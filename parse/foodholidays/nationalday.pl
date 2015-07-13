#!/usr/bin/env perl

=head1 DESCRIPTION

Steal

=cut

use uni::perl;

use FindBin '$Bin';
use lib "$Bin/../../lib";

use Log::Any::Adapter 'Stderr';

use CachedGet;
use JSON;
use HTML::TreeBuilder;
use Text::CSV_XS;

my $base_url = "http://nationaldaycalendar.com/calendar-at-a-glance/";
my @months = qw/ January February March April May June July August September October November December /;
my %month_num = map {state $n; ($_ => ++$n)} @months;

my @items;

my $p = HTML::TreeBuilder->new();
$p->parse(cached_get($base_url));
for my $month_node ( $p->find("h3") ) {
    my ($year) = $month_node->as_text() =~ /(\d+)/xms  or next;
    my ($month) = $month_node->as_text() =~ /(\w+)/xms  or next;
    my ($url) = map {$_->attr('href')} $month_node->find("a")  or next;

    my $pp = HTML::TreeBuilder->new();
    $pp->parse(cached_get($url));
    my ($base_node) = $pp->look_down(_tag => 'div', class => "entry");

    my $date;
    for my $child_node ($base_node->content_list()) {
        next if !ref $child_node;
        if ($child_node->tag() eq 'p') {
            $date = $child_node->as_text();
            next;
        }

        for my $event_node ($child_node->look_down(_tag => 'a', target => '_blank')) {
            my ($day) = $date =~ /(\d+)/xms;
            next if !$day;
            push @items, {
                date => sprintf('%04d-%02d-%02d', $year, $month_num{$month}, $day),
                name => $event_node->as_text(),
                href => $event_node->attr('href'),
            };
        }
    }
}




my $csv = Text::CSV_XS->new({ eol => $/ });
my $file;
$csv->print(\*STDOUT, ["Start Date", "Subject", "Description"]);

for my $item ( @items ) {
    $csv->print(\*STDOUT, [$item->{date}, $item->{name}, $item->{href}]);
}


exit;






