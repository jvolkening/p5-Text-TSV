package Text::TSV 0.001;

use strict;
use warnings;
use 5.016;
use autodie;

use Encode;
use IO::Uncompress::AnyUncompress qw/$AnyUncompressError/;
use IPC::Cmd qw/can_run/;
use List::Util qw/any uniq/;

use constant XZ_MAGIC => "\xFD7zXZ\x00";
use constant GZIP_MAGIC => "\x1F\x8B";
use constant BZIP2_MAGIC => "\x42\x5A\x68";
use constant ZSTD_MAGIC => "\x28\xB5\x2F\xFD";

sub new {

    my ($class, $fn_in, %args) = @_;

    my $self = bless {fn => $fn_in}, $class;

    my @valid_args = qw/
        has_header
        strict
        strip_comments
        expected_headers
    /;

    # validation checks
    for my $k (keys %args) {
        die "Invalid argument passed: $k\n"
            if (! any {$k eq $_} @valid_args);
    }
    die "Error: expected_headers requires has_header => 1\n"
        if defined $args{expected_headers}
            && defined $args{has_header}
            && !$args{has_header};

    $self->_set_handle();
    $self->{has_headers} = defined $args{expected_headers} ? 1
        : defined $args{has_header} ? $args{has_header}
        : 1;
    $self->{strip_comments} = $args{strip_comments} // 1;
    $self->{strict} = $args{strict} // 1;
    $self->_parse_headers()
        if ($self->{has_headers});
    $self->_validate_headers( $args{expected_headers} );

    return $self;

}

sub next_record {
    
    my ($self) = @_;

    my $fh = $self->{fh};
    my $line;
    while (defined($line = <$fh>)) {
        $line = Encode::decode('UTF-8', $line, Encode::FB_CROAK)
            if ($self->{_decode_by_line});
        next if $self->{strip_comments} && $line =~ /^[ ]*#/;
        next if !$self->{strict} && $line =~ /\A\r?\n?\z/;
        last;
    }
    return if (! defined $line);
    chomp $line;
    $line =~ s/\r\z//;
    my @f = split "\t", $line, -1;
    $self->{width} //= scalar @f;
    die "Strict mode failure: column count mismatch\n"
        if ($self->{strict} && scalar @f != $self->{width});
    return \@f
        if (! $self->{has_headers});
    my %hash;
    @hash{ @{ $self->{headers} } } = @f;
    return \%hash;
    
}

sub _parse_headers {

    my ($self) = @_;

    my $fh = $self->{fh};
    my $line;
    while (defined($line = <$fh>)) {
        $line = Encode::decode('UTF-8', $line, Encode::FB_CROAK)
            if ($self->{_decode_by_line});
        next if $self->{strip_comments} && $line =~ /^[ ]*#/;
        next if !$self->{strict} && $line =~ /\A\r?\n?\z/;
        last;
    }
    die "Error: missing header line when told to expect\n"
        if (! defined $line);
    chomp $line;
    $line =~ s/\r\z//;

    my @headers = split "\t", $line, -1;
    die "Error: empty headers found\n"
        if (any {$_ !~ /\S/} @headers);
    die "Strict mode failure: no delimiters found in header\n"
        if ($self->{strict} && scalar @headers < 2);
    die "Duplicate headers found, bailing to avoid data loss\n"
        if (scalar @headers != scalar uniq @headers);

    $self->{headers} = \@headers;
    $self->{width} = scalar @headers;

    return;

}

sub headers {

    my ($self) = @_;
    return @{ $self->{headers} }
        if ($self->{has_headers});
    return;

}

sub _validate_headers {
    
    my ($self, $expected_headers) = @_;

    return if (! defined $expected_headers);
    my @known_headers = @{ $self->{headers} };
    for my $h (@{ $expected_headers }) {
        die "Missing expected header '$h'\n"
            if (! any {$_ eq $h} @known_headers);
    }

    return;

}

sub _set_handle {

    my ($self) = @_;

    my $fh_in;
    my %pp_opts = ( MultiStream => 1 );
    my ($tool, $label);
    if ( _has_bytes($self->{fn}, XZ_MAGIC) ) {
        ($tool, $label) = ('xzcat', 'XZ');
    }
    elsif ( _has_bytes($self->{fn}, GZIP_MAGIC) ) {
        ($tool, $label) = ('zcat', 'GZ');
    }
    elsif ( _has_bytes($self->{fn}, BZIP2_MAGIC) ) {
        ($tool, $label) = ('bzcat', 'BZIP2');
    }
    elsif ( _has_bytes($self->{fn}, ZSTD_MAGIC) ) {
        ($tool, $label) = ('zstdcat', 'ZSTD');
    }

    if (defined $tool) {
        my $tool_path = can_run $tool;
        if ($tool_path) {
            open $fh_in, '-|', $tool_path, $self->{fn};
        }
        else {
            $fh_in = IO::Uncompress::AnyUncompress->new($self->{fn}, %pp_opts)
                // die sprintf(
                    "Error: '%s' not found and IO::Uncompress::AnyUncompress"
                    . " failed for %s-compressed input '%s' (%s)\n",
                    $tool, $label, $self->{fn}, $AnyUncompressError
                );
            $self->{_decode_by_line} = 1;
        }
    }
    elsif ( _looks_binary($self->{fn}) ) {
        die "Error: input appears binary but is not a compatible compressed format\n";
    }
    else {
        open $fh_in, '<', $self->{fn};
    }
    binmode $fh_in, ':encoding(UTF-8)'
        if (! $self->{_decode_by_line});
    $self->{fh} = $fh_in;

}

sub _looks_binary {

    my ($fn) = @_;

    open my $in, '<:raw', $fn;
    read( $in, my $buf, 64 );
    close $in;
    return $buf =~ /[\x00-\x08\x0B\x0E-\x1F]/;

}

sub _has_bytes {

    my ($fn, $magic) = @_;

    my $n = length $magic;
    open my $in, '<:raw', $fn;
    read( $in, my $buf, $n );
    close $in;
    return $buf eq $magic;

}

1;


__END__

=encoding utf-8

=head1 NAME

Text::TSV - simple, robust parsing of tab-delimited text

=head1 SYNOPSIS

    use Text::TSV;

    # file with a header line (the default); records returned as hashref
    my $tsv = Text::TSV->new(
        'data.tsv.xz',
        expected_headers => [qw/id name/],
    );
    while (my $rec = $tsv->next_record) {
        say "$rec->{id}: $rec->{name}";
    }
    my @headers = $tsv->headers;

    # file without a header line; records returned as arrayref
    my $raw = Text::TSV->new(
        'data.tsv',
        has_header => 0
    );
    while (my $row = $raw->next_record) {
        say join ',', @{ $row };
    }

    # lenient parsing
    my $lax = Text::TSV->new(
        'data.tsv',
        strict => 0,
        strip_comments => 0
    );

=head1 DESCRIPTION

C<Text::TSV> reads tab-delimited text files one record at a time and returns
each record as a hashref or arrayref, depending on whether the first row is
treated as a header. It does no quoting or escaping: fields are separated by
single tab characters. Input is decoded as UTF-8. Compressed input is detected
automatically from magic bytes (not file extension).

By default, this module operates in 'strict' mode and expects rectangular
(every row has the same number of fields), tab-delimited input where the first
non-commented line contains column headers. Lines beginning with a '#' are
ignored as comments. Blank lines are considered malformed. A few of these
assumptions can be tweaked using the constructor options described below.

=head2 Raison d'être

C<Text::TSV> exists mainly because the author could never remember the set of
arguments to C<Text::CSV::csv> that would give him the expected behavior, and
99% of his usage for C<Text::CSV> was in parsing rectangular, tab-delimited
data files. This is therefore an opinionated, terse module intended to ingest
a specific (though widely used) delimited text format with a minimum of
boilerplate code. The features and knobs included are those most often needed by the
author. Some method has been made to optimize for speed without sacrificing
robust behavior, but C<Text::TSV> is neither the fastest nor the most flexible
approach to parsing TSV files. The author recommends C<Text::CSV> for any
needs that fall outside of the rather narrow delineations of this module.

=head1 CONSTRUCTOR

=over 4

=item B<new> I<filename> [I<options>]

    my $tsv = Text::TSV->new(
        $fn,
        strict => 1,
        has_header => 1
    );

Opens the file and, if headers are expected, reads and validates the header
line. Dies on any error. Options:

=over 4

=item B<has_header> (default: 1)

If true, the first content line is parsed as column names and records are
returned as hash references. If false, records are returned as array
references.

=item B<expected_headers> (default: none)

Array reference of column names that must be present in the header line
(extra columns are allowed). Dies with C<Missing expected header 'NAME'> if
one is absent. Supplying this together with an explicitly false C<has_header>
is a configuration error and dies. Column names are case-sensitive.

=item B<strict> (default: 1)

See L</STRICT VS NON-STRICT MODE>.

=item B<strip_comments> (default: 1)

If true, lines whose first non-space character (space characters only, not
tabs) is C<#> are skipped, including before the header. If false, such lines
are treated as ordinary data (or header) lines.

=back

=back

=head1 METHODS

=over 4

=item B<next_record>

    while (my $rec = $tsv->next_record) { ... }

Returns the next record, or an empty list/undef at end of input. With headers,
the record is a hash reference mapping header names to field values; without
headers it is an array reference of fields. In strict mode (default), empty
fields are allowed, but a mismatch between record field count and header name
count will throw an error. In non-strict mode, if a row has fewer fields than
headers, the missing fields are undefined; if it has more, the extra fields
are ignored in the hash. Trailing empty fields are preserved.

=item B<headers>

    my @h = $tsv->headers;

Returns an array of header names, or undef if no headers were present/parsed.

=back

=head1 INPUT FORMAT AND ASSUMPTIONS

=over 4

=item * Lines end in C<\n> or C<\r\n>; the line ending is removed.

=item * Fields are separated by a single tab; no quoting is supported.

=item * Header names must be non-empty (not blank/whitespace) and unique;
duplicates trigger an error rather than silently losing data.

=item * Text is read as UTF-8. No byte-order-mark (BOM) handling is performed;
a BOM will remain part of the first header name.

=item * Unrecognized input whose first bytes look binary (control characters)
dies.

=back

=head1 COMPRESSION SUPPORT

For speed, compressed files are read through external decompressors if
possible, falling back to (slow!) core Perl modules if an external
decompresssor is not found. Detection is by magic bytes: XZ (C<xzcat>), gzip
(C<zcat>), bzip2 (C<bzcat>) and zstd (C<zstdcat>).

=head1 STRICT VS NON-STRICT MODE

In strict mode (the default):

=over 4

=item * every record must have the same number of fields as the header (or as
the first record, when there is no header); otherwise C<next_record> dies with
a "column count mismatch" error;

=item * the header line must contain at least one tab;

=item * blank lines are not skipped and so fail the width check (unless the
file has a single column and no header).

=back

In non-strict mode, width mismatches are tolerated, completely empty lines are
skipped, and a single-column header is allowed. Lines containing only
whitespace other than a newline are not considered blank.

=head1 ERROR HANDLING

All errors are thrown with C<die>; wrap calls in C<eval> or a try/catch
module to handle them. Errors include: unreadable file, binary input,
missing decompressor, missing header line, empty or duplicate header names,
missing expected headers, conflicting options, and (strict mode) column count
mismatches.

=head1 CAVEATS AND BUGS

External decompressors must be installed for compressed input. Please report
bugs or feature requests through the issue tracker at
L<https://github.com/jvolkening/p5-Text-TSV/issues>.

=head1 SEE ALSO

L<Text::CSV>

=head1 AUTHOR

Jeremy Volkening <jeremy.volkening *at* base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2026 Jeremy Volkening

This software is licensed under the same terms as Perl 5 itself. See LICENSE
file for full details.

=cut
