#!/usr/bin/perl

use 5.018;
use Path::Tiny;

my @exts = qw/avi mp4 mkv mp3/;

my $mask = shift @ARGV || '*';

for my $ext (@exts) {
    my @files = glob "$mask.$ext";
    next if !@files;

    my $list = "$ext.list";
    my $lf = path($list);
    $lf->spew(map {"file '" . s/'/'\\''/gr ."'\n"} @files);

    my $out = join '_' => grep {$_} map {s/[*?]//gr} ($mask, 'merged');
    my $cmd = "ffmpeg -f concat -safe 0 -i $lf -c copy $out.$ext";
    `$cmd`;
    say $cmd;
}



