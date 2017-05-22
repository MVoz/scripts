#!/usr/bin/perl

use 5.018;

# https://api.tinkoff.ru/trading/bonds/list?pageSize=12&currentPage=200&start=0&end=2400&sortType=ByYieldToClient&orderType=Desc&country=All&sessionId=d5bdIDlm2wjXLDUDJzfP8tjZz4fplFDD.m1-api09

use JSON;
use File::Slurp;
use YAML;
use Getopt::Long;

use LWP::Simple;

use Date::Calc;
use Finance::Math::IRR;

use Encode::Locale;

binmode STDOUT, ':encoding(console_out)';

GetOptions(
    "buyback!" => \my $need_buyback,
);


my $json;
if (@ARGV) {
    my $file = $ARGV[0];
    $json = read_file $file;
}
else {
    $json = get 'https://api.tinkoff.ru/trading/bonds/list?sortType=ByYieldToClient&orderType=Desc';
}

my $data = decode_json $json;

my $bonds_full = $data->{payload}->{values};
my @bonds;
for my $bond (@$bonds_full) {
    # say STDERR Dump($bond); die;

    my $is_buyback = $bond->{buyBackDate} && $bond->{buyBackDate} ne $bond->{matDate};
    my $date = $is_buyback ? $bond->{buyBackDate} : $bond->{matDate};

    my $item = {
        ticker      => $bond->{symbol}->{ticker},
        name        => $bond->{symbol}->{description} . ($is_buyback ? ' /bb' : ''),
        currency    => $bond->{price}->{currency},
        price       => $bond->{price}->{value},
        date        => $date,
        yield       => $is_buyback ? $bond->{yieldToBuyBack} : $bond->{yieldToMaturity},
        irr         => xirr(_get_bond_cashflow($bond, $date), precision => 0.0001),
    };

    push @bonds, $item;
}

my $sort_key = 'irr';
#my $sort_key = 'yield';

say _format($_) for sort {$b->{$sort_key} <=> $a->{$sort_key}} @bonds;


sub _format {
    my $bond = shift;

    return sprintf "%20s    %-32s  %7.2f  %s  %s  %5.2f  %5.2f" =>
        $bond->{ticker},
        $bond->{name},
        $bond->{price},
        $bond->{currency},
        $bond->{date} =~ s/T.*//r,
        $bond->{yield},
        $bond->{irr} * 100,
        ;
}


sub _get_bond_cashflow {
    my ($bond, $date, %opt) = @_;

    my $today = _datestr(Date::Calc::Today());
    my @end_date = split /-/ => ($date =~ s/T.*//r);

    my $tax = 0.13;
    my $comission = 0.003;

    my $nominal = $bond->{faceValue};
    my $coupon = $bond->{couponValue} * (1 - $tax);
    my $period = $bond->{couponPeriodDays};
    
    my @flow = (_datestr(@end_date) => -($nominal + $coupon));

    my @date = Date::Calc::Add_Delta_Days(@end_date, -$period);
    while (_datestr(@date) ge $today) {
        push @flow, (_datestr(@date) => -$coupon);
        @date = Date::Calc::Add_Delta_Days(@date, -$period);
    }

    push @flow, ($today => $bond->{price}->{value} * (1 + $comission));

#    say "$bond->{symbol}->{isin}:  " . to_json \@flow;
#    use YAML; say Dump $bond;
    
    return @flow;
}

sub _datestr { sprintf "%4d-%02d-%02d" => @_ }

