package FinamBonds;

use uni::perl;


use HTML::TreeBuilder;

use CachedGet;


sub get_bond_info {
    my ($isin) = @_;

    my $finam_id = query_finam_id($isin);

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
        isin => $isin,
        finam_id => $finam_id,
        nominal => $nominal,
        coupons => \@coupons,
        redemption => \@maturity,
        offers => \@offers,
    };
}


sub query_finam_id {
    my ($isin) = @_;

    my $search_html = cached_get "http://bonds.finam.ru/issue/search/default.asp?emitterCustomName=$isin";
    my ($finam_id) = $search_html =~ m#onclick="window.location.href = '/issue/details(\w+)/default.asp'"#;
    croak "Internal id not found"  if !$finam_id;

    return $finam_id;
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


1;
