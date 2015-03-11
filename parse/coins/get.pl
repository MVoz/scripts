#!/usr/bin/perl

use 5.010;
use strict;
use warnings;
use autodie;
use utf8;

use Encode;
use Encode::Locale;
use URI::Escape;
use File::Slurp;
use HTML::TreeBuilder;
use Excel::Writer::XLSX;

use YAML;


binmode STDOUT, ':encoding(console_out)';

my $file = "dump.html";
_download($file)  if !-f $file || -M $file > 0.1;

my $p = HTML::TreeBuilder->new();
my $html = decode cp1251 => scalar read_file $file;
$p->parse($html);

my @items;
for my $item ( $p->find_by_attribute(class => 'R') ) {
    my ($name) = map {$_->as_text()} $item->find_by_attribute(class => 'XL');

    my %record;
    my $href;
    for my $field ( $item->look_down( _tag => 'tr') ) {
        my ($keyn, $valn) = $field->look_down( _tag => 'td' );
        my ($key, $val) = map {$_->as_text()} ($keyn, $valn);
        $key =~ s/[\s:]*$//xms;
        $val =~ s/^[\s:]*//xms;
        $val =~ s/[\s:]*$//xms;
        $record{$key} = $val;

        if ($key =~ m[/]xms) {
            my ($k1, $k2) = split m[\s*/\s*]xms, $key, 2;
            my ($v1, $v2) = split m[\s*/\s*]xms, $val, 2;
            $record{ucfirst $k1} = $v1;
            $record{ucfirst $k2} = $v2;
        }

        if ( !$key ) {
            my $an = $valn->look_down( _tag => 'a' );
            $href = $an->attr('href') if $an;
        }
    }
#    use YAML; say Dump \%record;

    $name =~ s/(?: (?: Золотая | Серебряная | Инвестиционная) \s*)* монета \s*//ixms;
    $name =~ s/\s+$//xms;
    $name =~ s/^\s+//xms;
    $record{name} = $name;
    $record{href} = $href;

#    next if $record{'Металл'} ne 'золото';
#    next if $name =~ 'продажа от';
    next if $record{'Продажа / Покупка'} =~ 'нет в';
    next if !_get_number($record{'Продажа'});

    if (my $weight = _get_number($record{'Чистый металл'})) {
        $record{price} = _get_number($record{'Продажа'}) / $weight;
    }

    push @items, \%record;
}



my $workbook = Excel::Writer::XLSX->new( 'coins.xlsx' );
my $sheet = $workbook->add_worksheet();
$sheet->set_column( 0, 0, 40 );

my @header = qw/Монета Металл Проба Страна Год Вес Покупка Продажа Цена Спред Ссылка/;
$sheet->write(0, $_, $header[$_])  for (0 .. $#header);

my $format_weight = $workbook->add_format(num_format => '0.00');
my $format_price = $workbook->add_format(num_format => '# ##0.00');
my $format_spread = $workbook->add_format(num_format => '0.00%');

my $row = 0;
for my $item ( sort {$a->{price} <=> $b->{price}} @items ) {
    $row ++;
    my $col = 0;

    my %record = %$item;

    my $weight = _get_number($record{'Чистый металл'});
    my $buy = _get_number($record{'Покупка'});
    my $sell = _get_number($record{'Продажа'});

    $sheet->write_string( $row, $col++, $record{name} );

    $sheet->write_string( $row, $col++, $record{'Металл'} // q{} );
    $sheet->write_number( $row, $col++, $record{'Проба'} // 0 );
    $sheet->write_string( $row, $col++, $record{'Страна'} // q{} );
    $sheet->write_string( $row, $col++, $record{'Год выпуска'} // q{} );

    $sheet->write_number( $row, $col++, $weight, $format_weight );
    $sheet->write_number( $row, $col++, $buy );
    $sheet->write_number( $row, $col++, $sell );

    $sheet->write_number( $row, $col++, $weight ? ($sell/$weight) : 0, $format_price );
    $sheet->write_number( $row, $col++, $buy && $sell ? ($sell-$buy)/$sell : 0, $format_spread );

    $sheet->write( $row, $col++, "http://www.artc-derzhava.ru" . $record{href} );
}


exit;

sub _get_number {
    my ($str) = @_;
    return if !$str;
    my ($num) = $str =~ / (?: ^ | (?<= \D) ) ([\d\.\s]+) (?= $ | \D) /xms;
    return if !$num;
    $num =~ s/\s//gxms;
    return $num;
}

sub _download {
    my ($file) = @_;

#    curl 'http://www.artc-derzhava.ru/catalogsearch/' -H 'Cookie: PHPSESSID=99e0b7fc8d5539482869fe9f78550da1; __utma=131208031.588198959.1406271664.1409060116.1409202266.6; __utmb=131208031.2.10.1409202266; __utmc=131208031; __utmz=131208031.1406271664.1.1.utmcsr=yandex|utmccn=(organic)|utmcmd=organic; _ym_visorc_4913941=w' -H 'Origin: http://www.artc-derzhava.ru' -H 'Accept-Encoding: gzip,deflate,sdch' -H 'Accept-Language: ru,en-US;q=0.8,en;q=0.6' -H 'User-Agent: Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/36.0.1985.125 Chrome/36.0.1985.125 Safari/537.36' -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' -H 'Cache-Control: max-age=0' -H 'Referer: http://www.artc-derzhava.ru/catalogsearch/' -H 'Connection: keep-alive' --data 'opened=1&metal=1&metname%5B1%5D=%E7%EE%EB%EE%F2%EE&metname%5B2%5D=+%F1%E5%F0%E5%E1%F0%EE&metname%5B3%5D=+%EF%EB%E0%F2%E8%ED%E0&metname%5B4%5D=+%EF%E0%EB%EB%E0%E4%E8%E9&probe%5B1%5D=0&probe%5B2%5D=0&probe%5B3%5D=0&probe%5B4%5D=0&weight_from=0&weight_to=0&cat_ids%5B%5D=4&cat_ids%5B%5D=94&cat_ids%5B%5D=99&cat_ids%5B%5D=109&cat_ids%5B%5D=107&cat_ids%5B%5D=202&country=0&epoch=0&year1=0&year2=0&copies1=0&copies2=0&qual=0&price1=&price2=&cprice1=&cprice2=&sorttype=1&sm=1' --compressed

    my %data = (
        'cat_ids[]' => 202,
        copies1 => 0,
        copies2 => 0,
        country => 0,
        cprice1 => '',
        cprice2 => '',
        epoch => 0,
        metal => 1,
        'metname[1]' => 'золото',
        'metname[2]' => ' серебро',
        'metname[3]' => ' платина',
        'metname[4]' => ' палладий',
        opened => 1,
        price1 => '',
        price2 => '',
        'probe[1]' => 0,
        'probe[2]' => 0,
        'probe[3]' => 0,
        'probe[4]' => 0,
        qual => 0,
        sm => 1,
        sorttype => 1,
        weight_from => 0,
        weight_to => 0,
        year1 => 0,
        year2 => 0,
    );

    my $data = join q{&},
        map { join q{=}, map { uri_escape encode cp1251 => $_ } ($_, $data{$_}) } 
        sort keys %data;

    my $html = `curl "http://www.artc-derzhava.ru/catalogsearch/" --data "$data" --compressed`;
    
    write_file $file, $html;
    return;
}

