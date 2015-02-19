#!/usr/bin/perl -w

use uni::perl;
use FindBin '$Bin'; 
use lib "$Bin/../../lib";

use Log::Any::Adapter 'Stderr';

use CachedGet;

use List::Util qw/sum/;
use List::MoreUtils qw/ uniq natatime /;

use YAML;


my $d_re = qr{<a\sid="([\w\-]+)"\shref="[/\w\-]+">([^<]+)</a></strong></td>\s*<td\salign="center">([^<]+)</td>}xms;
my $d_re_res = [qw/ id name value /];
my @sources = (
#    {url => "http://gtmarket.ru/ratings/worldwide-press-freedom-index/info",},
#    {url => "http://gtmarket.ru/ratings/happy-planet-index/info",},
#    {url => "http://gtmarket.ru/research/rule-of-law-index/info",},
#    {url => "http://gtmarket.ru/ratings/the-global-enabling-trade-index/info",},
    {url => "http://gtmarket.ru/ratings/corruption-perceptions-index/info",},
#    {url => "http://gtmarket.ru/ratings/global-age-wath-index/info",},
#    {
#        url => "http://gtmarket.ru/news/state/2009/09/20/2179", # Р�РЅРґРµРєСЃ РєРѕРЅРєСѓСЂРµРЅС‚РѕСЃРїРѕСЃРѕР±РЅРѕСЃС‚Рё IT-РѕС‚СЂР°СЃР»Рё
#        re => qr{<a\sname="([\w\-]+)"\shref="[/\w\-]+">([^<]+)</a></strong></td>\s*<td\salign="center">([^<]+)</td>}xms,
#    },
#    {url => "http://gtmarket.ru/ratings/global-food-security-index/info",},
#    {url => "http://gtmarket.ru/news/2013/11/25/6418",}, # Р РµР№С‚РёРЅРі СЂР°Р·РІРёС‚РёСЏ Р�РЅС‚РµСЂРЅРµС‚Р°
#    {url => "http://gtmarket.ru/news/2014/11/24/6988",}, # Р�РЅРґРµРєСЃ СЂР°Р·РІРёС‚РёСЏ РёРЅС„РѕСЂРјР°С†РёРѕРЅРЅРѕ-РєРѕРјРјСѓРЅРёРєР°С†РёРѕРЅРЅС‹С… С‚РµС…РЅРѕР»РѕРіРёР№
    {url => "http://gtmarket.ru/ratings/human-development-index/human-development-index-info",},
    {url => "http://gtmarket.ru/ratings/satisfaction-with-life-index/info",},
    {url => "http://gtmarket.ru/news/2014/06/25/6834",}, # СЂРµР№С‚РёРЅРі С…РѕСЂРѕС€РёС… СЃС‚СЂР°РЅ 2014
    {url => "http://gtmarket.ru/ratings/knowledge-economy-index/knowledge-economy-index-info",},
    # http://gtmarket.ru/ratings/governance-matters/governance-matters-info
    {url => "http://gtmarket.ru/ratings/global-innovation-index/info",},
    {url => "http://gtmarket.ru/ratings/country-reputation-ranking/info",},
    {url => "http://gtmarket.ru/ratings/the-imd-world-competitiveness-yearbook/info",},
    {url => "http://gtmarket.ru/ratings/global-competitiveness-index/info",},
#    {url => "http://gtmarket.ru/ratings/democracy-index/info",},
#   {url => "http://gtmarket.ru/ratings/international-property-right-index/info",},
    {url => "http://gtmarket.ru/ratings/quality-of-life-index/info",},
#    {url => "http://gtmarket.ru/ratings/scientific-and-technical-activity/info",},
    {url => "http://gtmarket.ru/ratings/education-index/education-index-info",},
    {url => "http://gtmarket.ru/ratings/life-expectancy-index/life-expectancy-index-info",},
    {url => "http://gtmarket.ru/ratings/legatum-prosperity-index/info",},
#    {url => "http://gtmarket.ru/ratings/internet-development/info",},
    {url => "http://gtmarket.ru/news/2013/10/02/6282",}, # РїРѕ СѓСЂРѕРІРЅСЋ СЂР°Р·РІРёС‚РёСЏ С‡РµР»РѕРІРµС‡РµСЃРєРѕРіРѕ РєР°РїРёС‚Р°Р»Р°
    {url => "http://gtmarket.ru/ratings/research-and-development-expenditure/info",},
    {url => "http://gtmarket.ru/news/2014/04/14/6688",}, # РїРѕ СѓСЂРѕРІРЅСЋ СЃРѕС†РёР°Р»СЊРЅРѕРіРѕ СЂР°Р·РІРёС‚РёСЏ 2014
    {
        url => "http://gtmarket.ru/news/state/2010/07/31/2592", # СЂРµР№С‚РёРЅРі СЃР°РјС‹С… СЃС‡Р°СЃС‚Р»РёРІС‹С… СЃС‚СЂР°РЅ
        re => qr{<a\sname="([\w\-]+)"\shref="[/\w\-]+">([^<]+)</a></strong></td>\s*<td\salign="center">([^<]+)</td>}xms,
    },
    {url => "http://gtmarket.ru/ratings/doing-business/info",},
    {url => "http://gtmarket.ru/ratings/sustainable-society-index/info",},
    {url => "http://gtmarket.ru/ratings/environmental-performance-index/info",},
    {url => "http://gtmarket.ru/ratings/index-of-economic-freedom/index-of-economic-freedom-info",},
    {url => "http://gtmarket.ru/ratings/global-index-of-cognitive-skills-and-educational-attainment/info",},
#    {url => "",},
#    {url => "",},
);

my %result;

for my $source (@sources) {
    my $count;
    my $data = cached_get($source->{url});
    my $re = $source->{re} // $d_re;
    my @re_results = $data =~ /$re/gxms;
    croak "not parsed"  if !@re_results;

    my $re_res = $source->{re_res} // $d_re_res;
    my $it = natatime scalar @{$re_res}, @re_results;
    
    my %subresult;
    while (my @line = $it->()) {
        $count++;
        my %line = (place => $count);
        @line{@{$re_res}} = @line;
        $subresult{$line{id}} = \%line;
    }
    
    my $id = $source->{id} // _get_id_from_url($source->{url});
    $result{$id} = \%subresult;
}

my @ids = uniq map {keys %$_} values %result;
my %rating;
for my $id (@ids) {
    my @places = grep {$_} map {$_->{$id}->{place}} grep {$_->{$id}} values %result;
    $rating{$id} = sum(@places)/@places  if @places > @sources/2;
}

my $cnt;
say Dump [map {++$cnt.": $_ => $rating{$_}"} sort {$rating{$a} <=> $rating{$b}} keys %rating];

# say Dump [keys %result];
# say Dump [sort {$a->{place}<=>$b->{place}} values %{$result{"2013-11-25"}}];


exit;



sub _get_id_from_url {
    my ($url) = @_;
    my ($id) = $url =~ m{gtmarket.ru/\w+/(.+)/\w+};
    croak "No id for <$url>"  if !$id;
    $id =~ tr{/}{-};
    return $id;
}
