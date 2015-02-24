#!/usr/bin/env perl

use uni::perl;
use Log::Any '$log';
use Log::Any::Adapter 'Stderr';

use Encode;
use Encode::Locale;

use Imager;
use Imager::ExifOrientation;

our $MASK = qr# \. jpe?g $ #xms;
our $DIR = '.preview';
our $SIZE = 1024;
our $QUALITY = 90;


for my $filename (glob '*') {
    next if !-f $filename;
    next if $filename !~ $MASK;

    $log->trace(decode locale_fs => $filename)  if $log->is_trace;

    my $image = Imager::ExifOrientation->rotate(path => $filename)
    or do {
        carp "unable to load $filename";
        next;
    };

    my $new_image = $image->scale(xpixels => $SIZE, ypixels => $SIZE, type => 'min');

    mkdir $DIR  if !-d $DIR;
    $new_image->write(file => "$DIR/$filename", type => 'jpeg', jpegquality => $QUALITY);
}

exit;


