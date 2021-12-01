#!/usr/bin/env perl

use strict;
use warnings;

use File::Path qw(make_path remove_tree);
use File::Spec::Functions qw(catfile);
use File::Copy qw(copy);
use Time::Piece;

use App::FatPacker;
use Archive::Tar;
use IO::Compress::Zip qw(zip $ZipError);

# Clean up after previous build
remove_tree('build');
make_path('build');

# Pre-process nimbusapp.pl
my %buildInfo = (
    DATE => localtime->ymd,
    RELEASE => shift // sprintf "DEV.%s", localtime->datetime,
);

{
    open my $in, '<:raw', 'nimbusapp.pl';
    open my $out, '>:raw', 'build/nimbusapp.pl';

    while (<$in>) {
        die "Input file contains carriage return at line $." if /\r/;
        s/CHANGEME_(\w+)/$buildInfo{$1}/eg;
        print $out $_;
    }

    close $in;
    close $out;
}

# Find modules to be packed in the final file
my @modules = ();
{
    open my $fh, '<', 'cpanfile' or die $!;

    while (<$fh>) {
        /^\s*requires\s*(['"])(.+?)\g1/ or next;
        push @modules, $2;
    }

    close $fh;
}

print "Packing with modules: @modules\n";

# Copy modules for packing
chdir 'build';

for my $module (@modules) {
    my @parts  = split /::/, $module;

    my $destFile = pop(@parts) . '.pm';
    my $destDir  = catfile 'fatlib', @parts;
    my $destPath = catfile $destDir, $destFile;

    my $srcPath = qx(perldoc -lm $module);
    chomp $srcPath;

    make_path($destDir);
    open my $in, '<:raw', $srcPath or die "Can't open $srcPath: $!";
    open my $out, '>:raw', $destPath or die "Can't open $destPath: $!";

    my $inPod = 0;
    my $blank = 0;
    my $size = 0;

    while (<$in>) {
        if (1) {
            last if /^__(END|DATA)__$/;

            next if /^\s*#/;
            next if /^\s*$/;

            $inPod = 1 if /^\s*(=\w+)/;
            if ($inPod) {
                $inPod = 0 if /=cut/;
                next;
            }
        }

        $size += length $out;
        print $out $_;
    }

    close $in;
    close $out;

    print "$module => $size\n";
}

# Build and pack final artifacts
{
    # system('fatpack file nimbusapp.pl > nimbusapp.packed.pl');
    my $packed = App::FatPacker->new->fatpack_file('nimbusapp.pl');
    open my $out, '>:raw', 'nimbusapp.packed.pl';
    print $out $packed;
}

print "\nBuild Complete:\n";
system("$^X ./nimbusapp.packed.pl version");
print "\n";

make_path('linux');
copy('nimbusapp.packed.pl', 'linux/nimbusapp');
chdir('linux');

my $tar = Archive::Tar->new();
$tar->add_files('nimbusapp');
$tar->chmod('nimbusapp', 755);
$tar->write('nimbusapp.tar.gz', COMPRESS_GZIP);

chdir('..');

make_path('win32');
copy('nimbusapp.packed.pl', 'win32/nimbusapp.pl');
copy('../nimbusapp.bat', 'win32');
chdir('win32');

zip [qw(nimbusapp.bat nimbusapp.pl)] => 'nimbusapp.zip' or die $ZipError;

chdir('..');

print "\nPackaging Complete.\n";
