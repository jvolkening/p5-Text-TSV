package Text::TSV 0.001;

use strict;
use warnings;
use 5.016;
use autodie;
use utf8;
use open qw(:std :utf8);

use IO::Uncompress::AnyUncompress;
use IPC::Cmd qw/can_run/;
use List::Util qw/any/;

use constant XZ_MAGIC => "\xFD7zXZ\x00";
use constant GZIP_MAGIC => "\x1F\x8B";
use constant BZIP2_MAGIC => "\x42\x5A\x68";
use constant ZSTD_MAGIC => "\x28\xB5\x2F\xFD";

sub new {

    my ($class, $fn_in, %args) = @_;

    my $self = bless {fn => $fn_in}, $class;

    $self->_set_handle();
    $self->{has_headers} = $args{has_header} // 1;
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
    my $line = <$fh> // return;
    while (_is_comment_line($line)) {
        $line = <$fh> // return;
    }
    chomp $line;
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

sub _is_comment_line {

    my ($line) = @_;
    return $line =~ /^\s*#/;

}

sub _parse_headers {

    my ($self) = @_;

    my $fh = $self->{fh};

    my $h = <$fh>
        // die "Error: missing header line when told to expect\n";
    chomp $h;
    while ($self->{strip_comments} && _is_comment_line($h)) {
        $h = <$fh> // die "Reached EOF before finding header";
        chomp $h;
    }
    my @headers = split "\t", $h, -1;
    die "Error: empty headers found\n"
        if (any {$_ !~ /\S/} @headers);
    die "Strict mode failure: no delimiters found in header\n"
        if ($self->{strict} && scalar @headers < 2);

    $self->{headers} = \@headers;
    $self->{width} = scalar @headers;

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
    if ( _has_bytes($self->{fn}, XZ_MAGIC) ) {
        my $XZCAT = can_run('xzcat')
            // die "Error: require 'xzcat' for XZ-compressed input\n";
        open $fh_in, '-|', $XZCAT, $self->{fn};
    }
    elsif ( _has_bytes($self->{fn}, GZIP_MAGIC) ) {
        my $ZCAT = can_run('zcat')
            // die "Error: require 'zcat' for GZ-compressed input\n";
        open $fh_in, '-|', $ZCAT, $self->{fn};
    }
    elsif ( _has_bytes($self->{fn}, BZIP2_MAGIC) ) {
        my $BZCAT = can_run('bzcat')
            // die "Error: require 'zstdcat' for BZIP2-compressed input\n";
        open $fh_in, '-|', $BZCAT, $self->{fn};
    }
    elsif ( _has_bytes($self->{fn}, ZSTD_MAGIC) ) {
        my $ZSTDCAT = can_run('zstdcat')
            // die "Error: require 'zstdcat' for ZSTD-compressed input\n";
        open $fh_in, '-|', $ZSTDCAT, $self->{fn};
    }
    elsif ( _looks_binary($self->{fn}) ) {
        die "Error: input appears binary but is not a compatible compressed format\n";
    }
    else {
        open $fh_in, '<', $self->{fn};
    }
    $self->{fh} = $fh_in;

}

sub _looks_binary {

    my ($fn) = @_;

    open my $in, '<:raw', $fn;
    read( $in, my $buf, 6 );
    close $in;
    return $buf =~ /[^\P{C}\s]/;

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

=head1 NAME

BioX::Tax::Kraken - simple access to Kraken-style taxDB taxonomy database

=head1 SYNOPSIS

    use BioX::Tax::Kraken;

    use constant CHICKEN => 9031;
    use constant HUMAN => 9606;
    use constant VERTEBRATA => 7742;
    use constant WHITE_OAK => 3513;
    use constant HSV1 => 10298;

    my $tax = BioX::Tax::Kraken->new($ARGV[0]);

    say $tax->name(CHICKEN);
    # 'Gallus gallus'
    say $tax->rank(CHICKEN);
    # 'species'
    say $tax->name(
        $tax->parent(CHICKEN)
    );
    # 'Gallus'

    say $tax->is_ancestor(CHICKEN, VERTEBRATA) ? 'Y' : 'N';
    # 'Y'
    say $tax->is_ancestor(CHICKEN, WHITE_OAK) ? 'Y' : 'N';
    # 'N'
    say $tax->a_isa_b(CHICKEN, WHITE_OAK) ? 'Y' : 'N';
    # 'N'
    say $tax->name(
        $tax->lca(CHICKEN, HUMAN)
    );
    # 'Amniota'
    say $tax->name(
        $tax->lca(CHICKEN, WHITE_OAK)
    );
    # 'Eukaryota'
    say join ' > ',
        map {$tax->name($_)}
        $tax->lineage(HSV1);
    # 'root > Viruses > Duplodnaviria > Heunggongvirae > Peploviricota >
    # Herviviricetes > Herpesvirales > Orthoherpesviridae > Alphaherpesvirinae >
    # Simplexvirus > Simplexvirus humanalpha1'
    say join ' > ',
        map {$tax->rank($_)}
        $tax->lineage(HSV1);
    # 'no rank > domain > clade > kingdom > phylum > class > order > family >
    # subfamily > genus > species'

=head1 DESCRIPTION

NOTE:: This distribution is currently in testing phase. The API may change
without notice. You have been warned.

C<BioX::Tax::Kraken> is a simple interface to a Kraken-style flatfile
taxonomic database, typically using the filename 'taxDB'. This file format is
a four-column tab-delimited text file, where the columns contain:

=over 4

=item B<taxonomic ID>

=item B<parent ID>

=item B<name> (typically scientific)

=item B<rank>

=back

This distribution has a single class with methods to look up and compare
entries in a Kraken-style taxonomic database based on one or more taxonomic
IDs. It is designed to be simple and correct, and it is written to balance
speed and memory consumption. It is neither blazing fast nor ultra memory
efficient; there are better options for taxonomic data storage formats and
interfaces if you have one of these requirements. This software's only purpose
is to facilitate easy access to the information stored in a Kraken-style
database if you are already using that format for other reasons.

NOTE: The author typically utilizes the NCBI taxonomic database, where
taxonomic IDs are positive integers. Because this is Perl, all of the class
methods can be given either integers or strings as inputs; all inputs will be
treated as strings internally for purposes of comparison.

=head1 A NOTE ON ERROR HANDLING

The methods in this module are intentionally designed to be forgiving by
default. All methods take one or more taxonomic IDs as arguments; if an ID is
not found in the database, undefined is returned but no errors are thrown.
Because most taxonomic databases are constantly changing, this design choice
allows for the possibility of graceful failure if an ID has been removed from
the database without wrapping every method call in a try/catch block.

If you wish to treat these cases as errors, you must check for the definedness
of return values and throw your own errors accordingly. 

=head1 METHODS

=over 4

=item B<new> I<filename>

    my $tax = BioX::Tax::Kraken->new('/path/to/taxDB');

Create a new C<BioX::Tax::Kraken> object and load the database from file. The
input filename is required, and uncompressed or xz-compressed inputs are
supported (xz has significantly better compression ratios than gzip, bzip2, or
zstd on taxDB files).

Returns a new C<BioX::Tax::Kraken> object.

=item B<name> I<tax ID>

=item B<rank> I<tax ID>

=item B<parent> I<tax ID>

    say $tax->name(9031); # 'Gallus gallus'
    say $tax->rank(9031); # 'species'
    say $tax->parent(9031); # '9030'

Given a valid taxonomic ID, fetch the associated property from the database.

Returns a scalar string, or undefined if no entry was found for the input ID.

=item B<is_ancestor> I<child ID> I<parent ID>

    say "That explains a lot!"
        if $tax->is_ancestor(9606, 9443);

Given two valid taxonomic IDs, queries to database to check if the second ID
is an ancestor (not necessarily direct) of the first.

Returns a boolean value, or undefined if either ID was not found in the
database.

=item B<a_isa_b> I<child ID> I<parent ID>

Alias of C<is_ancestor> whose name makes it a little easier to remember the
order of arguments

=item B<lineage> I<tax ID>

    for my $id ( $tax->lineage(9031) ) {
        say sprintf "%s: %s",
            $tax->rank($id),
            $tax->name($id);
    }

Given a valid taxonomic ID, calculates the taxonomic lineage from the tree
root to the given node, inclusive.

Returns a list of IDs, or undefined if the given ID was not found in the
database.

=item B<lca> I<tax ID 1> I<tax ID 2> ...

    my $oldun = $tax->lca(9031, 9606);

Given two or more tax IDs, calculates the last common ancestor (LCA, aka MRCA)
in common to all given nodes.

Returns a taxonomic ID, or undefined if one or more given IDs were not found
in the database.

=item B<children> I<tax ID>

    my @descendents = $tax->children(9031);

Given a valid tax ID, traverses the taxonomic tree to collect all intermediate
and leaf nodes that descend from that ID. BEWARE: The class does not currently
store any back-references when parsing the input database. Thus, unlike all
other instance methods, this method currently must traverse the *entire*
database each time it is called, and it therefore will be a significant
bottleneck if called over thousands or millions of inputs.

Returns an unsorted list of IDs, or undefined if the given ID was not
found in the database.

=back

=head1 CAVEATS AND BUGS

Please reports bugs or feature requests through the issue tracker at
L<https://github.com/jvolkening/p5-BioX-Tax-Kraken/issues>.

=head1 AUTHOR

Jeremy Volkening <jeremy.volkening *at* base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2026 Jeremy Volkening

This software is licensed under the same terms as Perl 5 itself. See LICENSE
file for full details.

=cut

