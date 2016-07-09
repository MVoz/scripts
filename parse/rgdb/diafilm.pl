#!/usr/bin/env perl

=head1 DESCRIPTION

Steal

=cut

use uni::perl;

use FindBin '$Bin';
use lib "$Bin/../../lib";

use Log::Any::Adapter 'Stderr';

use Encode;
use Encode::Locale;
use Getopt::Long;

use CachedGet;
use HTML::TreeBuilder;
use LWP::UserAgent;
use Path::Tiny;
use URI;

my $base_url = "http://arch.rgdb.ru/xmlui/handle/123456789";
my $img_url  = "http://arch.rgdb.ru/xmlui/bitstream/handle/123456789";

my %type = (
    #"<a href="/xmlui/handle/123456789/27090">Диафильмы</a>",
    film => [_tag => 'a', href => '/xmlui/handle/123456789/27090'],
    mag  => [_tag => 'a', href => '/xmlui/handle/123456789/20027'],
    book => [_tag => 'a', href => '/xmlui/handle/123456789/27123'],
);


Encode::Locale::decode_argv();
binmode STDOUT, 'encoding(console_out)';
binmode STDERR, 'encoding(console_out)';

GetOptions(
    'd|base-dir=s' => \my $base_dir,
    'id=s' => \my @targets,
    'f|id-from=s' => \my $from,
    't|id-to=s' => \my $to,
    'n|num=i' => \my $num,
    'only=s' => \my $only,
) or die;

$base_dir ||= '.';
die "Invalid --only"  if $only && !$type{$only};


push @targets, @ARGV;
if ($from && $to) {
    push @targets, ($from .. $to);
}
elsif ($from && $num) {
    push @targets, ($from .. $from+$num-1);
}



for my $target (@targets) {
    my ($code) = $target =~ /(\d+)\D*$/;
    die "Invalid target $target" if !$code;

    process_item($code);
}



sub process_item {
    my ($code) = @_;

    my $p = HTML::TreeBuilder->new();
    my $html = eval { cached_get("$base_url/$code") };
    if (!$html) {
        say "Failed to get $base_url/$code, skipping";
        return;
    }

    $p->parse($html);

    my $title = $p->find("h2")->as_text();
    my $author = eval { $p->look_down(_tag => 'span', class => "authors")->as_text() } || 'Nobody';
    my $year = eval {$p->look_down(_tag => 'span', class => "pubdate")->as_text() } || 'unk';

    my $name = "$author - $title ($year)";
    $name =~ s#[\:\*\?\/\"\']#-#g;
    say "$code:  $name";

=zip
    if (my $zip_node = $p->look_down(_tag => 'a', href => qr/\.zip\?/)) {
        my $href = $zip_node->attr("href");
        $href =~ s/\?.*$//;
        my $file = "$base_dir/$name.zip";
        return if -f $file;

        my $zip_url = URI->new_abs($href, $base_url)->as_string;
        say $zip_url;        
        my $code = _download($zip_url => $file);
        die "HTTP code $code"  if $code;
        return;
    }
=cut

    my $dir = encode locale_fs => "$base_dir/$name";

    my @files = map {$_->attr('href') =~ m#/(\w+\.\w+)\?sequence#} $p->look_down(_tag => 'a', class => 'image-link');
    if (!@files) {
        say "No sequence found, skipping";
        return;
    }

    if ($only && !$p->look_down(@{$type{$only}})) {
        say "It's not a $only; skipping";
        return;
    }

    for my $filename (@files) {
        my $url = "$img_url/$code/$filename";
        my $file = "$dir/" . encode locale_fs => $filename;

        next if -f $file;
        say $url;

        mkdir $dir if !-d $dir;

        my $code = _download($url => $file);
        last if $code == 404;

        if ($code == 999) {
            say "Incomplete book; removing...";
            path($dir)->remove_tree;
            last;
        }   

        die "HTTP code $code"  if $code;
    }

    return;
}


sub _download {
    my ($url, $path) = @_;
    state $ua = LWP::UserAgent->new();

    my $resp = $ua->get($url);
    return $resp->code  if !$resp->is_success;

    my $content = $resp->decoded_content;
    return 999  if utf8::is_utf8($content);
    path($path)->spew_raw($content);

    return;
}




