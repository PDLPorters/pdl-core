# This test checks this works: use Inline with => 'PDLA';
# Also that the XS code in PDLA::API works.

use strict;
use warnings;
use Test::More;
use PDLA::LiteF;

my $inline_test_dir;
# First some Inline administrivia.
BEGIN {
   # Test for Inline and set options
   $inline_test_dir = './.inlinewith';
   mkdir $inline_test_dir unless -d $inline_test_dir;

   # See if Inline loads without trouble, or bail out
   eval {
      require Inline;
      Inline->import (Config => DIRECTORY => $inline_test_dir , FORCE_BUILD => 1);
#      Inline->import ('NOCLEAN');
      1;
   } or do {
      plan skip_all => "Skipped: Inline not installed";
   };

   if( $Inline::VERSION < 0.68 ) {
      plan skip_all => "Skipped: Inline too early a version for Inline with=>'foo' form";
   }	   
}
use File::Path;
END {
  if ($^O =~ /MSWin32/i) {
    for (my $i = 0; $i < @DynaLoader::dl_modules; $i++) {
      if ($DynaLoader::dl_modules[$i] =~ /inline_with_t/) {
        DynaLoader::dl_unload_file($DynaLoader::dl_librefs[$i]);
      }
    }
  }
}

SKIP: {
  #use Inline 'INFO'; # use to generate lots of info
  use_ok 'Inline', with => 'PDLA' or skip 'with PDLA failed', 3;
  eval { Inline->bind(C => <<'EOF') };
static pdl* new_pdl(int datatype, PDLA_Indx dims[], int ndims)
{
  pdl *p = PDLA->pdlnew();
  PDLA->setdims (p, dims, ndims);  /* set dims */
  p->datatype = datatype;         /* and data type */
  PDLA->allocdata (p);             /* allocate the data chunk */

  return p;
}

pdl* myfloatseq()
{
  PDLA_Indx dims[] = {5,5,5};
  pdl *p = new_pdl(PDLA_F,dims,3);
  PDLA_Float *dataf = (PDLA_Float *) p->data;
  PDLA_Indx i; /* dimensions might be 64bits */

  for (i=0;i<5*5*5;i++)
    dataf[i] = i; /* the data must be initialized ! */
  return p;
}
EOF
  is $@, '', 'bind no error' or skip 'Inline C failed', 2;

  note "Inline Version: $Inline::VERSION\n";
  ok 1, 'compiled';

  my $pdl = myfloatseq();
  note $pdl->info,"\n";

  is $pdl->dims, 3, 'dims correct';
}

done_testing;
