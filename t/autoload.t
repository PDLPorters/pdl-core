# -*-perl-*-

# Test PDLA::AutoLoader

use strict;
use warnings;
use Test::More;
use PDLA::LiteF;


BEGIN {
   plan skip_all => 'This test must be run from t/..' if ! -f 't/func.pdl';
   use_ok('PDLA::AutoLoader');
}

$PDLA::debug = 1;

our @PDLALIB = ("t/"); # this means you have to run the test from ../t

my $x = long(2 + ones(2,2));

my $y = func($x);

ok( (sum($y) == 4*29), 'Check autoload of func.pdl' );

#check that tilde expansion works (not applicable on MS Windows)
SKIP: {
   skip "Inapplicable to MS Windows", 1 if $^O =~ /MSWin/i;
   my $tilde = (PDLA::AutoLoader::expand_path('~'))[0];
   my $get = $ENV{'HOME'} || (getpwnam( getlogin || getpwuid($<) ))[7];
   my $echo = qx(echo ~);
   chomp $echo;

   if ($echo !~ /^~/) {
      is($tilde, $echo, "Check tilde expansion (Got '$get' from (getpwnam(getpwuid(\$<)))[7] )");
   } else {
      is($tilde, $get, "Check tilde expansion (Got '$echo' from echo ~");
   }
}

done_testing;
