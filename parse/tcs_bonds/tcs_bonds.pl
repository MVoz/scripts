#!/usr/bin/perl

use 5.018;

# https://api.tinkoff.ru/trading/bonds/list?pageSize=12&currentPage=200&start=0&end=2400&sortType=ByYieldToClient&orderType=Desc&country=All&sessionId=d5bdIDlm2wjXLDUDJzfP8tjZz4fplFDD.m1-api09

use uni::perl;
use FindBin '$Bin'; 
use lib "$Bin/../../lib";

use Getopt::Long;

use CachedGet;
use HTML::TreeBuilder;

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

    my $info = _query_bond_info($bond->{symbol}->{ticker});

    my $fin;
    if (my $unk_coupon = first {!$_->[1]} @{$info->{coupons}}) {
        my $limit_date = $unk_coupon->[0];
        $fin = first {$_->[0] lt $limit_date} reverse @{$info->{offers}};
    }
    else {
        $fin = [ $info->{maturity}->[-1]->[0], 0 ];
    }

    my $fin_date = $fin->[0];
    my $today = _datestr(Date::Calc::Today());
    my $mat_left = sum map {$_->[1]} grep {$_->[0] gt $today} @{$info->{maturity}};
    return {}  if $mat_left == 0;

    my $nominal = $bond->{faceValue} / $mat_left * 100;

    my %cashflow = ($today => $bond->{price}->{value} * (1 + $comission));

    my @coupons = grep {$_->[0] gt $today} @{$info->{coupons}};
    my @taxed_coupons =
        map {[
            $coupons[$_]->[0],
            $_
                ? $coupons[$_]->[1] * (1 - $tax)
                : ($bond->{nkd} + ($coupons[$_]->[1] * $nominal / 100 - $bond->{nkd}) * (1 - $tax)) / $nominal * 100
        ]}
        (0 .. $#coupons);

    my $taxed_part = $bond->{faceValue} > $bond->{price}->{value} - $bond->{nkd}
        ? 1 - ($bond->{price}->{value} - $bond->{nkd}) / $bond->{faceValue}
        : 0;
    my $taxed_ratio = 1 - $taxed_part * $tax;

    my @payment_types = (
        [\@taxed_coupons, 1],
        [$info->{maturity}, $taxed_ratio],
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


sub _query_bond_info {
    my ($isin) = @_;

    my $search_html = cached_get "http://bonds.finam.ru/issue/search/default.asp?emitterCustomName=$isin";
    my ($finam_id) = $search_html =~ m#onclick="window.location.href = '/issue/details(\w+)/default.asp'"#;
    die "Internal id not found"  if !$finam_id;

    my @coupons;
    my @maturity;
    my @offers;
    my $p = HTML::TreeBuilder->new();

    my $coupons_html = cached_get "http://bonds.finam.ru/issue/details${finam_id}00002/default.asp";

    my ($nominal) = $coupons_html =~ m#<td>Номинал:\&nbsp;<span>([\d\s]+)</span>#;
    $nominal =~ s/\s//g;

    $p->parse($coupons_html);
    for my $line_node ($p->look_down(_tag => 'tr', class => qr/^bline\b/)) {
        my (undef, $date_str, undef, undef, $coupon_str, undef, $maturity_str) = map {$_->as_text} $line_node->look_down(_tag => 'td');
        my $date = _parse_date($date_str);

        push @coupons, [$date => _parse_value($coupon_str) / $nominal * 100];
        push @maturity, [$date => _parse_value($maturity_str) / $nominal * 100]  if _parse_value($maturity_str);
    }

    my $offers_html = cached_get "http://bonds.finam.ru/issue/details${finam_id}00003/default.asp";
    $p->parse($offers_html);
    for my $line_node ($p->look_down(_tag => 'tr', class => "noborder")) {
        my (undef, $date_str, undef, $rate_str) = map {$_->as_text} $line_node->look_down(_tag => 'td');
        push @offers, [_parse_date($date_str) => _parse_value($rate_str)];
    }

    return {
        id => $finam_id,
        nominal => $nominal,
        coupons => \@coupons,
        maturity => \@maturity,
        offers => \@offers,
    };
}

sub _parse_value {
    my $str = shift;
    my ($value) = $str =~ /(\d+(?:,\d*)?)/;
    $value =~ tr/,/./  if $value;
    return $value;
}


sub _parse_date {
    my $str = shift;
    return $str =~ s/(\d+)\.(\d+)\.(\d+).*/$3-$2-$1/r;
}
