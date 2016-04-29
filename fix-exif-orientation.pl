#!/usr/bin/perl

use uni::perl;

use Getopt::Long;
use File::Find;
use File::Glob qw(:globally :nocase);
use Image::ExifTool;
use Log::Any '$log';


my $mask = '*.{jpg,jpeg}';


GetOptions(
    'r|recursive!' => \my $recursive,
    'dry-run' => \my $dry_run,
) or die "wrong params, stop";

my $target = shift @ARGV || ".";
if (!-d $target) {
    ($target, $mask) = (".", $target);
}

if ($recursive) {
    find(\&process_dir, $target);
}
else {
    local $File::Find::name = ".";
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
    if (!$dry_run) {
        $exif->SetNewValue(Orientation => 1, Type => 'ValueConv');
        $exif->WriteInfo($file);
    }

    return;
}

