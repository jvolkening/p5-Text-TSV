#!/usr/bin/perl

use strict;
use warnings;

use Test2::V0;

use File::Temp qw/tempdir/;
use FindBin;
use IPC::Cmd qw/can_run/;

use Text::TSV;

my $dir = tempdir( CLEANUP => 1 );
my $n = 0;
sub mk {
    my ($content) = @_;
    my $fn = "$dir/f" . $n++ . '.tsv';
    open my $out, '>:raw', $fn or die $!;
    print {$out} $content;
    close $out;
    return $fn;
}
sub all {
    my ($tsv) = @_;
    my @r;
    while (my $r = $tsv->next_record) { push @r, $r }
    return \@r;
}

my $has_xz   = can_run('xzcat');
my $has_gz   = can_run('zcat');
my $has_bz2  = can_run('bzcat');
my $has_zstd = can_run('zstdcat');

subtest 'construction' => sub {
    my $t = Text::TSV->new(mk("a\tb\n1\t2\n"));
    isa_ok($t, ['Text::TSV']);
    like(dies { Text::TSV->new("$dir/nonexistent") }, qr/./, 'missing file dies');
};

subtest 'header mode' => sub {
    my $t = Text::TSV->new(mk("a\tb\n1\t2\n3\t4\n"));
    is(all($t), [{a => 1, b => 2}, {a => 3, b => 4}], 'hash records');
    is($t->next_record, undef, 'undef at EOF');
};

subtest 'no-header mode' => sub {
    my $t = Text::TSV->new(mk("a\tb\n1\t2\n"), has_header => 0);
    is(all($t), [['a', 'b'], [1, 2]], 'array records');
};

subtest 'expected_headers' => sub {
    my $fn = mk("a\tb\tc\n1\t2\t3\n");
    ok(lives { Text::TSV->new($fn, expected_headers => [qw/a c/]) }, 'present');
    like(dies { Text::TSV->new($fn, expected_headers => ['z']) },
        qr/Missing expected header 'z'/, 'absent dies');
    like(dies { Text::TSV->new($fn, expected_headers => ['a'], has_header => 0) },
        qr/expected_headers requires has_header/, 'conflict dies');
    ok(lives { Text::TSV->new($fn, expected_headers => ['a'], has_header => 1) },
        'explicit has_header => 1 ok');
};

subtest 'strict width' => sub {
    my $t = Text::TSV->new(mk("a\tb\n1\t2\n1\t2\t3\n"));
    $t->next_record;
    like(dies { $t->next_record }, qr/column count mismatch/, 'long row');
    $t = Text::TSV->new(mk("a\tb\n1\n"));
    like(dies { $t->next_record }, qr/column count mismatch/, 'short row');
    $t = Text::TSV->new(mk("1\t2\n3\n"), has_header => 0);
    $t->next_record;
    like(dies { $t->next_record }, qr/column count mismatch/, 'headerless');
    like(dies { Text::TSV->new(mk("a\n1\n")) }, qr/no delimiters/,
        'single-column header in strict');
};

subtest 'non-strict width' => sub {
    my $t = Text::TSV->new(mk("a\tb\n1\n1\t2\t3\n"), strict => 0);
    is(all($t), [{a => 1, b => undef}, {a => 1, b => 2}], 'mismatch tolerated');
    $t = Text::TSV->new(mk("1\t2\n3\n"), has_header => 0, strict => 0);
    is(all($t), [[1, 2], [3]], 'headerless mismatch tolerated');
    $t = Text::TSV->new(mk("a\n1\n"), strict => 0);
    is(all($t), [{a => 1}], 'single-column header allowed');
};

subtest 'comments' => sub {
    my $c = "# top\n\n#x\na\tb\n# mid\n1\t2\n  # indented\n";
    my $t = Text::TSV->new(mk("# top\na\tb\n# mid\n1\t2\n  # indented\n"));
    is(all($t), [{a => 1, b => 2}], 'stripped by default');
    $t = Text::TSV->new(mk("a\tb\n#x\t2\n"), strip_comments => 0);
    is(all($t), [{a => '#x', b => 2}], 'kept when disabled');
    $t = Text::TSV->new(mk("a\tb\n\t#x\n"));
    is(all($t), [{a => '', b => '#x'}], 'tab-leading is not a comment');
    $t = Text::TSV->new(mk("\n#c\na\tb\n\n#c\n1\t2\n"), strict => 0);
    is(all($t), [{a => 1, b => 2}], 'blank then comment');
};

subtest 'blank lines' => sub {
    my $fn = "a\tb\n1\t2\n\n3\t4\n";
    my $t = Text::TSV->new(mk($fn));
    $t->next_record;
    like(dies { $t->next_record }, qr/column count mismatch/, 'strict dies');
    $t = Text::TSV->new(mk($fn), strict => 0);
    is(all($t), [{a => 1, b => 2}, {a => 3, b => 4}], 'non-strict skips');
    $t = Text::TSV->new(mk("\n\na\tb\n1\t2\n"), strict => 0);
    is(all($t), [{a => 1, b => 2}], 'leading blanks before header');
    $t = Text::TSV->new(mk("a\tb\n\t\n"), strict => 0);
    is(all($t), [{a => '', b => ''}], 'tab-only row is data');
};

subtest 'header errors' => sub {
    like(dies { Text::TSV->new(mk("a\ta\n1\t2\n")) }, qr/Duplicate headers/, 'duplicate');
    like(dies { Text::TSV->new(mk("")) }, qr/missing header/, 'empty file');
    like(dies { Text::TSV->new(mk("# only\n# comments\n")) }, qr/missing header/,
        'only comments');
    like(dies { Text::TSV->new(mk("a\t\tb\n")) }, qr/empty headers/, 'empty name');
    ok(lives { Text::TSV->new(mk(""), has_header => 0) }, 'empty ok w/o header');
    is(Text::TSV->new(mk(""), has_header => 0)->next_record, undef, 'no records');
};

subtest 'CRLF' => sub {
    my $t = Text::TSV->new(mk("a\tb\r\n1\t2\r\n"), expected_headers => [qw/a b/]);
    is(all($t), [{a => 1, b => 2}], 'CR removed');
    $t = Text::TSV->new(mk("1\t2\r\n3\t4"), has_header => 0);
    is(all($t), [[1, 2], [3, 4]], 'no final newline');
    $t = Text::TSV->new(mk("a\tb\r\n\r\n1\t2\r\n"), strict => 0);
    is(all($t), [{a => 1, b => 2}], 'CRLF blank skipped');
};

subtest 'trailing empty fields' => sub {
    my $t = Text::TSV->new(mk("a\tb\tc\n1\t\t\n\t\t\n"));
    is(all($t), [{a => 1, b => '', c => ''}, {a => '', b => '', c => ''}],
        'preserved');
    $t = Text::TSV->new(mk("1\t\t\n"), has_header => 0);
    is(all($t), [[1, '', '']], 'array form');
};

subtest 'UTF-8' => sub {
    my $t = Text::TSV->new(mk("\xE2\x80\x94\tb\n\xE6\x97\xA5\t2\n"));
    is(all($t), [{"\x{2014}" => "\x{65E5}", b => 2}], 'decoded');
};

subtest 'binary detection' => sub {
    like(dies { Text::TSV->new(mk("a\0b\tc\n1\t2\n")) }, qr/appears binary/,
        'NUL bytes');
    like(dies { Text::TSV->new(mk("\x01\x02\x03\n")) }, qr/appears binary/,
        'control bytes');
};

sub compressed {
    my ($tool, $cmd) = @_;
    my $plain = mk("# c\na\tb\n1\t2\n\xC3\xA9\t4\n");
    system("$cmd < $plain > $plain.cmp") == 0 or return;
    return "$plain.cmp";
}

subtest 'compressed' => sub {
    my @expect = ({a => 1, b => 2}, {a => "\x{e9}", b => 4});
    my %tools = (
        xz   => [$has_xz,   'xz -c'],
        gzip => [$has_gz,   'gzip -c'],
        bzip2 => [$has_bz2, 'bzip2 -c'],
        zstd => [$has_zstd, 'zstd -q -c'],
    );
    for my $name (sort keys %tools) {
        my ($dec, $cmd) = @{ $tools{$name} };
        SKIP: {
            skip "no decompressor for $name", 1 if !$dec;
            my $fn = compressed($name, $cmd);
            skip "cannot compress with $name", 1 if !defined $fn;
            is(all(Text::TSV->new($fn)), \@expect, "$name input");
        }
    }
    SKIP: {
        skip 'xzcat unavailable', 1 if !$has_xz;
        is(all(Text::TSV->new("$FindBin::Bin/test_data/foo.tsv.xz"))->[0]{header1},
            "value1-\x{3b2}", 'xz file');
    }
};

subtest 'Perl fallback used when decompressor not found' => sub {
    my $fn = compressed('gzip', 'gzip -c');
    skip_all 'cannot create gzip test file' if !defined $fn;

    my @expect = ({a => 1, b => 2}, {a => "\x{e9}", b => 4});

    my $mock = mock 'Text::TSV' => (
        override => [ can_run => sub { return undef } ],
    );

    my $t = Text::TSV->new($fn);
    ok($t->{fh}->isa('IO::Uncompress::Base'), 'fallback handle used');
    is(all($t), \@expect, 'records parsed via Perl fallback');
};

subtest 'plain file' => sub {
    my $t = Text::TSV->new("$FindBin::Bin/test_data/foo.tsv");
    my $r = all($t);
    is(scalar @$r, 2, 'two records');
    is($r->[1], {header1 => 'another val', header2 => 'something else'}, 'values');
    is([sort keys %{ $r->[0] }], [qw/header1 header2/], 'headers');
};

done_testing;
