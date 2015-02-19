#!/usr/bin/env perl

use uni::perl;
use Date::Calc qw(:all);
use Math::Round qw/nearest/;
use Getopt::Long;

use Log::Any '$log';
use Log::Any::Adapter;



our %PERC_SUB = (
    at_the_end => sub {0},
    first_day_of_month => sub { shift->[2] == 1 },
); 
$PERC_SUB{monthly} = $PERC_SUB{first_day_of_month};



my %opt;
GetOptions(
    'trace' => sub { Log::Any::Adapter->set('Stderr') },
    'start=s' => \$opt{start},
    'rate=f' => \$opt{rate},
    'days=i' => \$opt{days},
    'sum=f' => \$opt{sum},
    'mode=s' => \$opt{perc_mode},
    'replenishment|repl=s%' => ($opt{replenishments} //= {}),
);

say dep_calc(%opt);
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
    my $num_days = $opt{days} || Delta_Days(@{_date_from_key($opt{finish} || croak 'no finish')}, @$start);
    
    my $sum = $opt{sum} || 0;
    my $sum_perc = 0;

    my $perc_mode = $opt{perc_mode} || 'at_the_end';
    my $perc_sub = $PERC_SUB{$perc_mode}  or croak "wrong perc_mode: $perc_mode";

    $log->trace("$num_days days, $rate%, $perc_mode");

    my $repl = $opt{replenishments} || {};
    
    for my $step_day ( 0 .. $num_days ) {
        my $date = [Add_Delta_Days(@$start, $step_day)];

        $sum_perc += nearest 0.01, $sum * ($rate/100 / (365+!!leap_year($date->[0])))  if $step_day > 0;
        $sum += $repl->{_date_key($date)} || 0;

        if ($perc_sub->($date)) {
            $sum += $sum_perc;
            $sum_perc = 0;
        }

        $log->trace(sprintf "%s: %.2f, %.2f", _date_key($date), $sum, $sum_perc)  if $log->is_trace;
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

    my @date = $key =~ /(\d+)-(\d+)-(\d+)/xms  or croak "unreadable date: $key";
    croak "invalid date: $key"  if !check_date(@date);
        
    return \@date;   
}