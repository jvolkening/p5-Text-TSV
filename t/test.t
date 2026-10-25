#!/usr/bin/perl

use strict;
use warnings;

use Test2::V0;

use FindBin;
use IPC::Cmd qw/can_run/;
use Scalar::Util qw/reftype/;

use Text::TSV;

my $has_xz = can_run('xzcat');
my $has_gz = can_run('zcat');
my $has_bz2 = can_run('bzcat');
my $has_zstd = can_run('zstdcat');
chdir $FindBin::Bin;

my $test_plain      = 'test_data/foo.tsv';
my $test_db_xz      = 'test_data/foo.tsv.xz';

done_testing;
exit;

