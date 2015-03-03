#!/usr/bin/env perl

use uni::perl;
use Log::Any '$log';
use Log::Any::Adapter 'Stderr';

use Encode;
use Encode::Locale;

use GD;
use Image::ExifTool qw/ImageInfo/;
use Image::ExifTool::Exif;
use List::Util qw/max/;
use File::Slurp;

our $MASK = qr# \. jpe?g $ #xms;
our $DIR = '.preview';
our $SIZE = 1024;
our $QUALITY = 90;


for my $filename (glob '*') {
    next if !-f $filename;
    next if $filename !~ $MASK;

    $log->trace(decode locale_fs => $filename)  if $log->is_trace;

    my $image = GD::Image->new($filename)
    or do {
        carp "unable to load $filename";
        next;
    };

    my ($width, $height) = $image->getBounds();
    my $factor = $SIZE / max($width, $height);

    my $scaled_image = GD::Image->new($width*$factor, $height*$factor, '1 truecolor');
    $scaled_image->copyResampled($image, 0, 0, 0, 0, $width*$factor, $height*$factor, $width, $height);

    my $new_image = _rotated_by_orientation($scaled_image, $filename);

    mkdir $DIR  if !-d $DIR;
    write_file "$DIR/$filename", $new_image->jpeg($QUALITY);
}

exit;


sub _rotated_by_orientation
{
    my ($image, $file) = @_;

    my $methods = _get_transforms_by_exif($file);
    for my $method (@$methods) {
        $image = $image->$method();
    }

    return $image;
}


sub _get_transforms_by_exif {
    my ($file) = @_;

    state $orientation_revers = +{ reverse %Image::ExifTool::Exif::orientation };
    state $rotate_map = {
        1 => [], # Horizontal (normal)
        2 => [qw/copyFlipHorizontal/], # Mirror horizontal
        3 => [qw/copyRotate180/], # Rotate 180 (rotate is too noisy)
        4 => [qw/copyFlipVertical/], # Mirror vertical
        5 => [qw/copyFlipHorizontal copyRotate270/], # Mirror horizontal and rotate 270 CW
        6 => [qw/copyRotate90/], # Rotate 90 CW
        7 => [qw/copyFlipHorizontal copyRotate90/], # Mirror horizontal and rotate 90 CW
        8 => [qw/copyRotate270/], # Rotate 270 CW
    };

    my $exif = ImageInfo($file);

    my $orient = $exif->{Orientation} || 'Normal';
    my $orient_code = $orientation_revers->{$orient} || 1;
    return $rotate_map->{$orient_code};
}


