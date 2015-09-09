#!/usr/bin/env perl

use uni::perl;
use Encode;
use Encode::Locale;

use Date::Calc qw(:all);
use Math::Round qw/nearest/;
use Getopt::Long;

use Date::Holidays::RU qw/is_business_day/;
use List::Util qw/first/;
use List::MoreUtils qw/none/;

use Log::Any '$log';
use Log::Any::Adapter;


our $QUANTUM = 0.00001;

our %PERC_SUB = (
    at_the_end => sub {0},
    first_day_of_month => sub { shift->[2] == 1 },
    first_day_of_quarter => sub { my $d = shift; $d->[2] == 1 && $d->[1] %3 == 1 },
    last_business_day_of_month => \&is_last_business_day_of_month,
); 
$PERC_SUB{monthly} = $PERC_SUB{last_business_day_of_month};

my %opt;
Encode::Locale::decode_argv();
GetOptions(
    'trace' => sub { Log::Any::Adapter->set('Stderr') },
    'start|from=s' => \$opt{start},
    'finish|to=s' => \$opt{finish},
    'rate=f' => \$opt{rate},
    'rate-change=s%' => ($opt{rate_change} //= {}),
    'days|period=i' => \$opt{days},
    'sum=f' => \$opt{sum},
    'mode=s' => \$opt{perc_mode},
    'replenishment|repl=f%' => sub { $opt{replenishments}->{_date_key(_date_from_key($_[1]))} += $_[2] },
    'quantum=f' => \$QUANTUM,
    'currency=s' => \$opt{currency},
);

say sprintf 'Finally: %.2f', dep_calc(%opt);
exit;


=example
say dep_calc(
    start => [2015, 2, 18],
    rate => 18.2,
    days => 121,
    sum => 30_000,
    perc_mode => 'first_day_of_month',
    replenishments => {
        '2015-02-19' => 170_000,
    },
);
=cut

sub dep_calc {
    my %opt = @_;
    
    my $rate = $opt{rate}  or croak 'no rate';
    my $start = _date_from_key($opt{start}) || [Today()];
    my $finish = _date_from_key($opt{finish}) || [Today()];
    my $num_days = $opt{days} || Delta_Days(@$start, @$finish);
    
    my $sum = $opt{sum} || 0;
    my $sum_perc = 0;
    my $sum_tax = 0;

    my $perc_mode = $opt{perc_mode} || 'at_the_end';
    my $perc_sub = _get_perc_sub($perc_mode, start => $start);

    my $repl = _make_date_hash($opt{replenishments});
    my $rate_change = _make_date_hash($opt{rate_change});

    $log->trace(sprintf "%s: %.2f  ($num_days days, $rate%%, $perc_mode)", _date_key($start), $sum)  if $log->is_trace;

    for my $step_day ( 1 .. $num_days ) {
        my $date = [Add_Delta_Days(@$start, $step_day)];
        my $date_key = _date_key($date);

        $rate = $rate_change->{$date_key}  if exists $rate_change->{$date_key};

        my $d_perc = $sum * ($rate/100 / (365+!!leap_year($date->[0])));
        $sum_perc += $d_perc;
        $sum_tax += $d_perc * _get_RU_tax_rate($date, $rate, $opt{currency});

        $log->trace(
            sprintf "%s: %.2f   %%: +%.2f -> %.2f   tax: %.2f",
            _date_key($date), $sum, $d_perc, $sum_perc, $sum_tax
        )  if $log->is_trace;

        if ( $repl->{$date_key} ) {
            $sum += $repl->{$date_key};
            $log->trace(sprintf "            +%.2f -> %.2f", $repl->{$date_key}, $sum)  if $log->is_trace;
        }

        if ($perc_sub->($date) || $step_day==$num_days) {
            $sum += $sum_perc - $sum_tax;
            $sum_perc = 0;
            $sum_tax = 0;
            $log->trace(sprintf "            %.2f   %%: %.2f", $sum, $sum_perc)  if $log->is_trace;
        }

    }

   return $sum + $sum_perc; 
}


sub _get_perc_sub {
    my ($mode, %opt) = @_;

    if (my ($day) = $mode =~ /^monthly[-_]at[-_](\d+)$/xms ) {
        return sub {
            my ($y, $m, $d) = @{shift()};
            return 1  if $d == $day;
            return 1  if $d == 1 && $day < 1;
            my $maxd = Days_in_Month($y, $m);
            return 1  if $d == $maxd && $day > $maxd;
            return 0;
        };
    }

    if (my ($interval) = $mode =~ /^every[-_](\d+)[-_]days?$/xms ) {
        return sub {
            my $delta = Delta_Days(@{$opt{start}}, @{shift()});
            return 1  if $delta > 0 && !($delta % $interval);
            return 0;
        }
    }

    my $sub = $PERC_SUB{$mode};
    croak "wrong perc_mode: $mode"  if !$sub;

    return $sub;
}


sub _date_key {
    my ($date) = @_;
    return $date  if !ref $date;
    return sprintf "%04d-%02d-%02d", @$date;
}

sub _date_from_key {
    my ($key) = @_;
    return if !$key;
    return $key  if ref $key;

    my @date;
    if (@date = $key =~ /(\d{4})-(\d{1,2})-(\d{1,2})/xms) {}
    elsif (@date = reverse ($key =~ /(\d{1,2}).(\d{1,2}).(\d{4})/xms)) {}
    elsif (@date = reverse ($key =~ /(\d{1,2}).(\d{1,2}).(\d{2})/xms)) { $date[0] += $date[0] > 50 ? 1900 : 2000 }
    elsif (@date = _parse_RU_date($key)) {}
    else { croak "unreadable date: $key" }

    croak "invalid date: $key"  if !check_date(@date);
        
    return \@date;   
}


sub _make_date_hash {
    my ($shash) = @_;
    $shash //= {};

    my %hash;
    while (my ($skey, $val) = each %$shash) {
        my $key = _date_key(_date_from_key($skey));
        $hash{$key} = $val;
    }

    return \%hash;
}


sub is_last_business_day_of_month {
    my ($date) = @_;
    my ($y, $m, $d) = @$date;

    return q{}  if !is_business_day($y, $m, $d);

    my $maxd = Days_in_Month($y, $m);
    return 1  if $d == $maxd;

    return 1  if none {is_business_day($y, $m, $_)} ($d+1 .. $maxd);

    return 0;
}


sub _parse_RU_date {
    my ($date) = @_;
    
    state $months_gen = [ qw/ января февраля марта апреля мая июня июля августа сентября октября ноября декабря / ];
    state $months_3l = [ qw/ янв фев мар апр май июн июл авг сен окт ноя дек / ];
    state $month_by_name = +{
        (map {($months_gen->[$_] => $_+1)} (0 .. $#$months_gen)),
        (map {($months_3l->[$_] => $_+1)} (0 .. $#$months_3l)),
    };
    state $month_re = join q{|}, @$months_gen, @$months_3l;
    state $date_re = qr/ \b (\d{1,2}) \s+ ($month_re) \s+ (\d{4}) (?= \b | г) /xms;

    if (my ($d, $mname, $y) = $date =~ $date_re) {
        return ($y, $month_by_name->{$mname}, $d);
    }

    return;
}


sub _get_RU_bank_rate {
    my ($date) = @_;

    state $bank_rate_changes = [
        # http://www.operbank.ru/stavka-refinansirovaniya-4.html
        sort {$b->[0] cmp $a->[0]}
        map {[ _date_key([_parse_RU_date($_->[0])]) => $_->[1] ]}
        (
            ['с 14 сентября 2012 г.' => 8.25],
            ['с 26 декабря 2011 г.' => 8],
            ['с 3 мая 2011 г.' => 8.25],
            ['с 28 февраля 2011 г.' => 8],
            ['с 1 июня 2010 г.' => 7.75],
            ['с 30 апреля 2010 г.' => 8],
            ['с 29 марта 2010 г.' => 8.25],
            ['с 24 февраля 2010 г.' => 8.5],
            ['с 28 декабря 2009 г.' => 8.75],
            ['с 25 ноября 2009 г.' => 9],
            ['с 30 октября 2009 г.' => 9.5],
            ['с 30 сентября 2009 г.' => 10],
            ['с 15 сентября 2009 г.' => 10.5],
            ['с 10 августа 2009 г.' => 10.75],
            ['с 13 июля 2009 г.' => 11],
            ['с 5 июня 2009 г.' => 11.5],
            ['с 14 мая 2009 г.' => 12],
            ['с 24 апреля 2009 г.' => 12.5],
            ['с 1 декабря 2008 г.' => 13],
            ['с 12 ноября 2008 г.' => 12],
            ['с 14 июля 2008 г.' => 11],
            ['с 10 июня 2008 г.' => 10.75],
            ['с 29 апреля 2008 г.' => 10.5],
            ['с 4 февраля 2008 г.' => 10.25],
            ['с 19 июня 2007 г.' => 10],
            ['с 29 января 2007 г.' => 10.5],
            ['с 23 октября 2006 г.' => 11],
            ['с 26 июня 2006 г.' => 11.5],
            ['с 26 декабря 2005 г.' => 12],
            ['с 15 июня 2004 г.' => 13],
            ['с 15 января 2004 г.' => 14],
            ['с 21 июня 2003 г.' => 16],
            ['с 17 февраля 2003 г.' => 18],
            ['с 7 августа 2002 г.' => 21],
            ['с 9 апреля 2002 г.' => 23],
            ['с 4 ноября 2000 г.' => 25],
            ['с 10 июля 2000 г.' => 28],
            ['с 21 марта 2000 г.' => 33],
            ['с 7 марта 2000 г.' => 38],
            ['с 24 января 2000 г.' => 45],
            ['с 10 июня 1999 г.' => 55],
            ['с 24 июля 1998 г.' => 60],
            ['с 29 июня 1998 г.' => 80],
            ['с 5 июня 1998 г.' => 60],
            ['с 27 мая 1998 г.' => 150],
            ['с 19 мая 1998 г.' => 50],
            ['с 16 марта 1998 г.' => 30],
            ['со 2 марта 1998 г.' => 36],
            ['с 17 февраля 1998 г.' => 39],
            ['со 2 февраля 1998 г.' => 42],
            ['с 11 ноября 1997 г.' => 28],
            ['с 6 октября 1997 г.' => 21],
            ['с 16 июня 1997 г.' => 24],
            ['с 28 апреля 1997 г.' => 36],
            ['с 10 февраля 1997 г.' => 42],
            ['со 2 декабря 1996 г.' => 48],
            ['с 21 октября 1996 г.' => 60],
            ['с 19 августа 1996 г.' => 80],
            ['с 24 июля 1996 г.' => 110],
            ['с 10 февраля 1996 г.' => 120],
            ['с 1 декабря 1995 г.' => 160],
            ['с 24 октября 1995 г.' => 170],
            ['с 19 июня 1995 г.' => 180],
            ['с 16 мая 1995 г.' => 195],
            ['с 6 января 1995 г.' => 200],
            ['с 17 ноября 1994 г.' => 180],
            ['с 12 октября 1994 г.' => 170],
            ['с 23 августа 1994 г.' => 130],
            ['с 1 августа 1994 г.' => 150],
            ['с 30 июня 1994 г.' => 155],
            ['с 22 июня 1994 г.' => 170],
            ['со 2 июня 1994 г.' => 185],
            ['с 17 мая 1994 г.' => 200],
            ['с 29 апреля 1994 г.' => 205],
            ['с 15 октября 1993 г.' => 210],
            ['с 23 сентября 1993 г.' => 180],
            ['с 15 июля 1993 г.' => 170],
            ['с 29 июня 1993 г.' => 140],
            ['с 22 июня 1993 г.' => 120],
            ['со 2 июня 1993 г.' => 110],
            ['с 30 марта 1993 г.' => 100],
            ['с 23 мая 1992 г.' => 80],
            ['с 10 апреля 1992 г.' => 50],
            ['с 1 января 1992 г.' => 20],
        )
    ];

    my $key = _date_key($date);
    my $record = first {$key ge $_->[0]} @$bank_rate_changes;
    croak "no record for $key" if !$record;

    return $record->[1];
}

sub _get_RU_tax_threshold {
    my ($date, $currency) = @_;
    $currency //= 'RUB';
    return 9  if $currency ne 'RUB';

    my $key = _date_key($date);
    my $bank_rate = _get_RU_bank_rate($key);

    if ($key ge '2014-12-15' && $key le '2015-12-31') {
        return $bank_rate + 10;
    }
    return $bank_rate + 5;
}

sub _get_RU_tax_rate {
    my ($date, $rate, $currency) = @_;

    my $threshold = _get_RU_tax_threshold($date, $currency);
    return 0 if $rate <= $threshold;
    return ($rate-$threshold)/$rate * 0.35;
}
