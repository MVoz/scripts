package CachedGet;

use uni::perl;
use autodie;

use Mouse;
use Exporter "import";

use Encode;
use File::Slurp;
use LWP::UserAgent;
use Digest;
require Digest::CRC;
use Log::Any '$log';

our @EXPORT = qw/ cached_get /;

has cache_dir => ( is => 'ro', default => './_cache' );
has cache_timeout => ( is => 'ro', default => 1 ); # in days
has cache_fullname => ( is => 'ro', isa => 'Bool', default => 0 );
has ua => ( is => 'rw', lazy_build => 1 );


sub _build_ua {
    my ($self) = @_;
    return LWP::UserAgent->new();
}

sub _http_get {
    my ($self, $url) = @_;
    $log->trace("GET $url")  if $log->is_trace;
    my $response = $self->ua->get($url);
    croak "Failed to get $url: " . $response->message  if !$response->is_success;
    my $data = $response->decoded_content();
    return $data;
}

sub _cache_get {
    my ($self, $url) = @_;

    my $file = $self->_cache_filename($url);
    return if !-f $file;
    return if -M $file > $self->cache_timeout;
    
    return decode utf8 => scalar read_file $file;
}

sub _cache_put {
    my ($self, $url, $data) = @_;
    mkdir $self->cache_dir  if !-d $self->cache_dir;
    write_file $self->_cache_filename($url), encode utf8 => $data;
    return;
}

sub _cache_filename {
    my ($self, $url) = @_;
    my $digest = Digest->new("CRC-32")->add($url)->hexdigest();
    $url =~ s# ^ (?: \w+ : //)? [\w\.]+ (?: : \d+)? /? ##xms  if !$self->cache_fullname;
    $url ||= "index.html";
    $url =~ s/(?= (?: \. \w+)? $)/\.$digest/xms;
    $url =~ tr!/: #?*!______!;
    return $self->cache_dir . "/$url";
}

sub get {
    my ($self, $url) = @_;

    my $data = $self->_cache_get($url);
    return $data  if defined $data;

    $data = $self->_http_get($url);
    $self->_cache_put($url => $data);
    return $data;
}



sub cached_get {
    my ($url, %opt) = @_;
    return __PACKAGE__->new(%opt)->get($url);
}


__PACKAGE__->meta->make_immutable();

1;
