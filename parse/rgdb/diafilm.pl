#!/usr/bin/env perl

=head1 DESCRIPTION

Steal

=cut

use uni::perl;

use FindBin '$Bin';
use lib "$Bin/../../lib";

use Log::Any::Adapter 'Stderr';

use Encode;
use Encode::Locale;
use Getopt::Long;

use CachedGet;
use HTML::TreeBuilder;
use LWP::UserAgent;
use Path::Tiny;
use URI;

use YAML;

my $name_db = 'title.yml';

my $base_url = "http://arch.rgdb.ru/xmlui/handle/123456789";
my $img_url  = "http://arch.rgdb.ru/xmlui/bitstream/handle/123456789";

my %type = (
    #"<a href="/xmlui/handle/123456789/27090">Диафильмы</a>",
    film => [_tag => 'a', href => '/xmlui/handle/123456789/27090'],
    mag  => [_tag => 'a', href => '/xmlui/handle/123456789/20027'],
    book => [_tag => 'a', href => '/xmlui/handle/123456789/27123'],
    modern => [_tag => 'a', href => '/xmlui/handle/123456789/38408'],
);


Encode::Locale::decode_argv();
binmode STDOUT, 'encoding(console_out)';
binmode STDERR, 'encoding(console_out)';

GetOptions(
    'd|base-dir=s' => \my $base_dir,
    'id=s' => \my @targets,
    'f|id-from=s' => \my $from,
    't|id-to=s' => \my $to,
    'n|num=i' => \my $num,
    'only=s' => \my $only,
    'l|login=s' => \my $login,
    'p|pass|password=s' => \my $password,
    'incomplete!' => \my $get_incomplete,
    'names!' => \my $skip_download,
) or die;

$base_dir ||= '.';
die "Invalid --only"  if $only && !$type{$only};


push @targets, @ARGV;
if ($from && $to) {
    push @targets, ($from .. $to);
}
elsif ($from && $num) {
    push @targets, ($from .. $from+$num-1);
}


my ($name_by_key) = eval { YAML::LoadFile("$Bin/$name_db") };

my $keys_by_name;
for my $type (keys %type) {
    $keys_by_name->{$type}->{$name_by_key->{$type}->{$_}}->{$_} = $name_by_key->{$type}->{$_}  for keys %{$name_by_key->{$type} || {}};
}

my $ua = LWP::UserAgent->new(cookie_jar => {});
my $is_logged;
if ($login) {
    die "Need --password"  if !$password;
    my $res = $ua->post(
        'http://arch.rgdb.ru/xmlui/password-login',
        { login_email => $login, login_password => $password, submit => 'Войти' },
    );
    die "Login failed"  if $res->code != 302;
    $is_logged = 1;
}


for my $target (@targets) {
    my ($code) = $target =~ /(\d+)\D*$/;
    die "Invalid target $target" if !$code;

    process_item($code);
}

YAML::DumpFile("$Bin/$name_db", $name_by_key);


sub process_item {
    my ($code) = @_;

    my $p = HTML::TreeBuilder->new();
    my $html = eval { cached_get("$base_url/$code") };
    if (!$html) {
        say "Failed to get $base_url/$code, skipping";
        return;
    }

    $p->parse($html);

    my @files = map {$_->attr('href') =~ m#/(\w+\.\w+)\?sequence#} $p->look_down(_tag => 'a', class => 'image-link');
    if (!@files) {
        say "No sequence found, skipping";
        return;
    }

    if (!$get_incomplete) {
        my $access = eval { $p->look_down(_tag => 'meta', name => "DC.relation")->attr('content') };
        die "No access tag found"  if !$access;

        if ($access eq "В здании РГДБ") {
            say "Restricted access item; skipping";
            return;
        }

        if (!$is_logged && $access eq "Защищено авторским правом") {
            say "Limited access item, please provide login/password; skipping";
            return;
        }
    }


    my $title = $p->find("h2")->as_text();
    my $author = eval { $p->look_down(_tag => 'span', class => "authors")->as_text() } || 'Nobody';
    my $year = eval {$p->look_down(_tag => 'span', class => "pubdate")->as_text() } || 'unk';

    my $name = "$author - $title";
    $name =~ s#[\:\*\?\/\"\'\/]#-#g;
    $year =~ s#[\:\*\?\/\"\'\/]#-#g;
    chop $name while length(encode utf8 => $name) > 240;
    $name .= " ($year)";
    say "$code:  $name";

    my $type = detect_type($p);
    croak "Undetected type for $code"  if !$type;
    if ($only && $type ne $only) {
        say "It's not a $only; skipping";
        return;
    }

    $name_by_key->{$type}->{$code} = $name;
    $keys_by_name->{$type}->{$name}->{$code} = $name;
    my $need_subdir = keys %{$keys_by_name->{$type}->{$name}} > 1;

    return if $skip_download;

=zip
    if (my $zip_node = $p->look_down(_tag => 'a', href => qr/\.zip\?/)) {
        my $href = $zip_node->attr("href");
        $href =~ s/\?.*$//;
        my $file = "$base_dir/$name.zip";
        return if -f $file;

        my $zip_url = URI->new_abs($href, $base_url)->as_string;
        say $zip_url;        
        my $code = _download($zip_url => $file);
        die "HTTP code $code"  if $code;
        return;
    }
=cut

    my $dir = encode locale_fs => "$base_dir/$name" . ($need_subdir ? "/$code" : '');

    for my $filename (@files) {
        my $url = "$img_url/$code/$filename";
        my $file = "$dir/" . encode locale_fs => $filename;

        next if -f $file;
        say $url;

        path($dir)->mkpath()  if !-d $dir;

        my $code = _download($url => $file);

        if ($code == 404 || $code == 999) {
            say "Incomplete book, skipping";
            if (!$get_incomplete) {
                say "(removing incomplete)";
                path($dir)->remove_tree;
            }
            last;
        }   

        die "HTTP code $code"  if $code;
    }

    return;
}


sub _download {
    my ($url, $path) = @_;

    my $resp = $ua->get($url);
    return $resp->code  if !$resp->is_success;

    my $content = $resp->decoded_content;
    return 999  if utf8::is_utf8($content);
    path($path)->spew_raw($content);

    return;
}


sub detect_type {
    my ($p) = @_;

    for my $type_code (keys %type) {
        return $type_code  if $p->look_down(@{$type{$type_code}});
    }

    return;
}



