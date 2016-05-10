#!/usr/bin/env perl

=head1 DESCRIPTION

Steal

=cut

use uni::perl;

use Carp;
use Encode;
use Encode::Locale;

use HTML::TreeBuilder;
use LWP::UserAgent;
use JSON;

use Excel::Writer::XLSX;

# curl "http://zoloto-md.ru/filter" -H "Cookie: PHPSESSID=1t509fgu25epfvuhgvqna26270; language=ru; currency=RUB; _ym_uid=14626267451040790330; _gat=1; _ym_isad=1; _ga=GA1.2.224986955.1462626745; _ym_visorc_19473382=w; _ym_visorc_32137485=w" -H "Origin: http://zoloto-md.ru" -H "Accept-Encoding: gzip, deflate" -H "Accept-Language: ru,en-US;q=0.8,en;q=0.6" -H "X-Compress: null" -H "User-Agent: Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.94 Safari/537.36" -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" -H "Accept: application/json, text/javascript, */*; q=0.01" -H "Referer: http://zoloto-md.ru/bullion-coins/" -H "X-Requested-With: XMLHttpRequest" -H "Connection: keep-alive" --data "tpl=prise&only_price_list=0&offset=0&available=1&search=&sort=0&category_id=0&metal_id=0&sample_id=0&country_id=0" --compressed

#binmode STDOUT, ':encoding(console_out)';

#my $json = LWP::UserAgent->new()->post(
#    "http://zoloto-md.ru/filter/",
#    "tpl=prise&only_price_list=0&offset=0&available=1&search=&sort=0&category_id=0&metal_id=0&sample_id=0&country_id=0",
#)->decoded_content();

my $json = `curl -s "http://zoloto-md.ru/filter" -H "Cookie: PHPSESSID=1t509fgu25epfvuhgvqna26270; language=ru; currency=RUB; _ym_uid=14626267451040790330; _ym_isad=1; _ga=GA1.2.224986955.1462626745; _gat=1; _ym_visorc_19473382=w; _ym_visorc_32137485=w" -H "Origin: http://zoloto-md.ru" -H "Accept-Encoding: gzip, deflate" -H "Accept-Language: ru,en-US;q=0.8,en;q=0.6" -H "X-Compress: null" -H "User-Agent: Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.94 Safari/537.36" -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" -H "Accept: application/json, text/javascript, */*; q=0.01" -H "Referer: http://zoloto-md.ru/bullion-coins/" -H "X-Requested-With: XMLHttpRequest" -H "Connection: keep-alive" --data "tpl=prise&only_price_list=0&offset=0&available=1&search=&sort=0&category_id=0&metal_id=0&sample_id=0&country_id=0" --compressed`;

my $html = decode_json($json)->{data};



my @coins;

    my $p = HTML::TreeBuilder->new();
    $p->parse($html);

    for my $coin_node ($p->find_by_attribute(class => 'js-product')) {
        my ($img_node) = $coin_node->find_by_tag_name('img');

        next if !$img_node;

        my $name = $img_node->attr('alt');
        $name =~ s/(?: Инвестиционная | монета ) \s+ //igxms;

        my %coin;
        $coin{name} = $name;
        $coin{link} = $coin_node->find_by_tag_name('a')->attr('href');
        $coin{weight} = $coin_node->find_by_attribute(class => "pi-text-center")->as_text();
        $coin{sell} = $coin_node->find_by_attribute(class => "product_price js-price pi-text-center")->as_text() =~ s/[^\d\.]|\.$//gr;
        $coin{buy} = eval { $coin_node->find_by_attribute(class => "product_price js-price-buyout pi-text-center")->as_text() =~ s/[^\d\.]|\.$//gr } || 0;

        next if !$coin{sell};

        push @coins, \%coin;
    }




my $workbook = Excel::Writer::XLSX->new( 'zoloto-md.xlsx' );
my $sheet = $workbook->add_worksheet();
$sheet->set_column( 0, 0, 40 );

my @header = qw/Монета Вес Покупка Продажа Унция Спред Ссылка/;
$sheet->write(0, $_, $header[$_])  for (0 .. $#header);

my $format_weight = $workbook->add_format(num_format => '0.00');
my $format_price = $workbook->add_format(num_format => '# ##0');
my $format_spread = $workbook->add_format(num_format => '0.00%');

my $row = 0;
for my $coin ( sort {$a->{price} <=> $b->{price}} @coins ) {
    $row ++;
    my $col = 0;

    $sheet->write_string( $row, $col++, $coin->{name} );
    $sheet->write_number( $row, $col++, $coin->{weight}, $format_weight );
    $sheet->write_number( $row, $col++, $coin->{buy}, $format_price );
    $sheet->write_number( $row, $col++, $coin->{sell}, $format_price );
    $sheet->write_number( $row, $col++, $coin->{sell}/$coin->{weight}*31.10, $format_price );
    $sheet->write_number( $row, $col++, ($coin->{sell} - $coin->{buy})/$coin->{sell}, $format_spread );
    $sheet->write( $row, $col++, $coin->{link} );
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

