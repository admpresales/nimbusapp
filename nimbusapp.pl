#!/usr/bin/env perl

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

use Time::Piece;
use Sort::Versions;

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';
use Term::ANSIColor;

no if $] < 5.024, qw( warnings experimental::postderef );
use feature 'postderef';

no warnings 'experimental::signatures';
use feature 'signatures';

use constant {
    RELEASE_VERSION => "CHANGEME_RELEASE",
    RELEASE_DATE    => "CHANGEME_DATE",
    COMPOSE_FILE    => 'docker-compose.yml',
    DEFAULT_TAG_COUNT => 10
};

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
        INSTALL => $ENV{NIMBUS_INSTALL_DIR} // dirname($0),
        DOWNLOAD => $ENV{NIMBUS_DOWNLOAD_URL} // 'https://github.com/admpresales/nimbusapp/releases/latest/download/nimbusapp' . ($isWin32 ? '.zip' : '.tar.gz'),
        HUB_API_BASE => $ENV{NIMBUS_HUB_API_BASE} // "https://hub.docker.com/v2",
        INTELLIJ_MOUNT_HOME => $ENV{NIMBUS_INTELLIJ_HOME} // catfile( $userHome, 'IdeaProjects_docker' ),
        INTELLIJ_MOUNT_M2   => $ENV{NIMBUS_INTELLIJ_MAVEN} // catfile( $userHome, '.m2' ),
        NL => $isWin32 ? "\r\n" : "\n"
    );
};

my %command = (
    help => sub {
        usage();
        exit @_ > 1;
    },
    version => sub {
        info("Release Version: ", RELEASE_VERSION);
        info("Release Date: ", RELEASE_DATE);
        0;
    },
    update => \&update_version,
    up => prompt_first('CONFIRM_RECREATE', \&docker_app_compose),
    down => prompt_first('CONFIRM_DELETE', \&docker_compose),
    render => \&docker_app,
    inspect => \&docker_app,
    tags => \&list_tags
);

$command{$_} = \&docker_compose for qw( pull start stop restart rm ps logs exec );

# Output functions
# Everything except docker-{compose,app} output goes to STDERR
#    This allows that output to be easily recorded or used in scripts
use subs qw(info debug warn error fatal usage);

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
sub warn    { _log  'WARN', @_; _output text_block('LABEL_WARN'), @_; }
sub error   { _log 'ERROR', @_; _output text_block('LABEL_ERROR'), @_; }
sub fatal   { _log 'FATAL', @_; _output text_block('LABEL_ERROR'), @_; exit 1; }
sub usage   { _log 'FATAL', @_; _output @_, (@_ ? $config{NL} : ''), text_block('USAGE'); exit 1; }

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

sub download($url, $context = 'Download error') {
    my $res = HTTP::Tiny->new->get($url);

    if (! $res->{success}) {
        fatal $context, $config{NL},
              "\t", join("\t", $url, $res->{status}, $res->{reason})
    }
    
    $res->{content};
}

sub update_version {
    my $archive = do {
        my $content = download $config{DOWNLOAD};
        
        my $temp = File::Temp->new(UNLINK => 0);
        print $temp $content;
        close($temp);

        $temp->filename;
    };

    debug("Temporary download location: ", $archive);
    debug("Extracting to: ", $config{INSTALL});

    my @extract = do {
        if ($config{WINDOWS}) {
            ('powershell', '-c', sprintf('Expand-Archive -Path "%s" -DestinationPath "%s"', $archive, $config{INSTALL}));
        }
        else {
            my $dest = catfile($config{INSTALL}, 'nimbusapp');
            ( (! -w $dest ? 'sudo' : ()), 'tar', 'xzf', $archive, '-C', $config{INSTALL});
        }
    };

    debug("Running: ", @extract);
    system(@extract);

    fatal "Failed to extract '$archive'. Status: $?" if $?;

    unlink($archive) if -f $archive
}

sub prompt($label, $params) {
    return if $config{FORCE} || $params->{cmd} eq 'up' && grep { /--force-recreate/ } $params->{args}->@*;

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
        my @settings = map { ('-s', s/^(.*?)=(.*)$/$1="$2"/r) } $params->{settings}->@*;
        
        make_path($params->{composeDir}) unless -d $params->{composeDir};

        my $temp = File::Temp->new(UNLINK => 0);

        my @command = ('docker-app', 'render', @settings, $params->{fullImage});
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
                warn "Image name contains an underscore which is not used by nimbusapp. ",
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
        my $rc = docker_app($cmd, $params, $args);
        return $rc if $rc;
    }

    unshift @$args, '-d' if $cmd eq 'up' && ! grep { $_ eq '--no-start' } @$args;

    my @compose = ( 'docker-compose', '-f', $params->{composeFile}, '-p', $params->{image}, $cmd, @$args );
    debug("Running: ", join ' ', @compose);
    system @compose;

    return 0;
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

    print "$_", $config{NL} for
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
        $params{$_} ||= $app->{$_} for qw(tag org);
    }

    return %params;
}

sub save_app_config(%params) {
    my $apps = read_app_config;

    $apps->{$params{image}} = {
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
if ($config{WINDOWS}) {
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
            warn text_block('MISSING_DNS', { file => $config{DAEMON_CONFIG} });
        }
    }
}

sub build_re {
    my $opts = join "|", @_;
    return qr/^($opts)$/;
}

my %re = (
    # Returns org, image, tag
    image => qr{
        ^(?:  (?<org>   [a-z0-9]{4,30}  ) \/ )?             # Optional org  (lowercase + numbers)
              (?<image> [a-z0-9][a-z0-9_.-]+ )              # Image         (lowercase + numbers + limited special)
         (?: :(?<tag>   [a-zA-Z0-9][a-zA-Z0-9_.-]+ ) )? $   # Optional tag  (lower/upper + numbers + limited special)
    }xx,
    
    # Options
    set => build_re(qw(-s --set)),
    debug => build_re(qw(-d --debug)),
    force => build_re(qw(-f --force)),
    quiet => build_re(qw(-q --quiet)),
    intellij_home => build_re('-v'),
    intellij_m2 => build_re('-m'),
    project => build_re('-p'),
    preserve_volumes => build_re('--preserve-volumes'),
    number => build_re(qw(-n --number)),
    latest => build_re(qw(--latest))
);

usage unless @ARGV;
_log 'CMD', join(' ', @ARGV);

if ($ARGV[0] =~ /^-?-?(help|version|update)$/) {
    exit ($command{$1}->() // 0);
}

my %params = do {
    if ($ARGV[0] =~ $re{image}) {
        shift;
        %+;
    }
    else {
        ();
    }
};

while (@ARGV > 0) {
    my $arg = shift;

    if ($arg =~ $re{set}) {
        push $params{settings}->@*, shift;
    }
    elsif ($arg =~ $re{project}) {
        $params{project} = shift;
    }
    elsif ($arg =~ $re{latest}) {
        $params{latest} = 1;
    }
    elsif ($arg =~ $re{number}) {
        $params{number} = shift;
    }

    # Volumes
    elsif ($arg =~ $re{intellij_home}) {
        $params{intellij_home} = 1;
    }
    elsif ($arg =~ $re{intellij_m2}) {
        $params{intellij_m2} = 1;
    }
    elsif ($arg =~ $re{preserve_volumes}) {
        $params{preserve_volumes} = 1;
    }

    # Global configurations
    elsif ($arg =~ $re{debug}) {
        $config{DEBUG}++;
    }
    elsif ($arg =~ $re{force}) {
        $config{FORCE}++;
    }
    elsif ($arg =~ $re{quiet}) {
        $config{QUIET}++;
    }

    elsif (defined $command{$arg}) {
        if (not defined $params{project}) {
            if (not defined $params{image}) {
                usage("No image or project specified.");
            }

            $params{project} = $params{image};
        }

        %params = load_app_config(%params);

        usage("No image found.") if not defined $params{image};

        $params{org} //= $config{DEFAULT_ORG};
        $params{composeDir} = catfile($config{CACHE}, $params{image});
        $params{composeFile} = catfile($params{composeDir}, COMPOSE_FILE);
        $params{cmd} = $arg;
        $params{originalImage} = $params{image};
        $params{args} = [ @ARGV ];

        if ($arg ne 'tags') {
            fatal text_block('MISSING_VERSION', \%params) if not defined $params{tag};
            $params{fullImage} = sprintf "%s/%s.dockerapp:%s", @params{qw(org image tag)};
            info 'Using: ', $params{fullImage};
        }

        my $rc = $command{$arg}->($arg, \%params, \@ARGV);
        save_app_config(%params) if $rc == 0;
        exit $rc;
    }
    else {
        usage "Unknown option: $arg";
    }
}

usage "No command found";

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

CONFIRM_DELETE => q{
[% bold %]This action will [% red %]DELETED[% reset %][% bold %] your containers and is [% red %]IRREVERSIBLE[% reset %]!

[% bold %]You may wish to use [% reset %]`nimbusapp [% originalImage %] stop'[% bold %] to shut down your containers without deleting them[% reset %]
    
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
    version  Prints version information

Command Options:
    up  --no-start       Create containers without starting them
        --force-recreate Force all containers to be re-created
        --no-recreate    Do not allow any containers to be re-created
}
}
}