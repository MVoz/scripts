#!/usr/bin/perl

use 5.018;

# https://api.tinkoff.ru/trading/bonds/list?pageSize=12&currentPage=200&start=0&end=2400&sortType=ByYieldToClient&orderType=Desc&country=All&sessionId=d5bdIDlm2wjXLDUDJzfP8tjZz4fplFDD.m1-api09

use uni::perl;
use FindBin '$Bin'; 
use lib "$Bin/../../lib";

use Getopt::Long;

use FinamBonds;

use JSON;
use YAML;
use List::Util qw/sum first maxstr/;

use LWP::Simple;

use Date::Calc;
use Finance::Math::IRR;

use Encode::Locale;

use Log::Any::Adapter 'Stderr';

binmode STDOUT, ':encoding(console_out)';

GetOptions(
    'cf|cashflow!' => \my $dump_cashflow,
);

$CachedGet::DEFAULT_TIMEOUT = 7; # 1 week

my $json = get 'https://api.tinkoff.ru/trading/bonds/list?sortType=ByYieldToClient&orderType=Desc';

my $data = decode_json $json;
#say Dump $data;

my $bonds_full = $data->{payload}->{values};
my @bonds;
for my $bond (@$bonds_full) {
    my $cashflow = _get_bond_cashflow($bond);

    my $date = maxstr keys %$cashflow;
    my $mat_date = $bond->{matDate} =~ s/T.*//r;

    my $item = {
        ticker      => $bond->{symbol}->{ticker},
        name        => join(' ' =>
                            $bond->{symbol}->{description},
                            # $bond->{symbol}->{showName},
                            $date eq $mat_date ? () : "($mat_date)",
                        ),
        currency    => $bond->{price}->{currency},
        price       => $bond->{price}->{value},
        date        => $date,
        irr         => %$cashflow ? xirr(%$cashflow, precision => 0.0001) : 0,
        cashflow    => $cashflow,
    };

    push @bonds, $item;
}

my $sort_key = 'irr';

for my $bond (sort {$b->{$sort_key} <=> $a->{$sort_key}} @bonds) {
    say _format($bond);
    say Dump $bond->{cashflow}  if $dump_cashflow;
}


sub _format {
    my $bond = shift;

    return sprintf "%20s  %-40s  %7.2f  %s  %s  %5.2f" =>
        $bond->{ticker},
        $bond->{name},
        $bond->{price},
        $bond->{currency},
        $bond->{date} =~ s/T.*//r,
        $bond->{irr} * 100,
        ;
}


sub _get_bond_cashflow {
    my ($bond, %opt) = @_;

    my $tax = $bond->{symbol}->{brand} eq 'ОФЗ' ? 0 : 0.13;
    my $comission = 0.003;

    my $info = FinamBonds::get_bond_info($bond->{symbol}->{ticker});

    my $fin;
    if (my $unk_coupon = first {!$_->[1]} @{$info->{coupons}}) {
        my $limit_date = $unk_coupon->[0];
        $fin = first {$_->[0] lt $limit_date} reverse @{$info->{offers}};
    }
    else {
        $fin = [ $info->{redemption}->[-1]->[0], 0 ];
    }

    my $fin_date = $fin->[0];
    my $today = _datestr(Date::Calc::Today());
    my $mat_left = sum map {$_->[1]} grep {$_->[0] gt $today} @{$info->{redemption}};
    return {}  if $mat_left == 0;

    my $nominal = $bond->{faceValue} / $mat_left * 100;

    my %cashflow = ($today => $bond->{price}->{value} * (1 + $comission));

    my $accrued = $bond->{nkd};
    my $clear_value = $bond->{price}->{value} - $accrued;

    my @coupons = grep {$_->[0] ge $today} @{$info->{coupons}};

    # check if nearest coupon payment already run
    my $soon = _datestr(Date::Calc::Add_Delta_Days(Date::Calc::Today(), 14));
    if (@coupons && $coupons[0]->[0] le $soon && $accrued < $coupons[0]->[1] * 0.9) {
        # warn "$bond->{symbol}->{ticker}: skip coupon at $coupons[0]->[0]";
        shift @coupons;
    }


    my @taxed_coupons =
        map {[
            $coupons[$_]->[0],
            $_
                ? $coupons[$_]->[1] * (1 - $tax)
                : ($accrued + ($coupons[$_]->[1] * $nominal / 100 - $accrued) * (1 - $tax)) / $nominal * 100
        ]}
        (0 .. $#coupons);

    my $taxed_part = $bond->{faceValue} > $clear_value
        ? 1 - $clear_value / $bond->{faceValue}
        : 0;
    my $taxed_ratio = 1 - $taxed_part * $tax;

    my @payment_types = (
        [\@taxed_coupons, 1],
        [$info->{redemption}, $taxed_ratio],
        [[$fin], $taxed_ratio],
    );

    for my $type (@payment_types) {
        my ($payments, $ratio) = @$type;
        for my $payment (@$payments) {
            my $date = $payment->[0];
            next if $date le $today || $date gt $fin_date;
            $cashflow{$date} -= $payment->[1] * $nominal / 100 * $ratio;
        }
    }

    #say Dump $info, \%cashflow;
    return \%cashflow;
}

sub _datestr { sprintf "%4d-%02d-%02d" => @_ }


