#!/usr/bin/env perl

=head1 DESCRIPTION

Steal

=cut

use uni::perl;

use FindBin '$Bin';
use lib "$Bin/../../lib";

use Log::Any::Adapter 'Stderr';

use CachedGet;
use HTML::TreeBuilder;
use LWP::UserAgent;
use Path::Tiny;

my $base_url = "http://arch.rgdb.ru/xmlui/handle/123456789";
my $img_url  = "http://arch.rgdb.ru/xmlui/bitstream/handle/123456789";


my $target = $ARGV[0];
my ($code) = $target =~ /(\d+)\D*$/;

process_item($code);



sub process_item {
    my ($code) = @_;

    my $p = HTML::TreeBuilder->new();
    my $html = cached_get("$base_url/$code");
    my ($first_num, $ext) = $html =~ m#$code/(0+1).(\w+)\?sequence=\d#;
    die "Image sequence not detected"  if !$first_num;

    $p->parse($html);

    my $title = $p->find("h2")->as_text();
    my $author = eval { $p->look_down(_tag => 'span', class => "authors")->as_text() } || 'Nobody';
    my $year = eval {$p->look_down(_tag => 'span', class => "pubdate")->as_text() } || 'unk';

    my $dir = "$author - $title ($year)";
    mkdir $dir;

    say $dir;

    my $file_mask = "%0" . length($first_num) ."d.$ext";
    for my $n (1 .. 9999) {
        my $filename = sprintf $file_mask, $n;
        my $url = "$img_url/$code/$filename";
        my $file = "$dir/$filename";

        say $url;
        next if -f $file;

        state $ua = LWP::UserAgent->new();
        my $resp = $ua->get($url);
        last if $resp->code == 404;
        die "$resp->code $resp->message"  if !$resp->is_success;

        my $content = $resp->decoded_content;
        die "Text instead of data" if utf8::is_utf8($content);
        path($file)->spew_raw($content);
    }

    return;
}







