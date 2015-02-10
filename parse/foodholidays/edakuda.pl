#!/usr/bin/env perl

=head1 DESCRIPTION

Steal

=cut

use uni::perl;
use lib::abs "../../lib";

use CachedGet;

use Carp;
use Encode;

use Log::Any::Adapter 'Stderr';

use HTML::TreeBuilder;
use Memoize;
use Text::CSV_XS;




my $cache_dir = '.';
my $top_url = 'http://www.edakuda.ru';
my $base_url = "$top_url/news/foodholidays/?from=";
my $step = 9;
my $max_page = 410;


my @items;
my $page = 0;

while ( $page < $max_page ) {
    my $p = HTML::TreeBuilder->new();
    $p->parse(cached_get($base_url . $page));

    for my $item ( $p->find_by_attribute(class => 'share_buttons') ) {
#        <div class="medium darkgray">31 декабря</div>
#        <div class="mainpage_picture_header"><a href="/news/1035-den-shampanskogo/">День «Шампанского»</a></div>
        my ($date) = map {$_->as_text()} $item->find_by_attribute(class => 'medium darkgray');
        my ($anc) = $item->find('a');
        my $name = $anc->as_text();
        my $href = $anc->attr('href');

        push @items, {
            date => $date,
            name => $name,
            href => $href,
        };
    }

    $page += $step;
}



my $csv = Text::CSV_XS->new({ eol => $/ });
my $file;
$csv->print(\*STDOUT, ["Start Date", "Subject", "Description"]);

for my $item ( sort {_sort_key($a) cmp _sort_key($b)} @items ) {
    $csv->print(\*STDOUT, [_parsed_date($item->{date}), $item->{name}, "$top_url$item->{href}"]);
}


exit;


sub _parsed_date {
    my ($date_str) = @_;
    state $month = do {
        my @m = qw/января февраля марта апреля мая июня июля августа сентября октября ноября декабря/;
        my %m = map {( $m[$_] => $_+1)} (0 .. $#m);
        \%m;
    };

    my ($mon_str, $day) = reverse split /\s+/, $date_str;
    my $mon = $month->{$mon_str}  or carp "Bad month $mon_str";
    my $date = sprintf "%04d-%02d-%02d", 2015, $mon, $day;
    return $date;
}


BEGIN {
memoize '_sort_key'; 
sub _sort_key {
    my ($item) = @_;
    my $key = join q{-}, _parsed_date($item->{date}), $item->{name};

    return $key;
}
}





