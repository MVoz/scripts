#!/usr/bin/perl

use 5.010;
use uni::perl;

use List::Util qw/ first /;
use Getopt::Long;
use Image::ExifTool;

use YAML;

our $FFMPEG = 'ffmpeg64';

our %target_info = (
    5530 => {
        ext => 'mp4',
        width => 320,
        height => 180,
        quantum => 8,
        opt => '-f mp4 -vcodec mpeg4 -q:v 8 -acodec aac -b:a 96000 -ac 2 -strict -2',
    },
    '5530h' => {
        ext => 'mp4',
        width => 640,
        height => 360,
        quantum => 8,
        opt => '-f mp4 -vcodec mpeg4 -q:v 8 -acodec aac -b:a 96000 -ac 2 -strict -2',
    },
    5500 => {
        ext => 'mp4',
        width => 208,
        height => 208,
        quantum => 8,
        opt => '-f mp4 -vcodec mpeg4 -q:v 8 -acodec aac -b:a 64000 -ac 1 -strict -2',
    },
    tablet => {
        ext => 'mp4',
        width => 400,
        height => 240,
        quantum => 8,
        opt => '-f mp4 -vcodec mpeg4 -q:v 8 -acodec aac -b:a 96000 -ac 1 -strict -2',
    },
    ipad => {
        ext => 'mp4',
        width => 640,
        height => 480,
        quantum => 8,
        opt => '-f mp4 -vcodec libx264 -crf 20 -acodec aac -b:a 160000 -ac 2',
#        opt => '-acodec aac -ab 160000 -vcodec libx264 -coder 1 -flags "+loop" -cmp "+chroma" -partitions "+parti8x8+parti4x4+partp8x8+partb8x8" -me_method umh -subq 8 -me_range 16 -g 250 -keyint_min 25 -sc_threshold 40 -i_qfactor 0.71 -b_strategy 2 -qcomp 0.6 -qmin 10 -qmax 51 -qdiff 4 -bf 3 -refs 5 -direct-pred auto -trellis 1 -flags2 +bpyramid+mixed_refs+wpred+dct8x8+fastpskip -wpredp 2 -rc_lookahead 50 -coder 0 -bf 0 -refs 1 -flags2 -wpred-dct8x8 -level 30 -maxrate 10000000 -bufsize 10000000 -wpredp 0 -b 1000kb -threads 0',
    },
);


GetOptions(
    'i=s' => \my $infile,
    't=s' => \my $target_code,
    'ff=s' => \$FFMPEG,
    'extra=s' => \my $extra_opt,
);


$target_code //= shift @ARGV;
$infile //= shift @ARGV;

die 'no infile'  if !$infile;
die 'no target'  if !$target_code;


my $target = $target_info{$target_code};
my ( $t_width, $t_height ) = _calc_image_size($infile, $target);

mkdir $target_code  if !-d $target_code;

my $outfile = "$target_code/$infile";
$outfile =~ s/(?<=\.) \w+ $/$target->{ext}/xms;

my $cmd = qq{$FFMPEG -y -i "$infile" $target->{opt} -s ${t_width}x${t_height} ${\($extra_opt || q// )} "$outfile"};
say "Running: $cmd\n";
system $cmd;

exit;



sub _calc_image_size {
    my ($infile, $target) = @_;

    my $info = Image::ExifTool::ImageInfo($infile);
#    say Dump $info;
    my $src_width = first {$_} @$info{qw/ DisplayWidth ImageWidth /};
    my $src_height = first {$_} @$info{qw/ DisplayHeight ImageHeight /};

    my $q = $target->{quantum} || 8;

    my ( $t_width, $t_height ) = $src_width / $target->{width} > $src_height / $target->{height}
        ? ( $target->{width}, _round( $target->{width} * $src_height / $src_width => $q ) )
        : ( _round( $target->{height} * $src_width / $src_height => $q ), $target->{height} );

    return ( $t_width, $t_height );
}

sub _round {
    my ($n, $q) = @_;
    $q ||= 1;
    return int( $n/$q + 1/2 ) * $q;
}