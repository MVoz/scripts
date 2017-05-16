#!/usr/bin/perl

use 5.018;

# https://api.tinkoff.ru/trading/bonds/list?pageSize=12&currentPage=200&start=0&end=2400&sortType=ByYieldToClient&orderType=Desc&country=All&sessionId=d5bdIDlm2wjXLDUDJzfP8tjZz4fplFDD.m1-api09

use JSON;
use File::Slurp;
use YAML;

use LWP::Simple;

use Encode::Locale;

binmode STDOUT, ':encoding(console_out)';


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
    my $item = {
        ticker => $bond->{symbol}->{ticker},
        name => $bond->{symbol}->{description},
        currency => $bond->{price}->{currency},
        price => $bond->{price}->{value},
    };

    my $yield = {
        date => $bond->{matDate},
        yield => $bond->{yieldToMaturity},
        type => 'maturity',
    };

    push @bonds, +{ %$item, %$yield };
    next if $bond->{matDate} eq $bond->{buyBackDate};

    my $yield = {
        date => $bond->{buyBackDate},
        yield => $bond->{yieldToBuyBack},
        type => 'buyback',
    };

    push @bonds, +{ %$item, %$yield };
}

say _format($_) for sort {$b->{yield} <=> $a->{yield}} @bonds;


sub _format {
    my $bond = shift;

    return sprintf "%20s    %-24s  %7.2f  %s  %s  %5.2f  %s" =>
        $bond->{ticker},
        $bond->{name},
        $bond->{price},
        $bond->{currency},
        $bond->{date} =~ s/T.*//r,
        $bond->{yield},
        $bond->{type},
        ;
}
