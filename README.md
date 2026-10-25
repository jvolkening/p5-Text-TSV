[![Tests](https://github.com/jvolkening/p5-Text-TSV/actions/workflows/tests.yml/badge.svg)](https://github.com/jvolkening/p5-Text-TSV/actions/workflows/tests.yml)
[![Coverage Status](https://coveralls.io/repos/github/jvolkening/p5-Text-TSV/badge.svg?branch=main)](https://coveralls.io/github/jvolkening/p5-Text-TSV?branch=main)
[![CPAN version](https://badge.fury.io/pl/Text-TSV.svg)](https://badge.fury.io/pl/Text-TSV)

**WARNING**: Currently in testing phase. The API may change in future releases without notice. You have been warned!


# NAME

Text::TSV - simple, robust parsing of tab-delimited text

# SYNOPSIS

```perl
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
```

# DESCRIPTION

`Text::TSV` reads tab-delimited text files one record at a time and returns
each record as a hashref or arrayref, depending on whether the first row is
treated as a header. It does no quoting or escaping: fields are separated by
single tab characters. Input is decoded as UTF-8. Compressed input is detected
automatically from magic bytes (not file extension).

By default, this module operates in 'strict' mode and expects rectangular
(every row has the same number of fields), tab-delimited input where the first
non-commented line contains column headers. Lines beginning with a '#' are
ignored as comments. Blank lines are considered malformed. A few of these
assumptions can be tweaked using the constructor options described below.

## Raison d'être

`Text::TSV` exists mainly because the author could never remember the set of
arguments to `Text::CSV::csv` that would give him the expected behavior, and
99% of his usage for `Text::CSV` was in parsing rectangular, tab-delimited
data files. This is therefore an opinionated, terse module intended to ingest
a specific (though widely used) delimited text format with a minimum of
boilerplate code. The features and knobs included are those most often needed by the
author. Some method has been made to optimize for speed without sacrificing
robust behavior, but `Text::TSV` is neither the fastest nor the most flexible
approach to parsing TSV files. The author recommends `Text::CSV` for any
needs that fall outside of the rather narrow delineations of this module.

# CONSTRUCTOR

- **new** *filename* \[*options*\]

    ```perl
    my $tsv = Text::TSV->new(
        $fn,
        strict => 1,
        has_header => 1
    );
    ```

    Opens the file and, if headers are expected, reads and validates the header
    line. Dies on any error. Options:

    - **has\_header** (default: 1)

        If true, the first content line is parsed as column names and records are
        returned as hash references. If false, records are returned as array
        references.

    - **expected\_headers** (default: none)

        Array reference of column names that must be present in the header line
        (extra columns are allowed). Dies with `Missing expected header 'NAME'` if
        one is absent. Supplying this together with an explicitly false `has_header`
        is a configuration error and dies. Column names are case-sensitive.

    - **strict** (default: 1)

        See ["STRICT VS NON-STRICT MODE"](#strict-vs-non-strict-mode).

    - **strip\_comments** (default: 1)

        If true, lines whose first non-space character (space characters only, not
        tabs) is `#` are skipped, including before the header. If false, such lines
        are treated as ordinary data (or header) lines.

# METHODS

- **next\_record**

    ```perl
    while (my $rec = $tsv->next_record) { ... }
    ```

    Returns the next record, or an empty list/undef at end of input. With headers,
    the record is a hash reference mapping header names to field values; without
    headers it is an array reference of fields. In strict mode (default), empty
    fields are allowed, but a mismatch between record field count and header name
    count will throw an error. In non-strict mode, if a row has fewer fields than
    headers, the missing fields are undefined; if it has more, the extra fields
    are ignored in the hash. Trailing empty fields are preserved.

- **headers**

    ```perl
    my @h = $tsv->headers;
    ```

    Returns an array of header names, or undef if no headers were present/parsed.

# INPUT FORMAT AND ASSUMPTIONS

- Lines end in `\n` or `\r\n`; the line ending is removed.
- Fields are separated by a single tab; no quoting is supported.
- Header names must be non-empty (not blank/whitespace) and unique;
duplicates trigger an error rather than silently losing data.
- Text is read as UTF-8. No byte-order-mark (BOM) handling is performed;
a BOM will remain part of the first header name.
- Unrecognized input whose first bytes look binary (control characters)
dies.

# COMPRESSION SUPPORT

For speed, compressed files are read through external decompressors if
possible, falling back to (slow!) core Perl modules if an external
decompresssor is not found. Detection is by magic bytes: XZ (`xzcat`), gzip
(`zcat`), bzip2 (`bzcat`) and zstd (`zstdcat`).

# STRICT VS NON-STRICT MODE

In strict mode (the default):

- every record must have the same number of fields as the header (or as
the first record, when there is no header); otherwise `next_record` dies with
a "column count mismatch" error;
- the header line must contain at least one tab;
- blank lines are not skipped and so fail the width check (unless the
file has a single column and no header).

In non-strict mode, width mismatches are tolerated, completely empty lines are
skipped, and a single-column header is allowed. Lines containing only
whitespace other than a newline are not considered blank.

# ERROR HANDLING

All errors are thrown with `die`; wrap calls in `eval` or a try/catch
module to handle them. Errors include: unreadable file, binary input,
missing decompressor, missing header line, empty or duplicate header names,
missing expected headers, conflicting options, and (strict mode) column count
mismatches.

# CAVEATS AND BUGS

External decompressors must be installed for compressed input. Please report
bugs or feature requests through the issue tracker at
[https://github.com/jvolkening/p5-Text-TSV/issues](https://github.com/jvolkening/p5-Text-TSV/issues).

# SEE ALSO

[Text::CSV](https://metacpan.org/pod/Text%3A%3ACSV)

# AUTHOR

Jeremy Volkening &lt;jeremy.volkening \*at\* base2bio.com>

# COPYRIGHT AND LICENSE

Copyright 2026 Jeremy Volkening

This software is licensed under the same terms as Perl 5 itself. See LICENSE
file for full details.
