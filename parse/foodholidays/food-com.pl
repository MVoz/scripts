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

my $base_url = "http://www.food.com/rzfoodservices/web/food-holidays/getCalendarMarkup?cal=";

my @months = map {sprintf '%02d2015', $_} (1 .. 12);

my @items;
for my $month (@months) {
    my $json = cached_get($base_url . $month);
    my $html = decode_json($json)->{calendarMarkup};

    my $p = HTML::TreeBuilder->new();
    $p->parse($html);

    # <td class="vevent"><abbr class="edfh-cal-daynum dtstart" title="2015-01-16"><span class="visuallyhidden">January </span>16</abbr><a class="summary" href="http://www.food.com/food-holidays/fig-newton-day-0116">Fig Newton Day</a></td>
    for my $item ( $p->find("td") ) {
        my ($date) = map {$_->attr('title')} $item->find('abbr');
        my ($anc) = $item->find('a')  or next;
        my $name = $anc->as_text();
        my $href = $anc->attr('href');

        push @items, {
            date => $date,
            name => $name,
            href => $href,
        };
    }
}



my $csv = Text::CSV_XS->new({ eol => $/ });
my $file;
$csv->print(\*STDOUT, ["Start Date", "Subject", "Description"]);

for my $item ( @items ) {
    $csv->print(\*STDOUT, [$item->{date}, $item->{name}, $item->{href}]);
}


exit;






