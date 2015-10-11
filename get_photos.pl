#!/usr/bin/perl

use 5.010;
use strict;
use warnings;
use utf8;
use autodie;

use Getopt::Long;

use Encode;
use Encode::Locale;

use Win32;
use Win32::OLE qw/ in /;

use File::Find;
use File::Copy;
use File::Path;

use Image::ExifTool;

use List::Util qw/ first /;

use YAML::XS;


my $mode = 'copy';
my @dir_names = qw/ DCIM Images Videos Pictures /;


GetOptions(
    'move' => sub { $mode = 'move' },
);

binmode STDOUT, ':encoding(console_out)';

my $file_types = join q{|}, Image::ExifTool::GetFileType();
my $filename_re = qr/ .* \. (?: $file_types ) $ /ixms;


my @drives = in( Win32::OLE->new('Scripting.FileSystemObject')->Drives() );

DRIVE:
for my $drive ( @drives ) {
    next DRIVE if !$drive->{FileSystem};

    my $vol = $drive->{DriveLetter};

    BASE_DIR:
    for my $dir_name ( @dir_names ) {
        my $base_path = "$vol:/$dir_name";
        next BASE_DIR if !-d $base_path;

        my @files;
        my $grep_file = sub {
            my $n = $File::Find::name;
            return if !-f $n || $n !~ $filename_re;
            push @files, $n;
        };

        find( $grep_file, $base_path );

        FILE:
        for my $file ( sort @files ) {
            _process_file( $file );
        }
    }
}

exit;

sub _process_file {
    my ($file) = @_;
    say $file;

    my $info = Image::ExifTool::ImageInfo($file);
#    say Dump $info; exit;

    my @dates = grep {$_} map {$info->{$_}} qw/ DateTimeOriginal MediaCreateDate FileCreateDate /;
    my $target_file = _get_target_filename(\@dates, $file);

    if ( !$target_file ) {
        say ' -- skipping';
        return;
    }

    say " ---> $target_file";
    copy $file => encode locale_fs => $target_file;
    if ( $mode eq 'move' ) {
        die 'Copy failed!' if !-f $target_file;
        unlink $file;
    }

    return;
}


sub _get_target_filename {
    my ($dates_ref, $source_file) = @_;
#    state $mons = [ qw/ Nul Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec / ];
    state $mons = [ qw/ нул янв фев мар апр май июн июл авг сен окт ноя дек  / ];

    my ($ext) = map {lc $_} ( $source_file =~ / \. (\w+) $ /xms );

    my ($Y, $M, $D, $h, $m, $s);
    for my $date_str ( @$dates_ref ) {
        ($Y, $M, $D, $h, $m, $s) = $date_str =~ /(\d+)/gxms;
        last if $Y && $Y >= 2000;
    }

    return if !$Y || $Y < 2000;

    my $y = $Y - 2000;
    for my $n ( 0 .. 99 ) {
        my $suff = $n ? sprintf("_%02d", $n) : q{};
        # 100503_092408__03_май_2010.jpg
        my $path = "Cam_$Y";
        mkpath $path  if !-d $path;
        my $name = sprintf "$path/%02d%02d%02d_%02d%02d%02d__${D}_$mons->[$M]_$Y$suff.$ext", $y, $M, $D, $h, $m, $s;
        
        return $name  if !-f $name;
        return $name  if -s $name == -s $source_file;
    }

    return;
}
