#!/usr/bin/env perl

=head1 DESCRIPTION

Steal

=cut

use uni::perl;

use FindBin '$Bin';
use lib "$Bin/../../lib";

use CachedGet;

use Carp;
use Encode;
use Encode::Locale;
use Getopt::Long;

use Log::Any '$log';
use Log::Any::Adapter 'Stderr';

use HTML::TreeBuilder;
use Date::Calc qw/Day_of_Week/;
use Date::Holidays::RU;
use POSIX qw/strftime/;


my %URL = (
    RU => 'http://calendar.yoip.ru/print/%04d-proizvodstvennyj-calendar.html',
    UA => 'http://calendar.yoip.ru/print/%04d-proizvodstvennyj-calendar-Ukraine.html',
);

my %FORMAT = (
    short => '%m%d',
    full => '%Y-%m-%d',
);


my $country = 'RU';
my $is_diff = 1;
my $format_code = 'short';

GetOptions(
    'c|country=s' => \$country,
    'diff!' => \$is_diff,
    'f|format=s' => \$format_code,
);

my $base_url = $URL{uc $country}  or die "bad country";
my $format = $FORMAT{$format_code}   or die "bad format"; 

binmode STDOUT, ':encoding(console_out)';

my @years = (2004 .. 2020);


my %correction;

for my $year (@years) {
    my $url = sprintf $base_url, $year;
    my $html = eval { cached_get $url };
    if (!$html) { carp $@; next }

    my $p = HTML::TreeBuilder->new();
    $p->parse($html);

    my $month;

    # <td style='padding:15px;'>
    for my $month_node ( $p->find_by_attribute(style => 'padding:15px;') ) {
        $month ++;
        for my $day_node( $month_node->find('td') ) {
            my $day = 0+$day_node->as_text();
            next if !$day;

            state $daytype = {
                ''      => 'workday',
#                success => 'workday',
                active  => 'short',
                danger  => 'dayoff',
                warning => 'dayoff',
            };
            my $type = $daytype->{$day_node->attr('class')};
            next if !$type; # !!!

            my $dow = Day_of_Week($year, $month, $day);
            my $is_weekend = $dow >= 6;

            my $day_key = sprintf "%02d%02d", $month, $day;
            my $yearly_holiday = $is_diff
                ? Date::Holidays::RU::_get_regular_holidays_by_year($year)->{$day_key}
                : '';

            carp sprintf "Incompatible: %04d-%02d-%02d is $yearly_holiday, but $type", $year, $month, $day
                if $yearly_holiday && $type ne 'dayoff';

            next if $is_weekend && $type eq 'dayoff';
            next if $yearly_holiday && $type eq 'dayoff';
            next if !$is_weekend && $type eq 'workday';

            #say sprintf "%04d-%02d-%02d: $type", $year, $month, $day;
            push @{$correction{$type}->{$year}}, [$year-1900, $month-1, $day];
            push @{$correction{workday}->{$year}}, [$year-1900, $month-1, $day]  if $is_weekend && $type eq 'short';
        }
    }
}


while ( my ($type, $dates) = each %correction ) {
    say $type;
    for my $year (sort keys %$dates) {
        my $dates = $dates->{$year};
        say "$year => [ qw( " . join(q{ }, map {strftime($format, 0,0,0, reverse @$_)} @$dates) . " ) ],";
    }
}

exit;




