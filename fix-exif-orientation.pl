#!/usr/bin/perl

use uni::perl;

use Getopt::Long qw/:config bundling/;
use File::Find;
use File::Glob qw(:globally :nocase);
use Image::ExifTool;
use Log::Any '$log';
use Log::Any::Adapter;


my $mask = '*.{jpg,jpeg}';

my @log_levels = qw/ info debug trace /;
my $log_level = 0;

GetOptions(
    'r|recursive!' => \my $recursive,
    'dry-run' => \my $dry_run,
    'v' => sub {$log_level++  if $log_level<@log_levels},
) or die "wrong params, stop";

Log::Any::Adapter->set('Stderr', log_level => $log_levels[$log_level-1])  if $log_level;

my $target = shift @ARGV || ".";
if (!-d $target) {
    ($target, $mask) = (".", $target);
}

if ($recursive) {
    find(\&process_dir, $target);
}
else {
    local $File::Find::name = $target;
    process_dir();
}

exit;



sub process_dir {
    my $dir = $File::Find::name;
    return if !-d $dir;

    $log->info("Searching $dir");
    for my $file (glob "$dir/$mask") {
        process_file($file);
    }

    return;
};


sub process_file {
    my ($file) = @_;

    my $exif = Image::ExifTool->new();
    $exif->ExtractInfo($file);
    my $info = $exif->GetInfo();

    my ($width, $height) = @$info{'ImageWidth', 'ImageHeight'};
    if (!$width || !$height) {
        $log->debug("  $file: broken dimensions, skipping");
        return;
    }
    if ($width >= $height) {
        $log->debug("  $file: horizontal");
        return;
    }
    my $of = $exif->GetValue('Orientation', 'ValueConv');
    if (!$of) {
        $log->debug("  $file: no orientation tag");
        return;
    }
    if ($of != 6 && $of != 8) {
        $log->debug("  $file: good orientation");
        return;
    }

    $log->info("Fixing $file");
    if ($dry_run) {
        say $file;
    }
    else {
        $exif->SetNewValue(Orientation => 1, Type => 'ValueConv');
        $exif->WriteInfo($file);
    }

    return;
}

