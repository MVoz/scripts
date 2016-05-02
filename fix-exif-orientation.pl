#!/usr/bin/perl

use uni::perl;

use Encode;
use Encode::Locale;
use Getopt::Long qw/:config bundling/;
use File::Find;
use File::Glob qw(:nocase);
use Log::Any '$log';
use Log::Any::Adapter;

use Image::ExifTool;

binmode STDERR, ':encoding(console_out)';
Encode::Locale::decode_argv();

my $mask = '*.{jpg,jpeg}';

my @log_levels = qw/ info debug trace /;
my $log_level = 0;

GetOptions(
    'r|recursive!' => \my $recursive,
    'dry-run' => \my $dry_run,
    'v' => sub {$log_level++  if $log_level<@log_levels},
) or die "wrong params, stop";

Log::Any::Adapter->set('Stderr', log_level => $log_levels[$log_level-1])  if $log_level;

my $target = encode locale_fs => shift @ARGV || ".";
if (!-d $target) {
    ($target, $mask) = (".", $target);
}

$log->trace("    starting from " . decode locale_fs => $target);

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
    my $dir_name = decode locale_fs => $dir;
#    $log->trace("    scanning $dir_name");
    return if !-d $dir;

    $log->info("Searching $dir_name");
    $log->trace(decode locale_fs => "$dir/$mask");
    for my $file (File::Glob::bsd_glob "$dir/$mask") {
        process_file($file);
    }

    return;
};


sub process_file {
    my ($file) = @_;
    my $file_name = decode locale_fs => $file;
    $log->trace("    processing $file_name");

    my $exif = Image::ExifTool->new();
    $exif->ExtractInfo($file);
    my $info = $exif->GetInfo();

    my ($width, $height) = @$info{'ImageWidth', 'ImageHeight'};
    if (!$width || !$height) {
        $log->debug("  $file_name: broken dimensions, skipping");
        return;
    }
    if ($width >= $height) {
        $log->debug("  $file_name: horizontal");
        return;
    }
    my $of = $exif->GetValue('Orientation', 'ValueConv');
    if (!$of) {
        $log->debug("  $file_name: no orientation tag");
        return;
    }
    if ($of != 6 && $of != 8) {
        $log->debug("  $file_name: good orientation");
        return;
    }

    $log->info("Fixing $file_name");
    if ($dry_run) {
        say $file;
    }
    else {
        $exif->SetNewValue(Orientation => 1, Type => 'ValueConv');
        $exif->Options(IgnoreMinorErrors => 1);
        my $result = $exif->WriteInfo($file);
        $log->debug("Write result: $result");
        $log->info("Write failed: " . $exif->GetValue('Error'))  if !$result;
    }

    return;
}

