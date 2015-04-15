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

use Log::Any '$log';
use Log::Any::Adapter 'Stderr';
use HTML::TreeBuilder;

use Excel::Writer::XLSX;


binmode STDOUT, ':encoding(console_out)';

my $base_url = 'http://proba9999.ru/index.php?categoryID=569&sort=Price&direction=DESC&offset=%d';
my $page_size = 12;

my @coins;

for my $page (0 .. 1) {
    my $url = sprintf $base_url, $page * $page_size;
    my $html = cached_get $url, cache_timeout => 1/24;

    my $p = HTML::TreeBuilder->new();
    $p->parse($html);

    for my $coin_node ($p->find_by_attribute(class => 'ajax_block_product bordercolor  product_list-3')) {
        my ($name) = $coin_node->find_by_attribute(class => 'product_img_link')->attr('title');
        $name =~ s/(?: (?: Золотая | Серебряная | Инвестиционная) \s*)* монета \s*//ixms;
        $name =~ s/,.*//xms;
        $name =~ s/\s+$//xms;
        $name =~ s/^\s+//xms;

        my %coin;
        $coin{name} = $name;

        my ($price_node) = $coin_node->find_by_attribute(class => 'price-list-total');

        for my $line_node ($price_node->find('li')) {
            my $line = $line_node->as_text();
            $coin{sell} = _get_number($line)  if $line =~ /Стандартная/i;
            $coin{buy} = _get_number($line)  if $line =~ /выкупа/i;
        }

        next if !$coin{sell};

        push @coins, \%coin;
    }
}



my $workbook = Excel::Writer::XLSX->new( 'proba9999.xlsx' );
my $sheet = $workbook->add_worksheet();
$sheet->set_column( 0, 0, 40 );

my @header = qw/Монета Покупка Продажа Спред/;
$sheet->write(0, $_, $header[$_])  for (0 .. $#header);

my $format_weight = $workbook->add_format(num_format => '0.00');
my $format_price = $workbook->add_format(num_format => '# ##0');
my $format_spread = $workbook->add_format(num_format => '0.00%');

my $row = 0;
for my $coin ( sort {$a->{price} <=> $b->{price}} @coins ) {
    $row ++;
    my $col = 0;

    $sheet->write_string( $row, $col++, $coin->{name} );
    $sheet->write_number( $row, $col++, $coin->{buy} );
    $sheet->write_number( $row, $col++, $coin->{sell} );
    $sheet->write_number( $row, $col++, ($coin->{sell} - $coin->{buy})/$coin->{sell}, $format_spread );

}


exit;




sub _get_number {
    my ($str) = @_;
    return 0 if !$str;
    my ($num) = $str =~ /(\d+)/xms;
    return 0 if !$num;
    $num =~ s/\s//gxms;
    return $num || 0;
}

