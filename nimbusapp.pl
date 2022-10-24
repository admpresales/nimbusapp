#!/usr/bin/env perl
use constant START_LINE => __LINE__ - 2;

use 5.020;
use strict;
use warnings;

use File::Temp qw();
use File::Copy qw(move);
use File::Slurp qw(read_file write_file);
use File::Spec::Functions qw(catfile);
use File::Path qw(make_path);
use File::Basename qw(basename dirname);

use JSON::Tiny qw(encode_json decode_json); # HTTP responses, docker + nimbus config
use YAML::Tiny;     # Docker compose
use HTTP::Tiny;     # Download update, tags
use Template::Tiny; # Text content

use Getopt::Long;
use Time::Piece;
use Sort::Versions;
use Term::ANSIColor;

use if $^O eq 'MSWin32',   'Win32::Console::ANSI';
use if $^O eq 'MSWin32', qw'Win32::ShellQuote quote_system';

use experimental qw(postderef lexical_subs signatures);

use constant {
    RELEASE_VERSION => "CHANGEME_RELEASE",
    RELEASE_DATE    => "CHANGEME_DATE",
    COMPOSE_FILE    => 'docker-compose.yml',
    DEFAULT_TAG_COUNT => 10
};

# Add handlers for die/warn when distributed via FatPack
if (START_LINE != 0) {
    $SIG{__DIE__} = sub {
        die $_[0] =~ s/line (\d+).$/"$& (Source:" . ($1 - START_LINE) . ')'/re;
    };

    $SIG{__WARN__} = sub {
        warn $_[0] =~ s/line (\d+).$/"$& (Source:" . ($1 - START_LINE) . ')'/re;
    };
}

my %config = do {
    my $isWin32 = $^O eq 'MSWin32';
    my $userHome = $ENV{HOME} // $ENV{USERPROFILE};
    my $nimbusHome = $ENV{NIMBUS_HOME} // $ENV{NIMBUS_BASEDIR} //
        catfile( 
            $userHome // fatal("Could not determine home directory.\n"), 
            ".nimbusapp" 
        );

    make_path($nimbusHome) unless -d $nimbusHome;

    (
        WINDOWS => $isWin32,
        DEFAULT_ORG => $ENV{NIMBUS_DEFAULT_ORG} // "admpresales",
        APPS_CONFIG => $ENV{NIMBUS_CONFIG} // catfile($nimbusHome, 'apps.json'),
        APPS_OLD_CONFIG => $ENV{NIMBUS_OLD_CONFIG} // catfile($nimbusHome, 'apps.config'),
        CACHE => $ENV{NIMBUS_CACHE} // catfile($nimbusHome, 'cache'),
        DEBUG => $ENV{NIMBUS_DEBUG} // 0,     # Be verbose
        FORCE => $ENV{NIMBUS_FORCE} // 0,     # Skip prompts
        QUIET => $ENV{NIMBUS_QUIET} // 0,     # Be quiet
        DAEMON_CONFIG => $isWin32 ? 'C:\ProgramData\Docker\config\daemon.json' : '/etc/docker/daemon.json',
        LOG_FILE => $ENV{NIMBUS_LOG} // catfile($nimbusHome, 'nimbusapp.log'),
        INSTALL  => $ENV{NIMBUS_INSTALL_DIR} // dirname($0),
        DOWNLOAD => $ENV{NIMBUS_DOWNLOAD_URL} // 'https://github.com/admpresales/nimbusapp/releases/latest/download/nimbusapp' . ($isWin32 ? '.zip' : '.tar.gz'),
        HUB_API_BASE => $ENV{NIMBUS_HUB_API_BASE} // "https://hub.docker.com/v2",
        INTELLIJ_MOUNT_HOME => $ENV{NIMBUS_INTELLIJ_HOME} // catfile( $userHome, 'IdeaProjects_docker' ),
        INTELLIJ_MOUNT_M2   => $ENV{NIMBUS_INTELLIJ_MAVEN} // catfile( $userHome, '.m2' ),
        NL => $isWin32 ? "\r\n" : "\n",
        SAVE_APPS_CONFIG => $ENV{NIMBUS_SAVE_CONFIG} // 1,
    );
};

my %dispatch = (
    help => sub { usage(); },
    version => \&display_version,
    update => sub {
        display_version(); 
        prompt('CONFIRM_UPDATE');
        update_version();
    },
    up => prompt_first('CONFIRM_RECREATE', \&docker_app_compose),
    down => prompt_first('CONFIRM_DELETE', \&docker_compose),
    render => \&docker_app,
    inspect => \&docker_app,
    tags => sub {
        print join $config{NL}, list_tags(@_);
        print $config{NL};
    },
    cache => sub($cmd, $params, $args) {
        print $params->{tag}, $config{NL};
    },
    delete => \&delete_image,
    purge => \&purge_images,
);

# Compose pass-through
$dispatch{$_} = \&docker_compose for qw( pull start stop restart rm ps logs exec kill port events run top );


# Output functions
# Everything except docker-{compose,app} output goes to STDERR
#    This allows that output to be easily recorded or used in scripts
use subs qw(info debug warning error fatal usage);

sub _log {
    return if $ENV{NIMBUS_INTERNAL};
    my $logLevel = shift;
    my $t = localtime;
    open(my $fh, '>>', $config{LOG_FILE});
    printf $fh "%s %6s %s%s", $t->datetime, $logLevel, join('', @_), $config{NL};
    close($fh);
}

sub _output { print STDERR @_, $config{NL} unless $ENV{NIMBUS_INTERNAL}; }

sub debug   { _log 'DEBUG', @_; _output @_ if $config{DEBUG}; }
sub info    { _log  'INFO', @_; _output @_ unless $config{QUIET}; }
sub warning { _log  'WARN', @_; _output text_block('LABEL_WARN'), @_; }
sub error   { _log 'ERROR', @_; _output text_block('LABEL_ERROR'), @_; }
sub fatal   { _log 'FATAL', @_; _output text_block('LABEL_ERROR'), @_; exit 1; }
sub usage   { _log 'FATAL', @_; _output @_ ? (text_block('LABEL_ERROR'), @_, $config{NL}) : '', text_block('USAGE'); exit 1; }

# Load some text from the configuration document at the bottom of this file
# This keeps huge blocks of text out of the code, which may or may not be useful
#
# As this sub is used to handle error text, any errors should result in a 'die'
#   instead of using the program's standard 'fatal'
sub text_block($name, $params = {}) {
    state $text = load_text();
    state $template = Template::Tiny->new();
    state $formatting = {
        red => color('bold red'),
        yellow => color('bold yellow'),
        bold => color('bold'),
        reset => color('reset')
    };

    die "Unknown message template: ${name}.\n" unless $text->{$name};

    $params->@{keys %$formatting} = values %$formatting;

    $template->process(\$text->{$name}, $params, \my $output) || die sprintf "Template error (%s): %s\n", $name, $template->error;

    return $output;
}

sub run_command(@cmd) {
    @cmd = quote_system(@cmd) if $config{WINDOWS};
    debug("Running: @cmd");
    open(my $fh, '-|', @cmd) or die "Could not run $cmd[0]: $!\n";
    if (wantarray) {
        chomp(my @out = <$fh>);
        return @out;
    }
    else {
        local $/;
        return <$fh>;
    }
}

sub download($url, $context = 'Download error') {
    my $res = HTTP::Tiny->new->get($url);

    if (! $res->{success}) {
        fatal $context, $config{NL},
              "\t", join("\t", $url, $res->{status}, $res->{reason})
    }
    
    $res->{content};
}

sub display_version {
    info("Release Version: ", RELEASE_VERSION);
    info("Release Date: ", RELEASE_DATE);
    0;
}

sub update_version {
    my $archive = do {
        my $content = download $config{DOWNLOAD};
        
        my $temp = File::Temp->new(UNLINK => 0, suffix => $config{WINDOWS} ? '.zip' : '.tar.gz');
        print $temp $content;
        close($temp);

        $temp->filename;
    };

    debug("Temporary download location: ", $archive);
    debug("Extracting to: ", $config{INSTALL});
    my $nimbus_exe = catfile($config{INSTALL}, 'nimbusapp');

    my @extract = $config{WINDOWS}
            ?  quote_system('powershell', '-c', qq(Expand-Archive -Force -Path "$archive" -DestinationPath "$config{INSTALL}"))
            : ( (! -w $nimbus_exe || ! -w $config{INSTALL} ? 'sudo' : ()), 'tar', 'xzf', $archive, '--no-same-owner', '-C', $config{INSTALL} );

    debug("Running: @extract");
    system(@extract);

    fatal "Failed to extract '$archive'. Status: $?" if $?;

    unlink($archive) if -f $archive;

    my @version = ($nimbus_exe, '--version');
    debug("Running: @version");
    system(@version);
}

sub prompt($label, $params = {}) {
    return if $config{FORCE} || $params->{cmd} && $params->{args} && $params->{cmd} eq 'up' && grep { /--force-recreate/ } $params->{args}->@*;

    print STDERR text_block($label, $params) =~ s/[\n\r]+$//r, " [y/N] ";

    my $result = <STDIN>;
    chomp($result);

    _log 'PROMPT', $label, " = ", $result;

    exit if $result !~ /^y(es)?$/i;
}

sub prompt_first($label, $sub) {
    return sub {
        my $params = $_[1];

        if (nimbusapp($params, 'ps -q')) {
            local $params->{containers} = [ nimbusapp($params, 'ps --service --all') ];
            prompt($label, $params);
        }

        $sub->(@_);        
    };
}

sub nimbusapp($params, @args) {
    my @result = do {
        local $ENV{NIMBUS_INTERNAL} = 1; # Prevent recursive logging
        my $a = join ' ', @args;
        qx{perl "$0" "$params->{originalImage}" -q $a}
    };

    if (wantarray) {
        chomp @result;
        return @result;
    }
    else {
        return join '', @result;
    }
}

sub apply_mounts($params) {
    return unless $params->{intellij_home} || $params->{intellij_m2};
    fatal "Mounts are currently only available for Intellij" unless $params->{image} eq 'intellij';
    
    my $compose = YAML::Tiny->read( $params->{composeFile} );

    if ($params->{intellij_home}) {
        push $compose->[0]->{services}->{intellij}->{volumes}->@*,
            {
                type => 'bind',
                source => $config{INTELLIJ_MOUNT_HOME},
                target => '/home/demo/IdeaProjects'
            };
    }

    if ($params->{intellij_m2}) {
        push $compose->[0]->{services}->{intellij}->{volumes}->@*,
            {
                type => 'bind',
                source => $config{INTELLIJ_MOUNT_M2},
                target => '/home/demo/.m2'
            };
    }

    my $yaml = $compose->write_string( $params->{composeFile} );
    $yaml =~ s/'(true|false|null)'/$1/g;

    write_file( $params->{composeFile}, $yaml );
}

sub docker_app($cmd, $params, $args) {
    if ($cmd eq 'inspect') {
        my @command = ('docker-app', 'inspect', $params->{fullImage});
        debug("Running: ", join ' ', @command);
        system(@command) or exit $?;
    }
    else { # Render
        my @settings = map { 
            ('-s', sprintf '%s="%s"', $_, $params->{set}{$_})
        } keys $params->{set}->%*;
        
        make_path($params->{composeDir}) unless -d $params->{composeDir};

        my $temp = File::Temp->new(UNLINK => 0);

        my @command = ('docker-app', 'render', @settings, $params->{fullImage});
        @command = quote_system(@command) if $config{WINDOWS};
        debug("Running: ", join ' ', @command);
        open(my $app, '-|', @command) or fatal "Could not run docker-app: $! ($?)";

        while (defined(my $line = <$app>)) {
            print $temp $line;
        }

        close($app);     my $rc = $? >> 8;
        close($temp);

        if ($rc) {
            unlink($temp->filename);
            if ($params->{tag} =~ /^(.*?)_/) {
                warning "Image name contains an underscore which is not used by nimbusapp. ",
                      sprintf "Try using %s/%s:%s instead.", $params->{org}, $params->{image}, $1;
            }
            fatal "Could not render."
        }

        move $temp->filename, $params->{composeFile} or fatal "Error moving compose file: $!";
        apply_mounts($params);

        if ($cmd eq 'render') {
            print read_file $params->{composeFile};
        }
    }

    return 0;
}

sub docker_compose($cmd, $params, $args) {
    if (! -f $params->{composeFile}) {
        my $oldComposeFile = catfile($config{CACHE}, $params->@{qw(project org image tag)}, $params->{image} . '.yml');

        if (-f $oldComposeFile 
            && move($oldComposeFile, $params->{composeFile})) {
            
            info "Importing configuration from previous version of nimbusapp";
        }
        else {
            if ($!) {
                warning "Error importing old config: $!";
            }

            my $rc = docker_app($cmd, $params, $args);
            return $rc if $rc;
        }
    }
    
    if ($cmd eq 'up') {
        # Start in background by default (exclusive with --no-start)
        unshift @$args, '-d' unless grep { $_ eq '--no-start' || $_ eq '-d' } @$args;

        # Re-initialize anonymous volumes
        unshift @$args, '-V' unless $params->{preserve_volumes} || grep { $_ eq '-V' } @$args;

        # Remove orphan containers
        unshift @$args, '--remove-orphans' unless grep { $_ eq '--remove-orphans' } @$args;
    }

    if ($cmd eq 'down') {
        # Remove named an anonymous volumes with the container
        unshift @$args, '-v' unless $params->{preserve_volumes} || grep { $_ eq '-v' } @$args;

        # Remove orphan containers
        unshift @$args, '--remove-orphans' unless grep { $_ eq '--remove-orphans' } @$args;
    }

    my @compose = ( 'docker-compose', '-f', $params->{composeFile}, '-p', $params->{project}, $cmd, @$args );
    @compose = quote_system(@compose) if $config{WINDOWS};
    debug("Running: ", join ' ', @compose);
    system @compose;

    return 0;
}

sub delete_image($cmd, $params, $args) {
    $config{SAVE_APPS_CONFIG} = 0;
    $params->{composeFile} = catfile( dirname( $params->{composeFile} ), 'delete.yml');

    docker_app($cmd, $params, $args);

    my $compose = YAML::Tiny->read( $params->{composeFile} );

    my @images = 
        grep { qx(docker images -q $_) }
        map { $_->{image} }
        values $compose->[0]{services}->%*;

    unless (@images) {
        info "No images found.";
        return 0;
    }

    local $params->{images} = [ @images ];
    prompt('CONFIRM_IMAGE_DELETE', $params);

    my @command = ('docker', 'rmi', @images);
    @command = quote_system(@command) if $config{WINDOWS};
    
    debug("Running: ", join(@command));
    system(@command);
    
    return $?;
}

sub purge_images($cmd, $params, $args) {
    state sub split_image($i) { $i =~ qr/(.*?):(.*$)/ };

    my $compose = YAML::Tiny->read( $params->{composeFile} );
    my @images = map { $_->{image} } values $compose->[0]{services}->%*;

    my %keep = ();
    my @all = ();

    for my $image (@images) {
        my ($base, $tag) = split_image $image;

        if (not defined $keep{$base}) {
            my @ids = run_command(qw(docker image ls -q), $base);
            my $json = decode_json scalar run_command(qw(docker inspect), @ids);
            push @all, map { $_->{RepoTags}[0] } @$json;
        }

        $keep{$image} = 1;
    }

    my @remove =
        map { $_->[0] }
        sort { $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2] || $a->[3] <=> $b->[3] }
        map { [ $_, split_image($_) ] }
        grep { !$keep{$_} }
        @all;

    $params->{images} = [@remove];
    prompt('CONFIRM_IMAGE_DELETE', $params);

    say (qw(docker rmi), @remove);
}

sub docker_app_compose {
    my $rc = docker_app(@_);
    return $rc if $rc;
    return docker_compose(@_);
}

sub list_tags($, $params, $) {
    my $url = sprintf("%s/repositories/%s/%s.dockerapp/tags", $config{HUB_API_BASE}, $params->{org}, $params->{originalImage});
    my $n = $params->{latest} // $params->{number} // DEFAULT_TAG_COUNT;

    my $data = decode_json(download $url)->{results};

    return
        grep { $n-- > 0 }
        sort { versioncmp($b, $a) }
        map { $_->{name} }
        grep { $_->{name} !~ /-dev$/ } @$data;
}

sub read_app_config_json {
    if (-f $config{APPS_CONFIG}) {
        return decode_json(scalar read_file( $config{APPS_CONFIG} ));
    }

    return undef;
}

sub read_app_config_old {
    return undef unless -f $config{APPS_OLD_CONFIG};

    return {
        map {
            my %app;
            @app{qw(org image tag)} = $_->@[1..3];
            $_->[0] => \%app;
        }
        grep { @$_ == 4 }
        map { [ split qr/[\s:\/]/ ] }
        read_file( $config{APPS_OLD_CONFIG} )
    };
}

sub read_app_config {
    if (-f $config{APPS_CONFIG}) {
        read_app_config_json
    }
    elsif (-f $config{APPS_OLD_CONFIG}) {
        read_app_config_old
    }
    else {
        {};
    }
}

sub load_app_config(%params) {
    my $apps = read_app_config;

    if (defined(my $app = $apps->{$params{project}})) {
        $params{$_} ||= $app->{$_} for qw(image tag org);
        $params{image} = $app->{image} if $params{project} eq $params{image};
    }

    return %params;
}

sub save_app_config(%params) {
    my $apps = read_app_config;

    $apps->{$params{project}} = {
        map { $_ => $params{$_} } qw(image org tag)
    };

    write_file $config{APPS_CONFIG}, encode_json($apps);
}

sub get_dns_servers {
    grep { state %seen; !$seen{$_}++ } map { /DNS.*?:\s*(\d.*)/ } qx{netsh interface ip show config};
}

# States:
#   1  STOPPED
#   4  RUNNING
sub wait_for_docker($state) {
    while (1) {
        qx{sc.exe query docker} =~ /^\s* STATE \s* : \s* \d+ \s* (\w+)/imx;
        last if $1 eq $state;
        sleep 1;
    }
}

sub restart_docker {
    qx{sc.exe stop docker};
    wait_for_docker('STOPPED');
    qx{sc.exe start docker};
    wait_for_docker('RUNNING');
}

# Ensure docker networking is set up
# { "dns": [ "192.168.61.2" ] }
if ($config{WINDOWS} && ! -d dirname $config{DAEMON_CONFIG}) {
    warning "Could not find Docker configuration directory to check DNS settings.";
}
elsif ($config{WINDOWS}) {
    
    my $daemon = -f $config{DAEMON_CONFIG} ? decode_json( scalar read_file($config{DAEMON_CONFIG}) ) : {};

    if (!defined $daemon->{dns} || @{$daemon->{dns}} == 0) {
        info text_block('DNS_START', {});
        my @dns = get_dns_servers();

        if (@dns) {
            $daemon->{dns} = [ @dns ];
            write_file( $config{DAEMON_CONFIG}, encode_json($daemon) );
            info text_block('DNS_COMPLETE', { servers => [ @dns ], file => $config{DAEMON_CONFIG} });
            restart_docker();
        } else {
            warning text_block('MISSING_DNS', { file => $config{DAEMON_CONFIG} });
        }
    }
}

my $image_re = qr{
    ^(?<originalImage>
        (?:   (?<org>   [a-z0-9]{4,30}             ) \/ )?      # Optional org  (lowercase + numbers)
              (?<image> [a-z0-9][a-z0-9_.-]+       )            # Image         (lowercase + numbers + limited special)
        (?: : (?<tag>   [a-zA-Z0-9][a-zA-Z0-9_.-]+ )    )?      # Optional tag  (lower/upper + numbers + limited special)
    )$
}xx;

my %params = (
    debug => \$config{DEBUG},
    force => \$config{FORCE},
    quiet => \$config{QUIET},
    org => $config{DEFAULT_ORG},
    set => {}
);

usage unless @ARGV;
_log 'CMD', join(' ', @ARGV);

my $command;
{
    local $SIG{__WARN__} = \&usage;
    my sub dispatch_exit { exit ($dispatch{$_[0]}->(@_) // 0); }

    GetOptions( \%params, 
        'project|p=s',
        'intellij_home|v', 'intellij_m2|m', 'preserve_volumes',
        'debug|d', 'quiet|q', 'force|f',
        'number|n=i', 'latest',
        'set|s=s%',
        ( map { $_ => \&dispatch_exit } qw(help update version) ),
        '<>' => sub {
            state $image;
            if (!defined $image) {
                $image = shift;

                if ($image =~ /^(help|version|update)$/) {
                    dispatch_exit($1);
                }
                elsif ($image =~ $image_re) {
                    @params{keys %+} = values %+;
                }
                else {
                    usage "Invalid image format: $image";
                }
            }
            else {
                $command = shift;
                unshift @ARGV, '--'; # die('!FINISH');
            }
        }
    ) or usage "Error parsing command line options options.";
}

if (not defined $params{project}) {
    if (not defined $params{image}) {
        usage("No image or project specified.");
    }

    $params{project} = $params{image};
}

%params = load_app_config(%params);

usage("No image found.") if not defined $params{image};
$params{originalImage} ||= $params{image};
$params{composeDir} = catfile($config{CACHE}, $params{project});
$params{composeFile} = catfile($params{composeDir}, COMPOSE_FILE);
$params{cmd} = $command;
$params{args} = [ @ARGV ];

if (!defined $command) {
    usage "Please specify a command.";
}
elsif (!defined $dispatch{$command}) {
    usage "Unknown command: $command";
}
elsif (!defined($params{tag}) && $command ne 'tags') {
    if (defined $params{latest} && $params{latest}) {
        ($params{tag}) = list_tags(undef, \%params, undef);
    }
    else {
        fatal text_block('MISSING_VERSION', \%params);
    }
}

    $params{fullImage} = sprintf "%s/%s.dockerapp:%s", @params{qw(org image tag)};
info 'Using: ', $params{fullImage} unless $command eq 'tags' || $command eq 'render';

my $rc = $dispatch{$command}->($command, \%params, \@ARGV);
save_app_config(%params) if $config{SAVE_APPS_CONFIG} && $rc == 0;
exit $rc;

sub load_text {
return {
LABEL_WARN => '[% yellow %]WARNING:[% reset %] ',
LABEL_ERROR => '[% red %]ERROR:[% reset %] ',

DNS_START => 'No Docker DNS configuration found, attempting to configure DNS servers.',

DNS_COMPLETE => q{
Docker DNS servers have been configured to use the following addresses:
[% FOREACH server IN servers %]
    [% server %]
[% END %]

Docker DNS settings can be reviewed in [% file %]
},

MISSING_DNS => q{No DNS servers found, Docker containers may not be able to communicate with other servers.
Docker DNS settings can be found in [% file %]
},

MISSING_VERSION => q{No version number specified!

If this is your first time using [% originalImage %], please specify a version number:

nimbusapp [% originalImage %]:<version_number> [% cmd %]

The version number you choose will be remembered for future commands.
},

CONFIRM_UPDATE => '[% red %]Do you want to update your nimbusapp version?[% reset %]',

CONFIRM_DELETE => q{
[% bold %]This action will [% red %]DELETE[% reset %][% bold %] your containers and is [% red %]IRREVERSIBLE[% reset %]!

[% bold %]You may wish to use [% reset %]`nimbusapp [% originalImage %] stop'[% bold %] to shut down your containers without deleting them.[% reset %]
    
[% bold %]The following containers will be deleted:[% reset %]
[% FOREACH item IN containers -%]
    - [% item %]
[% END -%]

[% red %]Do you wish to DELETE these containers?[% reset %]
},

CONFIRM_RECREATE => q{
[% bold %]This action may cause one or more of your containers to be [% red %]DELETED[% reset %][% bold %] and [% red %]RECREATED[% reset %].

[% bold %]Recreating containers is normal when changing their configuration, such as image, tag or ports.[% reset %]

[% bold %]You may wish to use [% reset %]`nimbusapp [% originalImage %] start'[% bold %] to start your existing containers.[% reset %]

[% bold %]The following containers may be recreated:[% reset %]
[% FOREACH item IN containers -%]
    - [% item %]
[% END -%]

[% red %]Some or all containers may be recreated, do you wish to continue?[% reset %]
},

CONFIRM_IMAGE_DELETE => q{
[% bold %]This action will attempt to [% red %]DELETE[% reset %][% bold %] your images and is [% red %]IRREVERSIBLE[% reset %]!

[% bold %]Any images that are currently in use will not be deleted, use [% reset %]`nimbusapp <image> down`[% bold %] to delete containers before removing images.[% reset %]

[% bold %]The following images will be deleted:[% reset %]
[% FOREACH img IN images -%]
    - [% img %]
[% END -%]

[% red %]Do you wish to DELETE these images?[% reset %]
},

USAGE => q{
Usage: nimbusapp <IMAGE>[:<VERSION>] [OPTIONS] COMMAND [CMD OPTIONS]

Options:
    IMAGE       The Docker App file you wish to run. If no repository is provided, admpresales is assumed.
    VERSION     The version of the Docker App file you wish to run.
                Only required the first time a container is created, and will be cached for future use.
    -d, --debug Enable debugging output (use twice for verbose bash commands)
    -f, --force Skip all prompts - Use with caution, this option will happily delete your data without warning
    -s, --set   Enables you to set(override) default arguments
    --version   Print the version of nimbusapp and exit

Commands:
    down     Stop and remove containers
    help     Prints this help message
    inspect  Shows metadata and settings for a given application
    logs     Shows logs for containers
    ps       Lists containers
    pull     Pull service images
    render   Render the Compose file for the application
    rm       Remove stopped containers
    restart  Restart containers
    start    Start existing containers
    stop     Stop existing containers
    up       Creates and start containers
    delete   Deletes containers from a specific application version
    purge    Deletes old containers from the application
    cache    Prints the cached application version
    version  Prints version information

Command Options:
    up  --no-start       Create containers without starting them
        --force-recreate Force all containers to be re-created
        --no-recreate    Do not allow any containers to be re-created
}
}
}