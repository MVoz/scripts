#!/usr/bin/perl

use 5.018;
use Path::Tiny;

my @exts = qw/avi mp4 mkv/;

for my $ext (@exts) {
    my @files = glob "*.$ext";
    next if !@files;

    my $list = "$ext.list";
    my $lf = path($list);
    $lf->spew(map {"file '$_'\n"} @files);

    say "ffmpeg -f concat -safe 0 -i $lf -c copy merged.$ext";
    `ffmpeg -f concat -safe 0 -i $lf -c copy merged.$ext`;
}


