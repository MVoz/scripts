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
use PDF::API2;

use YAML;


my $name_db = 'title.yml';

my $base_url = "http://arch.rgdb.ru/xmlui/handle/123456789";
my $img_url  = "http://arch.rgdb.ru/xmlui/bitstream/handle/123456789";


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
    'pdf!' => \my $save_pdf,
) or die;

$base_dir ||= '.';

die "Invalid --only"  if $only && !Book->is_valid_type($only);


push @targets, @ARGV;
if ($from && $to) {
    push @targets, ($from .. $to);
}
elsif ($from && $num) {
    push @targets, ($from .. $from+$num-1);
}


my ($name_by_key) = eval { YAML::LoadFile("$Bin/$name_db") };

my $keys_by_name;
for my $type (keys %{Book->type_query}) {
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

    my $html = eval { cached_get("$base_url/$code", cache_timeout => 10) };
    if (!$html) {
        say "Failed to get $base_url/$code, skipping";
        return;
    }

    my %parse_opt = (
        get_incomplete => $get_incomplete,
        is_logged => $is_logged,
    );
    my $book = eval { Book->new($html, %parse_opt) };
    if (!$book) {
        my $err = $@;
        if (ref $err eq 'SCALAR') {
            say "$$err, skipping";
            return;
        }
        die $@;
    }

    my $metadata = $book->get_metadata();

    my $title = $metadata->{title};
    my $author = $metadata->{author} || 'Nobody';
    my $year = $metadata->{year} || 'unk';

    my $name = "$author - $title";
    $name =~ s#[\:\*\?\/\"\'\/]#-#g;
    $year =~ s#[\:\*\?\/\"\'\/]#-#g;
    chop $name while length(encode utf8 => $name) > 240;
    $name .= " ($year)";
    say decode console_out => encode console_out => "$code:  $name";

    my $type = $book->{type};
    croak "Undetected type for $code"  if !$type;
    if ($only && $type ne $only) {
        say "It's not a $only; skipping";
        return;
    }

    $name_by_key->{$type}->{$code} = $name;
    $keys_by_name->{$type}->{$name}->{$code} = $name;
    my $need_subdir = keys %{$keys_by_name->{$type}->{$name}} > 1;

    return if $skip_download;

    my $dir = encode locale_fs => "$base_dir/$name" . ($need_subdir ? "/$code" : '');

    my $pdf;
    if ($save_pdf) {
        $pdf = PDF::API2->new();
        $pdf->info(
            Author => $metadata->{author},
            Title => $metadata->{title},
            Keywords => $metadata->{theme},
        );
    }

    for my $filename (@{$book->{pages}}) {
        my $url = "$img_url/$code/$filename";
        my $file = "$dir/" . encode locale_fs => $filename;

        if (!-f $file) {
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

        if ($save_pdf) {
            my $image = $pdf->image_jpeg($file);
            my $page = $pdf->page();
            $page->mediabox($image->width, $image->height);
            my $gfx = $page->gfx();
            $gfx->image($image);
        }
    }

    if ($save_pdf) {
        my $pdf_name = encode locale_fs => "$base_dir/$name" . ($need_subdir ? ".$code" : '') . '.pdf';
        $pdf->saveas($pdf_name);
    }

    return;
}


sub _download {
    my ($url, $path) = @_;

    my $resp;
    for (1 .. 3) {
        $resp = $ua->get($url);
        last if $resp->is_success;
    }
    return $resp->code  if !$resp->is_success;

    my $content = $resp->decoded_content;
    return 999  if utf8::is_utf8($content);
    path($path)->spew_raw($content);

    return;
}




package Book;

use Carp;

sub new {
    my $class = shift;
    my ($html, %O) = @_;
    my $self = bless {}, $class;

    my $p = $self->{p} = HTML::TreeBuilder->new();
    $p->parse($html);

    my @pages = map {$_->attr('href') =~ m#/(\w+\.\w+)\?sequence#} $p->look_down(_tag => 'a', class => 'image-link');
    die \"No sequence found, skipping"  if !@pages;
    $self->{pages} = \@pages;

    if (!$O{get_incomplete}) {
        my $access = $self->{access} = eval { $p->look_down(_tag => 'meta', name => "DC.relation")->attr('content') };
        die \"No access tag found"  if !$access;
        die \"Restricted access item"  if $access eq "В здании РГДБ";
        die \"Limited access item, please provide login/password"  if !$O{is_logged} && $access eq "Защищено авторским правом"
    }

    $self->{type} = $self->detect_type();

    return $self;
}


sub get_metadata {
    my $self = shift;

    return $self->{metadata}  if $self->{metadata};

    my $p = $self->{p};
    my $url = $p->look_down(_tag => 'meta', name => "DC.identifier", scheme => "DCTERMS.URI")->attr('content');
    my ($id) = $url =~ /(\d+)$/;

    state $in_meta = {
        url =>      [name => "DC.identifier", scheme => "DCTERMS.URI"],
        title =>    [name => "citation_title"],
        author =>   [name => "citation_authors"],
    };
    state $in_span = {
        year =>     [class => "pubdate"],
        publisher => [class => "publishers"],
        illustrator => [class => "illustrators"],
        translator => [class => "translators"],
        target =>   [class => "target"],
        theme =>   [class => "theme"],
    };

    $self->{metadata} = {
        type => $self->{type},
        num_pages => scalar @{$self->{pages}},
        (map {$_ => (eval{$p->look_down(_tag => 'meta', @{$in_meta->{$_}})->attr('content')} || undef)} keys %$in_meta),
        (map {$_ => $self->_parse_span_element($in_span->{$_})} keys %$in_span),
    };

    my ($id) = $self->{metadata}->{url} =~ /(\d+)$/;
    if (!$id) {
        use YAML; warn Dump($self->{metadata});
        croak "ID not found"  if !$id;
    }
    $self->{metadata}->{id} = $id;

    Storage::put($self->{metadata});

    return $self->{metadata};
}

sub _parse_span_element {
    my $self = shift;
    my ($cond) = @_;

    my $value = join '; ' => map {$_->as_text()} $self->{p}->look_down(_tag => 'span', @$cond);
    return $value || undef;
}


sub detect_type {
    my $self = shift;

    my $p = $self->{p};
    my $type = $self->type_query();
    for my $type_code (keys %$type) {
        return $type_code  if $p->look_down(@{$type->{$type_code}});
    }

    return;
}


sub type_query {
    state $type = {
        #"<a href="/xmlui/handle/123456789/27090">Диафильмы</a>",
        film => [_tag => 'a', href => '/xmlui/handle/123456789/27090'],
        mag  => [_tag => 'a', href => '/xmlui/handle/123456789/20027'],
        book => [_tag => 'a', href => '/xmlui/handle/123456789/27123'],
        modern => [_tag => 'a', href => '/xmlui/handle/123456789/38408'],
    };

    return $type;
}


sub is_valid_type {
    my $self = shift;
    my ($key) = @_;
    return exists $self->type_query->{$key};
}

1;


package Storage;

use DBI;
use DBD::SQLite;

use Encode;
use YAML;
use Text::Diff;

my $dbh;

sub table { 'books' };

sub _init {
    return if $dbh;

    state $dbname = "books.sqlite";

    $dbh = DBI->connect("dbi:SQLite:dbname=$dbname","","");

#    $dbh->do("create table books (id int, name varchar(100))");

    my $table_name = table();
    my ($table) = $dbh->tables(undef, '%', $table_name);
    return if $table;

    $dbh->do("
        CREATE TABLE $table_name (
            id int PRIMARY KEY,
            type text,
            title text,
            author text,
            year text,
            publisher text,
            illustrator text,
            translator text,
            theme text,
            target text,
            num_pages int
        )
    ");

    return;
}


sub put {
    my ($data) = @_;
    _init();

    state $fields = [qw/
        id
        type
        title
        author
        year
        publisher
        translator
        illustrator
        target
        theme
        num_pages
    /];

    my $table_name = table();

    my $select_sql = "SELECT "
        . join(',' => @$fields)
        . " FROM books WHERE id=?";
    my $old = $dbh->selectrow_hashref($select_sql, {}, $data->{id});
    if ($old) {
        my %new = map {($_ => $data->{$_} && encode utf8 => $data->{$_})} @$fields;
        my $old_str = YAML::Dump($old);
        my $new_str = YAML::Dump(\%new);
        if ($new_str ne $old_str) {
            say 'Data changed:';
            say diff \$old_str, \$new_str, {CONTEXT => 0};
        }
    }

    my $sql = "INSERT OR REPLACE INTO $table_name ("
        . join(',' => @$fields)
        . ") values ("
        . join(',' => map {"?"} @$fields)
        . ")";
    my @binds = map {$data->{$_}} @$fields;
    $dbh->do($sql, {RaiseError=>1}, @binds) or die $dbh->errstr;

    return;
}


1;

