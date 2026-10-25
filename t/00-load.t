#!perl -T
use 5.012;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Text::TSV' ) || print "Bail out!\n";
}

diag( "Testing Text::TSV $Text::TSV::VERSION, Perl $], $^X" );
