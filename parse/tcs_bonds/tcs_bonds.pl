#!/usr/bin/perl

use 5.018;

# https://api.tinkoff.ru/trading/bonds/list?pageSize=12&currentPage=200&start=0&end=2400&sortType=ByYieldToClient&orderType=Desc&country=All&sessionId=d5bdIDlm2wjXLDUDJzfP8tjZz4fplFDD.m1-api09

use uni::perl;
use lib::abs "../../lib";

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


my $json = get 'https://api.tinkoff.ru/trading/bonds/list?sortType=ByYieldToClient&orderType=Desc';

my $data = decode_json $json;
#say Dump $data;

my $bonds_full = $data->{payload}->{values};
my @bonds;
for my $bond (@$bonds_full) {
    my $cashflow = _get_bond_cashflow($bond);

    my $date = maxstr keys %$cashflow;

    my $item = {
        ticker      => $bond->{symbol}->{ticker},
        name        => $bond->{symbol}->{description},
        currency    => $bond->{price}->{currency},
        price       => $bond->{price}->{value},
        date        => $date,
        irr         => xirr(%$cashflow, precision => 0.0001),
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

    return sprintf "%20s    %-32s  %7.2f  %s  %s  %5.2f" =>
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

    my $tax = 0.13;
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

    my %cashflow = ($today => $bond->{price}->{value} * (1 + $comission));

    my @payment_types = (
        [ $info->{coupons}, (1 - $tax) ],
        [ $info->{maturity}, 1 ],
        [ [$fin], 1 ],
    );

    my $mat_left = sum map {$_->[1]} grep {$_->[0] gt $today} @{$info->{maturity}};
    my $nominal = $bond->{faceValue} / $mat_left * 100;

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