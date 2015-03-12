#!/usr/bin/env perl

use uni::perl;

use Date::Calc qw(:all);
use Math::Round qw/nearest/;
use Getopt::Long;

use Date::Holidays::RU qw/is_business_day/;
use List::MoreUtils qw/none/;

use Log::Any '$log';
use Log::Any::Adapter;


our $QUANTUM = 0.00001;

our %PERC_SUB = (
    at_the_end => sub {0},
    first_day_of_month => sub { shift->[2] == 1 },
    last_business_day_of_month => \&is_last_business_day_of_month,
); 
$PERC_SUB{monthly} = $PERC_SUB{last_business_day_of_month};


my %opt;
GetOptions(
    'trace' => sub { Log::Any::Adapter->set('Stderr') },
    'start=s' => \$opt{start},
    'finish=s' => \$opt{finish},
    'rate=f' => \$opt{rate},
    'rate-change=s%' => ($opt{rate_change} //= {}),
    'days=i' => \$opt{days},
    'sum=f' => \$opt{sum},
    'mode=s' => \$opt{perc_mode},
    'replenishment|repl=s%' => ($opt{replenishments} //= {}),
    'quantum=f' => \$QUANTUM,
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
    my $num_days = $opt{days} || Delta_Days(@$start, @{_date_from_key($opt{finish} || croak 'no finish')});
    
    my $sum = $opt{sum} || 0;
    my $sum_perc = 0;

    my $perc_mode = $opt{perc_mode} || 'at_the_end';
    my $perc_sub = $PERC_SUB{$perc_mode}  or croak "wrong perc_mode: $perc_mode";

    my $repl = _make_date_hash($opt{replenishments});
    my $rate_change = _make_date_hash($opt{rate_change});

    $log->trace(sprintf "%s: %.2f  ($num_days days, $rate%%, $perc_mode)", _date_key($start), $sum)  if $log->is_trace;

    for my $step_day ( 1 .. $num_days ) {
        my $date = [Add_Delta_Days(@$start, $step_day)];
        my $date_key = _date_key($date);

        $rate = $rate_change->{$date_key}  if exists $rate_change->{$date_key};

        my $d_perc = nearest $QUANTUM, $sum * ($rate/100 / (365+!!leap_year($date->[0])));
        $sum_perc += $d_perc;

        $log->trace(sprintf "%s: %.2f   %%: +%.2f -> %.2f", _date_key($date), $sum, $d_perc, $sum_perc)  if $log->is_trace;

        if ( $repl->{$date_key} ) {
            $sum += $repl->{$date_key};
            $log->trace(sprintf "            +%.2f -> %.2f", $repl->{$date_key}, $sum)  if $log->is_trace;
        }

        if ($perc_sub->($date) || $step_day==$num_days) {
            $sum += $sum_perc;
            $sum_perc = 0;
            $log->trace(sprintf "            %.2f   %%: %.2f", $sum, $sum_perc)  if $log->is_trace;
        }

    }

   return $sum + $sum_perc; 
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
