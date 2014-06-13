#!/usr/bin/env perl

=head1 NAME

    deutf.pl

=head1 DESCRIPTION

    Rename files with utf8 names in non-utf8 filesystems (useful for windows).

=cut

use 5.010;
use strict;
use warnings;

use utf8;
use Encode;
use Encode::Locale;
use File::Copy;

for my $file_loc ( glob q{*} ) {
    my $file_utf = decode locale_fs => $file_loc;
    my $file_deutf = decode utf8 => $file_loc;

    next if $file_deutf eq $file_utf;

    my $file_new = encode locale_fs => $file_deutf;
    next if $file_new =~ m{\?}xms;

    say encode console_out => "$file_utf  -->  $file_deutf";
    move $file_loc => $file_new;
}