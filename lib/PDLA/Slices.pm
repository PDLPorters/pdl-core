package PDLA::Slices;

use strict;
use warnings;
use PDLA::Slices::Inline Pdlapp => Config => clean_after_build => 0;
use PDLA::Slices::Inline Pdlapp => 'DATA', internal => 1;
use PDLA::Core;
use parent 'PDLA::Exporter';

our @EXPORT_OK;
our %EXPORT_TAGS = (Func=> \@EXPORT_OK);

sub import_export {
    my ($func) = @_;
    push @EXPORT_OK, $func;
    no strict 'refs';
    *$func = \&{"PDLA::$func"};
}

import_export($_) for qw(
  dice dice_axis slice using indexND indexNDb
  sliceb unthread identvaff rotate splitdim lags diagonalI affine oslice mv
  xchg converttypei flowconvert rle rld rangeb index2d index1d index
);

=head1 NAME

PDLA::Slices -- Indexing, slicing, and dicing

=head1 SYNOPSIS

  use PDLA;
  $x = ones(3,3);
  $y = $x->slice('-1:0,(1)');
  $c = $x->dummy(2);


=head1 DESCRIPTION

This package provides many of the powerful PerlDL core index
manipulation routines.  These routines mostly allow two-way data flow,
so you can modify your data in the most convenient representation.
For example, you can make a 1000x1000 unit matrix with

 $x = zeroes(1000,1000);
 $x->diagonal(0,1) ++;

which is quite efficient. See L<PDLA::Indexing> and L<PDLA::Tips> for
more examples.

Slicing is so central to the PDLA language that a special compile-time
syntax has been introduced to handle it compactly; see L<PDLA::NiceSlice>
for details.

PDLA indexing and slicing functions usually include two-way data flow,
so that you can separate the actions of reshaping your data structures
and modifying the data themselves.  Two special methods, L<copy|copy> and
L<sever|sever>, help you control the data flow connection between related
variables.

 $y = $x->slice("1:3"); # Slice maintains a link between $x and $y.
 $y += 5;               # $x is changed!

If you want to force a physical copy and no data flow, you can copy or
sever the slice expression:

 $y = $x->slice("1:3")->copy;
 $y += 5;               # $x is not changed.

 $y = $x->slice("1:3")->sever;
 $y += 5;               # $x is not changed.

The difference between C<sever> and C<copy> is that sever acts on (and
returns) its argument, while copy produces a disconnected copy.  If you
say

 $y = $x->slice("1:3");
 $c = $y->sever;

then the variables C<$y> and C<$c> point to the same object but with
C<-E<gt>copy> they would not.

=head1 FUNCTIONS

=cut

use PDLA::Core ':Internal';
use Scalar::Util 'blessed';

=head2 index, index1d, index2d

=for ref

C<index>, C<index1d>, and C<index2d> provide rudimentary index indirection.

=for example

 $c = index($source,$ind);
 $c = index1d($source,$ind);
 $c = index2d($source2,$ind1,$ind2);

use the C<$ind> variables as indices to look up values in C<$source>.
The three routines thread slightly differently.

=over 3

=item * 

C<index> uses direct threading for 1-D indexing across the 0 dim
of C<$source>.  It can thread over source thread dims or index thread
dims, but not (easily) both: If C<$source> has more than 1
dimension and C<$ind> has more than 0 dimensions, they must agree in
a threading sense.

=item * 

C<index1d> uses a single active dim in C<$ind> to produce a list of
indexed values in the 0 dim of the output - it is useful for
collapsing C<$source> by indexing with a single row of values along
C<$source>'s 0 dimension.  The output has the same number of dims as
C<$source>.  The 0 dim of the output has size 1 if C<$ind> is a
scalar, and the same size as the 0 dim of C<$ind> if it is not. If
C<$ind> and C<$source> both have more than 1 dim, then all dims higher
than 0 must agree in a threading sense.

=item * 

C<index2d> works like C<index> but uses separate piddles for X and Y
coordinates.  For more general N-dimensional indexing, see the
L<PDLA::NiceSlice|PDLA::NiceSlice> syntax or L<PDLA::Slices|PDLA::Slices> (in particular C<slice>,
C<indexND>, and C<range>).

=back 

These functions are two-way, i.e. after

 $c = $x->index(pdl[0,5,8]);
 $c .= pdl [0,2,4];

the changes in C<$c> will flow back to C<$x>.

C<index> provids simple threading:  multiple-dimensioned arrays are treated
as collections of 1-D arrays, so that

 $x = xvals(10,10)+10*yvals(10,10);
 $y = $x->index(3);
 $c = $x->index(9-xvals(10));

puts a single column from C<$x> into C<$y>, and puts a single element
from each column of C<$x> into C<$c>.  If you want to extract multiple
columns from an array in one operation, see L<dice|/dice> or
L<indexND|/indexND>.

=for bad

index barfs if any of the index values are bad.

index1d propagates BAD index elements to the output variable.

index2d barfs if either of the index values are bad.

=cut

=head2 indexNDb

=for ref

  Backwards-compatibility alias for indexND

=head2 indexND

=for ref

  Find selected elements in an N-D piddle, with optional boundary handling

=for example

  $out = $source->indexND( $index, [$method] )

  $source = 10*xvals(10,10) + yvals(10,10);
  $index  = pdl([[2,3],[4,5]],[[6,7],[8,9]]);
  print $source->indexND( $index );

  [
   [23 45]
   [67 89]
  ]

IndexND collapses C<$index> by lookup into C<$source>.  The
0th dimension of C<$index> is treated as coordinates in C<$source>, and
the return value has the same dimensions as the rest of C<$index>.
The returned elements are looked up from C<$source>.  Dataflow
works -- propagated assignment flows back into C<$source>.

IndexND and IndexNDb were originally separate routines but they are both
now implemented as a call to L<range|/range>, and have identical syntax to
one another.

=cut

sub PDLA::indexND {
        my($source,$index, $boundary) = @_;
        return PDLA::range($source,$index,undef,$boundary);
}

*PDLA::indexNDb = \&PDLA::indexND;

sub PDLA::range {
  my($source,$ind,$sz,$bound) = @_;

# Convert to indx type up front (also handled in rangeb if necessary)
  my $index = (ref $ind && UNIVERSAL::isa($ind,'PDLA') && $ind->type eq 'indx') ? $ind : indx($ind);
  my $size = defined($sz) ? PDLA->pdl($sz) : undef;


  # Handle empty PDLA case: return a properly constructed Empty.
  if($index->isempty) {
      my @sdims= $source->dims;
      splice(@sdims, 0, $index->dim(0) + ($index->dim(0)==0)); # added term is to treat Empty[0] like a single empty coordinate
      unshift(@sdims, $size->list) if(defined($size));
      return PDLA->new_from_specification(0 x ($index->ndims-1), @sdims);
  }


  $index = $index->dummy(0,1) unless $index->ndims;


  # Pack boundary string if necessary
  if(defined $bound) {
    if(ref $bound eq 'ARRAY') {
      my ($s,$el);
      foreach $el(@$bound) {
        barf "Illegal boundary value '$el' in range"
          unless( $el =~ m/^([0123fFtTeEpPmM])/ );
        $s .= $1;
      }
      $bound = $s;
    }
    elsif($bound !~ m/^[0123ftepx]+$/  && $bound =~ m/^([0123ftepx])/i ) {
      $bound = $1;
    }
  }

  no warnings; # shut up about passing undef into rangeb
  $source->rangeb($index,$size,$bound);
}

=head2 range

=for ref

Engine for L<range|/range>

=for example

Same calling convention as L<range|/range>, but you must supply all
parameters.  C<rangeb> is marginally faster as it makes a direct PP call,
avoiding the perl argument-parsing step.

=cut

=head2 range

=for ref

Extract selected chunks from a source piddle, with boundary conditions

=for example

        $out = $source->range($index,[$size,[$boundary]])

Returns elements or rectangular slices of the original piddle, indexed by
the C<$index> piddle.  C<$source> is an N-dimensional piddle, and C<$index> is
a piddle whose first dimension has size up to N.  Each row of C<$index> is
treated as coordinates of a single value or chunk from C<$source>, specifying
the location(s) to extract.

If you specify a single index location, then range is essentially an expensive
slice, with controllable boundary conditions.

B<INPUTS>

C<$index> and C<$size> can be piddles or array refs such as you would
feed to L<zeroes|PDLA::Core/zeroes> and its ilk.  If C<$index>'s 0th dimension
has size higher than the number of dimensions in C<$source>, then
C<$source> is treated as though it had trivial dummy dimensions of
size 1, up to the required size to be indexed by C<$index> -- so if
your source array is 1-D and your index array is a list of 3-vectors,
you get two dummy dimensions of size 1 on the end of your source array.

You can extract single elements or N-D rectangular ranges from C<$source>,
by setting C<$size>.  If C<$size> is undef or zero, then you get a single
sample for each row of C<$index>.  This behavior is similar to
L<indexNDb|/indexNDb>, which is in fact implemented as a call to L<range|/range>.

If C<$size> is positive then you get a range of values from C<$source> at
each location, and the output has extra dimensions allocated for them.
C<$size> can be a scalar, in which case it applies to all dimensions, or an
N-vector, in which case each element is applied independently to the
corresponding dimension in C<$source>.  See below for details.

C<$boundary> is a number, string, or list ref indicating the type of
boundary conditions to use when ranges reach the edge of C<$source>.  If you
specify no boundary conditions the default is to forbid boundary violations
on all axes.  If you specify exactly one boundary condition, it applies to
all axes.  If you specify more (as elements of a list ref, or as a packed
string, see below), then they apply to dimensions in the order in which they
appear, and the last one applies to all subsequent dimensions.  (This is
less difficult than it sounds; see the examples below).

=over 3

=item 0 (synonyms: 'f','forbid') B<(default)>

Ranges are not allowed to cross the boundary of the original PDLA.  Disallowed
ranges throw an error.  The errors are thrown at evaluation time, not
at the time of the range call (this is the same behavior as L<slice|/slice>).

=item 1 (synonyms: 't','truncate')

Values outside the original piddle get BAD if you've got bad value
support compiled into your PDLA and set the badflag for the source PDLA;
or 0 if you haven't (you must set the badflag if you want BADs for out
of bound values, otherwise you get 0).  Reverse dataflow works OK for
the portion of the child that is in-bounds.  The out-of-bounds part of
the child is reset to (BAD|0) during each dataflow operation, but
execution continues.

=item 2 (synonyms: 'e','x','extend')

Values that would be outside the original piddle point instead to the
nearest allowed value within the piddle.  See the CAVEAT below on
mappings that are not single valued.

=item 3 (synonyms: 'p','periodic')

Periodic boundary conditions apply: the numbers in $index are applied,
strict-modulo the corresponding dimensions of $source.  This is equivalent to
duplicating the $source piddle throughout N-D space.  See the CAVEAT below
about mappings that are not single valued.

=item 4 (synonyms: 'm','mirror')

Mirror-reflection periodic boundary conditions apply.  See the CAVEAT
below about mappings that are not single valued.

=back

The boundary condition identifiers all begin with unique characters, so
you can feed in multiple boundary conditions as either a list ref or a
packed string.  (The packed string is marginally faster to run).  For
example, the four expressions [0,1], ['forbid','truncate'], ['f','t'],
and 'ft' all specify that violating the boundary in the 0th dimension
throws an error, and all other dimensions get truncated.

If you feed in a single string, it is interpreted as a packed boundary
array if all of its characters are valid boundary specifiers (e.g. 'pet'),
but as a single word-style specifier if they are not (e.g. 'forbid').

B<OUTPUT>

The output threads over both C<$index> and C<$source>.  Because implicit
threading can happen in a couple of ways, a little thought is needed.  The
returned dimension list is stacked up like this:

   (index thread dims), (index dims (size)), (source thread dims)

The first few dims of the output correspond to the extra dims of
C<$index> (beyond the 0 dim). They allow you to pick out individual
ranges from a large, threaded collection.

The middle few dims of the output correspond to the size dims
specified in C<$size>, and contain the range of values that is extracted
at each location in C<$source>.  Every nonzero element of C<$size> is copied to
the dimension list here, so that if you feed in (for example) C<$size
= [2,0,1]> you get an index dim list of C<(2,1)>.

The last few dims of the output correspond to extra dims of C<$source> beyond
the number of dims indexed by C<$index>.  These dims act like ordinary
thread dims, because adding more dims to C<$source> just tacks extra dims
on the end of the output.  Each source thread dim ranges over the entire
corresponding dim of C<$source>.

B<Dataflow>: Dataflow is bidirectional.

B<Examples>:
Here are basic examples of C<range> operation, showing how to get
ranges out of a small matrix.  The first few examples show extraction
and selection of individual chunks.  The last example shows
how to mark loci in the original matrix (using dataflow).

 pdla> $src = 10*xvals(10,5)+yvals(10,5)
 pdla> print $src->range([2,3])    # Cut out a single element
 23
 pdla> print $src->range([2,3],1)  # Cut out a single 1x1 block
 [
  [23]
 ]
 pdla> print $src->range([2,3], [2,1]) # Cut a 2x1 chunk
 [
  [23 33]
 ]
 pdla> print $src->range([[2,3]],[2,1]) # Trivial list of 1 chunk
 [
  [
   [23]
   [33]
  ]
 ]
 pdla> print $src->range([[2,3],[0,1]], [2,1])   # two 2x1 chunks
 [
  [
   [23  1]
   [33 11]
  ]
 ]
 pdla> # A 2x2 collection of 2x1 chunks
 pdla> print $src->range([[[1,1],[2,2]],[[2,3],[0,1]]],[2,1])
 [
  [
   [
    [11 22]
    [23  1]
   ]
   [
    [21 32]
    [33 11]
   ]
  ]
 ]
 pdla> $src = xvals(5,3)*10+yvals(5,3)
 pdla> print $src->range(3,1)  # Thread over y dimension in $src
 [
  [30]
  [31]
  [32]
 ]

 pdla> $src = zeroes(5,4);
 pdla> $src->range(pdl([2,3],[0,1]),pdl(2,1)) .= xvals(2,2,1) + 1
 pdla> print $src
 [
  [0 0 0 0 0]
  [2 2 0 0 0]
  [0 0 0 0 0]
  [0 0 1 1 0]
 ]

B<CAVEAT>: It's quite possible to select multiple ranges that
intersect.  In that case, modifying the ranges doesn't have a
guaranteed result in the original PDLA -- the result is an arbitrary
choice among the valid values.  For some things that's OK; but for
others it's not. In particular, this doesn't work:

    pdla> $photon_list = new PDLA::RandVar->sample(500)->reshape(2,250)*10
    pdla> histogram = zeroes(10,10)
    pdla> histogram->range($photon_list,1)++;  #not what you wanted

The reason is that if two photons land in the same bin, then that bin
doesn't get incremented twice.  (That may get fixed in a later version...)

B<PERMISSIVE RANGING>: If C<$index> has too many dimensions compared
to C<$source>, then $source is treated as though it had dummy
dimensions of size 1, up to the required number of dimensions.  These
virtual dummy dimensions have the usual boundary conditions applied to
them.

If the 0 dimension of C<$index> is ludicrously large (if its size is
more than 5 greater than the number of dims in the source PDLA) then
range will insist that you specify a size in every dimension, to make
sure that you know what you're doing.  That catches a common error with
range usage: confusing the initial dim (which is usually small) with another
index dim (perhaps of size 1000).

If the index variable is Empty, then range() always returns the Empty PDLA.
If the index variable is not Empty, indexing it always yields a boundary
violation.  All non-barfing conditions are treated as truncation, since
there are no actual data to return.

B<EFFICIENCY>: Because C<range> isn't an affine transformation (it
involves lookup into a list of N-D indices), it is somewhat
memory-inefficient for long lists of ranges, and keeping dataflow open
is much slower than for affine transformations (which don't have to copy
data around).

Doing operations on small subfields of a large range is inefficient
because the engine must flow the entire range back into the original
PDLA with every atomic perl operation, even if you only touch a single element.
One way to speed up such code is to sever your range, so that PDLA
doesn't have to copy the data with each operation, then copy the
elements explicitly at the end of your loop.  Here's an example that
labels each region in a range sequentially, using many small
operations rather than a single xvals assignment:

  ### How to make a collection of small ops run fast with range...
  $x =  $data->range($index, $sizes, $bound)->sever;
  $aa = $data->range($index, $sizes, $bound);
  map { $x($_ - 1) .= $_; } (1..$x->nelem);    # Lots of little ops
  $aa .= $x;

C<range> is a perl front-end to a PP function, C<rangeb>.  Calling
C<rangeb> is marginally faster but requires that you include all arguments.

DEVEL NOTES

* index thread dimensions are effectively clumped internally.  This
makes it easier to loop over the index array but a little more brain-bending
to tease out the algorithm.

=cut

=head2 rld

=for ref

Run-length decode a vector

Given a vector C<$x> of the numbers of instances of values C<$y>, run-length
decode to C<$c>.

=for example

 rld($x,$y,$c=null);

=cut

sub PDLA::rld {
  my ($x,$y) = @_;
  my ($c);
  if ($#_ == 2) {
    $c = $_[2];
  } else {
# XXX Need to improve emulation of threading in auto-generating c
    my ($size) = $x->sumover->max;
    my (@dims) = $x->dims;
    shift @dims;
    $c = $y->zeroes($size,@dims);
  }
  &PDLA::_rld_int($x,$y,$c);
  $c;
}

=head2 rle

=for ref

Run-length encode a vector

Given vector C<$c>, generate a vector C<$x> with the number of each
element, and a vector C<$y> of the unique values.  New in PDLA 2.017,
only the elements up to the first instance of C<0> in C<$x> are
returned, which makes the common use case of a 1-dimensional C<$c> simpler.
For threaded operation, C<$x> and C<$y> will be large enough
to hold the largest row of C<$y>, and only the elements up to the
first instance of C<0> in each row of C<$x> should be considered.

=for example

 $c = floor(4*random(10));
 rle($c,$x=null,$y=null);
 #or
 ($x,$y) = rle($c);

 #for $c of shape [10, 4]:
 $c = floor(4*random(10,4));
 ($x,$y) = rle($c);

 #to see the results of each row one at a time:
 foreach (0..$c->dim(1)-1){
  my ($as,$bs) = ($x(:,($_)),$y(:,($_)));
  my ($ta,$tb) = where($as,$bs,$as!=0); #only the non-zero elements of $x
  print $c(:,($_)) . " rle==> " , ($ta,$tb) , "\trld==> " . rld($ta,$tb) . "\n";
 }

=cut

sub PDLA::rle {
  my $c = shift;
  my ($x,$y) = @_==2 ? @_ : (null,null);
  &PDLA::_rle_int($c,$x,$y);
  my $max_ind = ($c->ndims<2) ? ($x!=0)->sumover-1 :
                                ($x!=0)->clump(1..$x->ndims-1)->sumover->max-1;
  return ($x->slice("0:$max_ind"),$y->slice("0:$max_ind"));
}

=head2 xchg

=for ref

exchange two dimensions

Negative dimension indices count from the end.

The command

=for example

 $y = $x->xchg(2,3);

creates C<$y> to be like C<$x> except that the dimensions 2 and 3
are exchanged with each other i.e.

 $y->at(5,3,2,8) == $x->at(5,3,8,2)

=cut

=head2 reorder

=for ref

Re-orders the dimensions of a PDLA based on the supplied list.

Similar to the L<xchg|/xchg> method, this method re-orders the dimensions
of a PDLA. While the L<xchg|/xchg> method swaps the position of two dimensions,
the reorder method can change the positions of many dimensions at
once.

=for usage

 # Completely reverse the dimension order of a 6-Dim array.
 $reOrderedPDLA = $pdl->reorder(5,4,3,2,1,0);

The argument to reorder is an array representing where the current dimensions
should go in the new array. In the above usage, the argument to reorder
C<(5,4,3,2,1,0)>
indicates that the old dimensions (C<$pdl>'s dims) should be re-arranged to make the
new pdl (C<$reOrderPDLA>) according to the following:

   Old Position   New Position
   ------------   ------------
   5              0
   4              1
   3              2
   2              3
   1              4
   0              5

You do not need to specify all dimensions, only a complete set
starting at position 0.  (Extra dimensions are left where they are).
This means, for example, that you can reorder() the X and Y dimensions of
an image, and not care whether it is an RGB image with a third dimension running
across color plane.

=for example

Example:

 pdla> $x = sequence(5,3,2);       # Create a 3-d Array
 pdla> p $x
 [
  [
   [ 0  1  2  3  4]
   [ 5  6  7  8  9]
   [10 11 12 13 14]
  ]
  [
   [15 16 17 18 19]
   [20 21 22 23 24]
   [25 26 27 28 29]
  ]
 ]
 pdla> p $x->reorder(2,1,0); # Reverse the order of the 3-D PDLA
 [
  [
   [ 0 15]
   [ 5 20]
   [10 25]
  ]
  [
   [ 1 16]
   [ 6 21]
   [11 26]
  ]
  [
   [ 2 17]
   [ 7 22]
   [12 27]
  ]
  [
   [ 3 18]
   [ 8 23]
   [13 28]
  ]
  [
   [ 4 19]
   [ 9 24]
   [14 29]
  ]
 ]

The above is a simple example that could be duplicated by calling
C<$x-E<gt>xchg(0,2)>, but it demonstrates the basic functionality of reorder.

As this is an index function, any modifications to the
result PDLA will change the parent.

=cut

sub PDLA::reorder {
        my ($pdl,@newDimOrder) = @_;

        my $arrayMax = $#newDimOrder;

        #Error Checking:
        if( $pdl->getndims < scalar(@newDimOrder) ){
                my $errString = "PDLA::reorder: Number of elements (".scalar(@newDimOrder).") in newDimOrder array exceeds\n";
                $errString .= "the number of dims in the supplied PDLA (".$pdl->getndims.")";
                barf($errString);
        }

        # Check to make sure all the dims are within bounds
        for my $i(0..$#newDimOrder) {
          my $dim = $newDimOrder[$i];
          if($dim < 0 || $dim > $#newDimOrder) {
              my $errString = "PDLA::reorder: Dim index $newDimOrder[$i] out of range in position $i\n(range is 0-$#newDimOrder)";
              barf($errString);
          }
        }

        # Checking that they are all present and also not duplicated is done by thread() [I think]

        # a quicker way to do the reorder
        return $pdl->thread(@newDimOrder)->unthread(0);
}

=head2 mv

=for ref

move a dimension to another position

The command

=for example

 $y = $x->mv(4,1);

creates C<$y> to be like C<$x> except that the dimension 4 is moved to the
place 1, so:

 $y->at(1,2,3,4,5,6) == $x->at(1,5,2,3,4,6);

The other dimensions are moved accordingly.
Negative dimension indices count from the end.
=cut

=head2 oslice

=for ref

DEPRECATED:  'oslice' is the original 'slice' routine in pre-2.006_006
versions of PDLA.  It is left here for reference but will disappear in
PDLA 3.000

Extract a rectangular slice of a piddle, from a string specifier.

C<slice> was the original Swiss-army-knife PDLA indexing routine, but is
largely superseded by the L<NiceSlice|PDLA::NiceSlice> source prefilter
and its associated L<nslice|PDLA::Core/nslice> method.  It is still used as the
basic underlying slicing engine for L<nslice|PDLA::Core/nslice>,
and is especially useful in particular niche applications.

=for example

 $x->slice('1:3');  #  return the second to fourth elements of $x
 $x->slice('3:1');  #  reverse the above
 $x->slice('-2:1'); #  return last-but-one to second elements of $x

The argument string is a comma-separated list of what to do
for each dimension. The current formats include
the following, where I<a>, I<b> and I<c> are integers and can
take legal array index values (including -1 etc):

=over 8

=item :

takes the whole dimension intact.

=item ''

(nothing) is a synonym for ":"
(This means that C<$x-E<gt>slice(':,3')> is equal to C<$x-E<gt>slice(',3')>).

=item a

slices only this value out of the corresponding dimension.

=item (a)

means the same as "a" by itself except that the resulting
dimension of length one is deleted (so if C<$x> has dims C<(3,4,5)> then
C<$x-E<gt>slice(':,(2),:')> has dimensions C<(3,5)> whereas
C<$x-E<gt>slice(':,2,:')> has dimensions C<(3,1,5))>.

=item a:b

slices the range I<a> to I<b> inclusive out of the dimension.

=item a:b:c

slices the range I<a> to I<b>, with step I<c> (i.e. C<3:7:2> gives the indices
C<(3,5,7)>). This may be confusing to Matlab users but several other
packages already use this syntax.


=item '*'

inserts an extra dimension of width 1 and

=item '*a'

inserts an extra (dummy) dimension of width I<a>.

=back

An extension is planned for a later stage allowing
C<$x-E<gt>slice('(=1),(=1|5:8),3:6(=1),4:6')>
to express a multidimensional diagonal of C<$x>.

Trivial out-of-bounds slicing is allowed: if you slice a source
dimension that doesn't exist, but only index the 0th element, then
C<slice> treats the source as if there were a dummy dimension there.
The following are all equivalent:

        xvals(5)->dummy(1,1)->slice('(2),0')  # Add dummy dim, then slice
        xvals(5)->slice('(2),0')              # Out-of-bounds slice adds dim.
        xvals(5)->slice((2),0)                # NiceSlice syntax
        xvals(5)->((2))->dummy(0,1)           # NiceSlice syntax

This is an error:

        xvals(5)->slice('(2),1')        # nontrivial out-of-bounds slice dies

Because slicing doesn't directly manipulate the source and destination
pdl -- it just sets up a transformation between them -- indexing errors
often aren't reported until later.  This is either a bug or a feature,
depending on whether you prefer error-reporting clarity or speed of execution.

=cut

=head2 using

=for ref

Returns array of column numbers requested

=for usage

 line $pdl->using(1,2);

Plot, as a line, column 1 of C<$pdl> vs. column 2

=for example

 pdla> $pdl = rcols("file");
 pdla> line $pdl->using(1,2);

=cut

*using = \&PDLA::using;
sub PDLA::using {
  my ($x,@ind)=@_;
  @ind = list $ind[0] if (blessed($ind[0]) && $ind[0]->isa('PDLA'));
  foreach (@ind) {
    $_ = $x->slice("($_)");
  }
  @ind;
}

=head2 diagonalI

=for ref

Returns the multidimensional diagonal over the specified dimensions.

The diagonal is placed at the first (by number) dimension that is
diagonalized.
The other diagonalized dimensions are removed. So if C<$x> has dimensions
C<(5,3,5,4,6,5)> then after

=for example

 $y = $x->diagonal(0,2,5);

the piddle C<$y> has dimensions C<(5,3,4,6)> and
C<$y-E<gt>at(2,1,0,1)> refers
to C<$x-E<gt>at(2,1,2,0,1,2)>.

NOTE: diagonal doesn't handle threadids correctly. XXX FIX
=cut
=head2 lags

=for ref

Returns a piddle of lags to parent.

Usage:

=for usage

  $lags = $x->lags($nthdim,$step,$nlags);

I.e. if C<$x> contains

 [0,1,2,3,4,5,6,7]

then

=for example

 $y = $x->lags(0,2,2);

is a (5,2) matrix

 [2,3,4,5,6,7]
 [0,1,2,3,4,5]

This order of returned indices is kept because the function is
called "lags" i.e. the nth lag is n steps behind the original.

C<$step> and C<$nlags> must be positive. C<$nthdim> can be
negative and will then be counted from the last dim backwards
in the usual way (-1 = last dim).
=cut
=head2 splitdim

=for ref

Splits a dimension in the parent piddle (opposite of L<clump|PDLA::Core/clump>)

After

=for example

 $y = $x->splitdim(2,3);

the expression

 $y->at(6,4,m,n,3,6) == $x->at(6,4,m+3*n)

is always true (C<m> has to be less than 3).
=cut
=head2 rotate

=for ref

Shift vector elements along with wrap. Flows data back&forth.
=cut
=head2 threadI

=for ref

internal

Put some dimensions to a threadid.

=for example

 $y = $x->threadI(0,1,5); # thread over dims 1,5 in id 1

=cut

=head2 identvaff

=for ref

A vaffine identity transformation (includes thread_id copying).

Mainly for internal use.
=cut
=head2 unthread

=for ref

All threaded dimensions are made real again.

See [TBD Doc] for details and examples.
=cut

=head2 dice

=for ref

Dice rows/columns/planes out of a PDLA using indexes for
each dimension.

This function can be used to extract irregular subsets
along many dimension of a PDLA, e.g. only certain rows in an image,
or planes in a cube. This can of course be done with
the usual dimension tricks but this saves having to
figure it out each time!

This method is similar in functionality to the L<slice|/slice>
method, but L<slice|/slice> requires that contiguous ranges or ranges
with constant offset be extracted. ( i.e. L<slice|/slice> requires
ranges of the form C<1,2,3,4,5> or C<2,4,6,8,10>). Because of this
restriction, L<slice|/slice> is more memory efficient and slightly faster
than dice

=for usage

 $slice = $data->dice([0,2,6],[2,1,6]); # Dicing a 2-D array

The arguments to dice are arrays (or 1D PDLAs) for each dimension
in the PDLA. These arrays are used as indexes to which rows/columns/cubes,etc
to dice-out (or extract) from the C<$data> PDLA.

Use C<X> to select all indices along a given dimension (compare also
L<mslice|PDLA::Core/mslice>). As usual (in slicing methods) trailing
dimensions can be omitted implying C<X>'es for those.

=for example

 pdla> $x = sequence(10,4)
 pdla> p $x
 [
  [ 0  1  2  3  4  5  6  7  8  9]
  [10 11 12 13 14 15 16 17 18 19]
  [20 21 22 23 24 25 26 27 28 29]
  [30 31 32 33 34 35 36 37 38 39]
 ]
 pdla> p $x->dice([1,2],[0,3]) # Select columns 1,2 and rows 0,3
 [
  [ 1  2]
  [31 32]
 ]
 pdla> p $x->dice(X,[0,3])
 [
  [ 0  1  2  3  4  5  6  7  8  9]
  [30 31 32 33 34 35 36 37 38 39]
 ]
 pdla> p $x->dice([0,2,5])
 [
  [ 0  2  5]
  [10 12 15]
  [20 22 25]
  [30 32 35]
 ]

As this is an index function, any modifications to the
slice change the parent (use the C<.=> operator).

=cut

sub PDLA::dice {

        my $self = shift;
        my @dim_indexes = @_;  # array of dimension indexes

        # Check that the number of dim indexes <=
        #    number of dimensions in the PDLA
        my $no_indexes = scalar(@dim_indexes);
        my $noDims = $self->getndims;
        barf("PDLA::dice: Number of index arrays ($no_indexes) not equal to the dimensions of the PDLA ($noDims")
                         if $no_indexes > $noDims;
        my $index;
        my $pdlIndex;
        my $outputPDLA=$self;
        my $indexNo = 0;

        # Go thru each index array and dice the input PDLA:
        foreach $index(@dim_indexes){
                $outputPDLA = $outputPDLA->dice_axis($indexNo,$index)
                        unless !ref $index && $index eq 'X';

                $indexNo++;
        }

        return $outputPDLA;
}
*dice = \&PDLA::dice;


=head2 dice_axis

=for ref

Dice rows/columns/planes from a single PDLA axis (dimension)
using index along a specified axis

This function can be used to extract irregular subsets
along any dimension, e.g. only certain rows in an image,
or planes in a cube. This can of course be done with
the usual dimension tricks but this saves having to
figure it out each time!

=for usage

 $slice = $data->dice_axis($axis,$index);

=for example

 pdla> $x = sequence(10,4)
 pdla> $idx = pdl(1,2)
 pdla> p $x->dice_axis(0,$idx) # Select columns
 [
  [ 1  2]
  [11 12]
  [21 22]
  [31 32]
 ]
 pdla> $t = $x->dice_axis(1,$idx) # Select rows
 pdla> $t.=0
 pdla> p $x
 [
  [ 0  1  2  3  4  5  6  7  8  9]
  [ 0  0  0  0  0  0  0  0  0  0]
  [ 0  0  0  0  0  0  0  0  0  0]
  [30 31 32 33 34 35 36 37 38 39]
 ]

The trick to using this is that the index selects
elements along the dimensions specified, so if you
have a 2D image C<axis=0> will select certain C<X> values
- i.e. extract columns

As this is an index function, any modifications to the
slice change the parent.

=cut

sub PDLA::dice_axis {
  my($self,$axis,$idx) = @_;

  # Convert to PDLAs: array refs using new, otherwise use topdl:
  my $ix = (ref($idx) eq 'ARRAY') ? ref($self)->new($idx) : ref($self)->topdl($idx);
  my $n = $self->getndims;
  my $x = $ix->getndims;
  barf("index_axis: index must be <=1D") if $x>1;
  return $self->mv($axis,0)->index1d($ix)->mv(0,$axis);
}
*dice_axis = \&PDLA::dice_axis;

=head2 slice

=for usage

  $slice = $data->slice([2,3],'x',[2,2,0],"-1:1:-1", "*3");

=for ref

Extract rectangular slices of a piddle, from a string specifier,
an array ref specifier, or a combination.

C<slice> is the main method for extracting regions of PDLAs and
manipulating their dimensionality.  You can call it directly or
via he L<NiceSlice|PDLA::NiceSlice> source prefilter that extends
Perl syntax o include array slicing.

C<slice> can extract regions along each dimension of a source PDLA,
subsample or reverse those regions, dice each dimension by selecting a
list of locations along it, or basic PDLA indexing routine.  The
selected subfield remains connected to the original PDLA via dataflow.
In most cases this neither allocates more memory nor slows down
subsequent operations on either of the two connected PDLAs.

You pass in a list of arguments.  Each term in the list controls
the disposition of one axis of the source PDLA and/or returned PDLA.
Each term can be a string-format cut specifier, a list ref that
gives the same information without recourse to string manipulation,
or a PDLA with up to 1 dimension giving indices along that axis that
should be selected.

If you want to pass in a single string specifier for the entire
operation, you can pass in a comma-delimited list as the first
argument.  C<slice> detects this condition and splits the string
into a regular argument list.  This calling style is fully
backwards compatible with C<slice> calls from before PDLA 2.006.

B<STRING SYNTAX>

If a particular argument to C<slice> is a string, it is parsed as a
selection, an affine slice, or a dummy dimension depending on the
form.  Leading or trailing whitespace in any part of each specifier is
ignored (though it is not ignored within numbers).

=over 3

=item C<< '' >>, C<< : >>, or C<< X >> -- keep

The empty string, C<:>, or C<X> cause the entire corresponding
dimension to be kept unchanged.


=item C<< <n> >> -- selection

A single number alone causes a single index to be selected from the
corresponding dimension.  The dimension is kept (and reduced to size
1) in the output.

=item C<< (<n>) >> -- selection and collapse

A single number in parenthesis causes a single index to be selected
from the corresponding dimension.  The dimension is discarded
(completely eliminated) in the output.

=item C<< <n>:<m> >> -- select an inclusive range

Two numbers separated by a colon selects a range of values from the
corresponding axis, e.g. C<< 3:4 >> selects elements 3 and 4 along the
corresponding axis, and reduces that axis to size 2 in the output.
Both numbers are regularized so that you can address the last element
of the axis with an index of C< -1 >.  If, after regularization, the
two numbers are the same, then exactly one element gets selected (just
like the C<< <n> >> case).  If, after regulariation, the second number
is lower than the first, then the resulting slice counts down rather
than up -- e.g. C<-1:0> will return the entire axis, in reversed
order.

=item C<< <n>:<m>:<s> >> -- select a range with explicit step

If you include a third parameter, it is the stride of the extracted
range.  For example, C<< 0:-1:2 >> will sample every other element
across the complete dimension.  Specifying a stride of 1 prevents
autoreversal -- so to ensure that your slice is *always* forward
you can specify, e.g., C<< 2:$n:1 >>.  In that case, an "impossible"
slice gets an Empty PDLA (with 0 elements along the corresponding
dimension), so you can generate an Empty PDLA with a slice of the
form C<< 2:1:1 >>.

=item C<< *<n> >> -- insert a dummy dimension

Dummy dimensions aren't present in the original source and are
"mocked up" to match dimensional slots, by repeating the data
in the original PDLA some number of times.  An asterisk followed
by a number produces a dummy dimension in the output, for
example C<< *2 >> will generate a dimension of size 2 at
the corresponding location in the output dim list.  Omitting
the numeber (and using just an asterisk) inserts a dummy dimension
of size 1.

=back

B<ARRAY REF SYNTAX>

If you feed in an ARRAY ref as a slice term, then it can have
0-3 elements.  The first element is the start of the slice along
the corresponding dim; the second is the end; and the third is
the stepsize.  Different combinations of inputs give the same
flexibility as the string syntax.

=over 3

=item C<< [] >> - keep dim intact

An empty ARRAY ref keeps the entire corresponding dim

=item C<< [ 'X' ] >> - keep dim intact

=item C<< [ '*',$n ] >> - generate a dummy dim of size $n

If $n is missing, you get a dummy dim of size 1.

=item C<< [ $dex, , 0 ] >> - collapse and discard dim

C<$dex> must be a single value.  It is used to index
the source, and the corresponding dimension is discarded.

=item C<< [ $start, $end ] >> - collect inclusive slice

In the simple two-number case, you get a slice that runs
up or down (as appropriate) to connect $start and $end.

=item C<< [ $start, $end, $inc ] >> - collect inclusive slice

The three-number case works exactly like the three-number
string case above.

=back

B<PDLA args for dicing>

If you pass in a 0- or 1-D PDLA as a slicing argument, the
corresponding dimension is "diced" -- you get one position
along the corresponding dim, per element of the indexing PDLA,
e.g. C<< $x->slice( pdl(3,4,9)) >> gives you elements 3, 4, and
9 along the 0 dim of C<< $x >>.

Because dicing is not an affine transformation, it is slower than
direct slicing even though the syntax is convenient.


=for example

 $x->slice('1:3');  #  return the second to fourth elements of $x
 $x->slice('3:1');  #  reverse the above
 $x->slice('-2:1'); #  return last-but-one to second elements of $x

 $x->slice([1,3]);  # Same as above three calls, but using array ref syntax
 $x->slice([3,1]);
 $x->slice([-2,1]);

=cut


##############################
# 'slice' is now implemented as a small Perl wrapper around
# a PP call.  This permits unification of the former slice,
# dice, and nslice into a single call.  At the moment, dicing
# is implemented a bit kludgily (it is detected in the Perl
# front-end), but it is serviceable.
#  --CED 12-Sep-2013

*slice = \&PDLA::slice;
sub PDLA::slice (;@) {
    my ($source, @others) = @_;

    # Deal with dicing.  This is lame and slow compared to the
    # faster slicing, but works okay.  We loop over each argument,
    # and if it's a PDLA we dispatch it in the most straightforward
    # way.  Single-element and zero-element PDLAs are trivial and get
    # converted into slices for faster handling later.

    for my $i(0..$#others) {
      if( blessed($others[$i]) && $others[$i]->isa('PDLA') ) {
        my $idx = $others[$i];
        if($idx->ndims > 1) {
          barf("slice: dicing parameters must be at most 1D (arg $i)\n");
        }
        my $nlm = $idx->nelem;

        if($nlm > 1) {

	   #### More than one element - we have to dice (darn it).
           my $n = $source->getndims;
           $source = $source->mv($i,0)->index1d($idx)->mv(0,$i);
           $others[$i] = '';

        } 
	elsif($nlm) {

           #### One element - convert to a regular slice.
           $others[$i] = $idx->flat->at(0);

        }
	else {
	
           #### Zero elements -- force an extended empty.
           $others[$i] = "1:0:1";
        }
      }
    }

    PDLA::sliceb($source,\@others);
}

=head1 BUGS

For the moment, you can't slice one of the zero-length dims of an
empty piddle.  It is not clear how to implement this in a way that makes
sense.

Many types of index errors are reported far from the indexing
operation that caused them.  This is caused by the underlying architecture:
slice() sets up a mapping between variables, but that mapping isn't
tested for correctness until it is used (potentially much later).

=head1 AUTHOR

Copyright (C) 1997 Tuomas J. Lukka.  Contributions by
Craig DeForest, deforest@boulder.swri.edu.
Documentation contributions by David Mertens.
All rights reserved. There is no warranty. You are allowed
to redistribute this software / documentation under certain
conditions. For details, see the file COPYING in the PDLA
distribution. If this file is separated from the PDLA distribution,
the copyright notice should be included in the file.

=cut

1;

__DATA__

__Pdlapp__

# $::PP_VERBOSE=1;

pp_addhdr(<<'EOH');

#ifdef _MSC_VER
#if _MSC_VER < 1300
#define strtoll strtol
#else
#define strtoll _strtoi64
#endif
#endif

EOH

pp_add_boot(
"  PDLA->readdata_affine = pdl_readdata_affineinternal;\n" .
"     PDLA->writebackdata_affine = pdl_writebackdata_affineinternal;\n"
);

## Several routines use the 'Dims' and 'ParentInds'
## rules - these currently do nothing

pp_def(
       'affineinternal',
       HandleBad => 1,
       AffinePriv => 1,
       DefaultFlow => 1,
       P2Child => 1,
       NoPdlThread => 1,
       ReadDataFuncName => "pdl_readdata_affineinternal",
       WriteBackDataFuncName => "pdl_writebackdata_affineinternal",
       MakeComp => '$CROAK("AFMC MUSTNT BE CALLED");',
       RedoDims => '$CROAK("AFRD MUSTNT BE CALLED");',
       EquivCPOffsCode => '
                PDLA_Indx i; PDLA_Indx poffs=$PRIV(offs); int nd;
                for(i=0; i<$CHILD_P(nvals); i++) {
                        $EQUIVCPOFFS(i,poffs);
                        for(nd=0; nd<$CHILD_P(ndims); nd++) {
                                poffs += $PRIV(incs[nd]);
                                if( (nd<$CHILD_P(ndims)-1 &&
                                     (i+1)%$CHILD_P(dimincs[nd+1])) ||
                                   nd == $CHILD_P(ndims)-1)
                                        break;
                                poffs -= $PRIV(incs[nd]) *
                                        $CHILD_P(dims[nd]);
                        }
                }',
       Doc => undef,    # 'internal',
);

=head2 s_identity
=cut

pp_def(
        's_identity',
        HandleBad => 1,
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        OtherPars => '',
        Reversible => 1,
        Dims => '$COPYDIMS();',
        ParentInds => '$COPYINDS();',
        Identity => 1,
        Doc => undef, # Internal vaffine identity function.
);

my $index_init_good =
       'register PDLA_Indx foo = $ind();
        if( foo<0 || foo>=$SIZE(n) ) {
           barf("PDLA::index: invalid index %d (valid range 0..%d)",
                foo,$SIZE(n)-1);
        }';
my $index_init_bad =
       'register PDLA_Indx foo = $ind();
        if( $ISBADVAR(foo,ind) || foo<0 || foo>=$SIZE(n) ) {
           barf("PDLA::index: invalid index %d (valid range 0..%d)",
                foo,$SIZE(n)-1);
        }';

pp_def(
       'index',
       HandleBad => 1,
       DefaultFlow => 1,
       Reversible => 1,
       Pars => 'a(n); indx ind(); [oca] c();',
       Code =>
       $index_init_good . ' $c() = $a(n => foo);',
       BadCode =>
       $index_init_bad . ' $c() = $a(n => foo);',
       BackCode =>
       $index_init_good . ' $a(n => foo) = $c();',
       BadBackCode =>
       $index_init_bad . ' $a(n => foo) = $c();',
       );

pp_def(
       'index1d',
       HandleBad => 1,
       DefaultFlow => 1,
       Reversible => 1,
       Pars => 'a(n); indx ind(m); [oca] c(m);',
       Code =>
       q{
         PDLA_Indx i;
         for(i=0;i<$SIZE(m);i++) {
                  PDLA_Indx foo = $ind(m=>i);
                  if( foo<0 || foo >= $SIZE(n) ) {
                   barf("PDLA::index1d: invalid index %d at pos %d (valid range 0..%d)",
                     foo, i, $SIZE(n)-1);
                  }
                  $c(m=>i) = $a(n=>foo);
         }
        },
        BadCode =>
        q{
         PDLA_Indx i;
         for(i=0;i<$SIZE(m);i++) {
                 PDLA_Indx foo = $ind(m=>i);
                 if( $ISBADVAR(foo, ind) ) {
                     $SETBAD(c(m=>i));
                 } else {
                   if( foo<0 || foo >= $SIZE(n) ) {
                     barf("PDLA::index1d: invalid/bad index %d at pos %d (valid range 0..%d)",
                      foo, i, $SIZE(n)-1);
                   }
                   $c(m=>i) = $a(n=>foo);
                 }
         }
        },
       BackCode => q{
         PDLA_Indx i;
         for(i=0;i<$SIZE(m);i++) {
                PDLA_Indx foo = $ind(m=>i);
                if( foo<0 || foo >= $SIZE(n) ) {
                 barf("PDLA::index1d: invalid index %d at pos %d (valid range 0..%d)",
                   foo, i, $SIZE(n)-1);
                }
                $a(n=>foo) = $c(m=>i);
         }
        },
       BadBackCode => q{
         PDLA_Indx i;
         for(i=0;i<$SIZE(m);i++) {
                 PDLA_Indx foo = $ind(m=>i);
                 if( $ISBADVAR(foo, ind) ) {
                   /* do nothing */
                 } else {
                   if( foo<0 || foo >= $SIZE(n) ) {
                     barf("PDLA::index1d: invalid/bad index %d at pos %d (valid range 0..%d)",
                      foo, i, $SIZE(n)-1);
                   }
                   $a(n=>foo) = $c(m=>i);
                 }
         }
        },
       );

my $index2d_init_good =
       'register PDLA_Indx fooa,foob;
        fooa = $inda();
        if( fooa<0 || fooa>=$SIZE(na) ) {
           barf("PDLA::index: invalid x-index %d (valid range 0..%d)",
                fooa,$SIZE(na)-1);
        }
        foob = $indb();
        if( foob<0 || foob>=$SIZE(nb) ) {
           barf("PDLA::index: invalid y-index %d (valid range 0..%d)",
                foob,$SIZE(nb)-1);
        }';
my $index2d_init_bad =
       'register PDLA_Indx fooa,foob;
        fooa = $inda();
        if( $ISBADVAR(fooa,inda) || fooa<0 || fooa>=$SIZE(na) ) {
           barf("PDLA::index: invalid index 1");
        }
        foob = $indb();
        if( $ISBADVAR(foob,indb) || foob<0 || foob>=$SIZE(nb) ) {
           barf("PDLA::index: invalid index 2");
        }';

pp_def(
       'index2d',
       HandleBad => 1,
       DefaultFlow => 1,
       Reversible => 1,
       Pars => 'a(na,nb); indx inda(); indx indb(); [oca] c();',
       Code =>
       $index2d_init_good . ' $c() = $a(na => fooa, nb => foob);',
       BadCode =>
       $index2d_init_bad . '$c() = $a(na => fooa, nb => foob);',
       BackCode =>
       $index2d_init_good . ' $a(na => fooa, nb => foob) = $c();',
       BadBackCode =>
       $index2d_init_bad . '$a(na => fooa, nb => foob) = $c();',
);


# indexND: CED 2-Aug-2002
pp_def(
        'rangeb',
        OtherPars => 'SV *index; SV *size; SV *boundary',
        HandleBad => 1,
        DefaultFlow => 1,
        Reversible => 1,
        P2Child => 1,
        NoPdlThread => 1,

#
# rdim: dimensionality of each range (0 dim of index PDLA)
#
# ntsize: number of nonzero size dimensions
# sizes:  array of range sizes, indexed (0..rdim-1).  A zero element means
#         that the dimension is omitted from the child dim list.
# corners: parent coordinates of each corner, running fastest over coord index.
#       (indexed 0 .. (nitems-1)*(rdim)+rdim-1)
# nitems: total number of list elements   (product of itdims)
# itdim:  number of index thread dimensions
# itdims: Size of each index thread dimension, indexed (0..itdim-1)
#
# bsize: Number of independently specified boundary conditions
# nsizes: Number of independently specified range dim sizes
# boundary: Array containing all the boundary condition specs
# indord: Order/size of the indexing dim (0th dim of $index)

        Comp => 'PDLA_Indx rdim;
                 PDLA_Indx nitems;
                 PDLA_Indx itdim;
                 PDLA_Indx ntsize;
                 PDLA_Indx bsize;
                 PDLA_Indx nsizes;
                 PDLA_Indx sizes[$COMP(rdim)];
                 PDLA_Indx itdims[$COMP(itdim)];
                 PDLA_Indx corners[$COMP(rdim) * $COMP(nitems)];
                 char boundary[$COMP(rdim)];
                 ',
        MakeComp => <<'EOD-MakeComp',
pdl *ind_pdl;
pdl *size_pdl;

/***
 * Check and condition the index piddle.  Some of this is apparently
 * done by XS -- but XS doesn't check for existing SVs that are undef.
 */
if ((index==NULL) || (index == &PL_sv_undef))
   { $CROAK("rangeb: index variable must be defined"); }

if(!(ind_pdl = PDLA->SvPDLAV(index))) /* assignment */
   { $CROAK("rangeb: unable to convert index variable to a PDLA"); }

PDLA->make_physdims(ind_pdl);

/* Generalized empties are ok, but not in the special 0 dim (the index vector) */
if(ind_pdl->dims[0] == 0)
    { $CROAK("rangeb: can't handle Empty indices -- call range instead"); }

/***
 * Ensure that the index is a PDLA_Indx.  If there's no loss of information,
 * just upgrade it -- otherwise, make a temporary copy.
 */
switch(ind_pdl->datatype) {
 default:                              /* Most types: */
   ind_pdl = PDLA->hard_copy(ind_pdl);  /*   copy and fall through */
 case PDLA_B: case PDLA_S: case PDLA_US: case PDLA_L: case PDLA_LL:
   PDLA->converttype(&ind_pdl,PDLA_IND,1); /* convert in place. */
   break;
 case PDLA_IND:
   PDLA->make_physical(ind_pdl);
   break;
}

/***
 * Figure sizes of the COMP arrrays and allocate them.
 */
{
  PDLA_Indx i,nitems;

  $COMP(rdim) = ind_pdl->ndims ? ind_pdl->dims[0] : 1;
  for(i=nitems=1; i < ind_pdl->ndims; i++)  /* Accumulate item list size */
    nitems *= ind_pdl->dims[i];
  $COMP(nitems) = nitems;
  $COMP(itdim) = ind_pdl->ndims ? ind_pdl->ndims - 1 : 0;
  $DOCOMPDIMS();
}

/***
 * Fill in the boundary condition array
 */
{
  char *bstr;
  STRLEN blen;
  bstr = SvPV(boundary,blen);

  if(blen == 0) {
    /* If no boundary is specified then every dim gets forbidden */
    int i;
    for (i=0;i<$COMP(rdim);i++)
      $COMP(boundary[i]) = 0;
  } else {
    int i;
    for(i=0;i<$COMP(rdim);i++) {
      switch(bstr[i < blen ? i : blen-1 ]) {
      case '0': case 'f': case 'F':               /* forbid */
        $COMP(boundary[i]) = 0;
        break;
      case '1': case 't': case 'T':               /* truncate */
        $COMP(boundary[i]) = 1;
        break;
      case '2': case 'e': case 'E':               /* extend */
        $COMP(boundary[i]) = 2;
        break;
      case '3': case 'p': case 'P':               /* periodic */
        $COMP(boundary[i]) = 3;
        break;
      case '4': case 'm': case 'M':               /* mirror */
        $COMP(boundary[i]) = 4;
        break;
      default:
        {
          /* No need to check if i < blen -- this will barf out the
           * first time it gets hit.  I didn't use $ CROAK 'coz that
           * macro doesn't let you pass in a string variable -- only a
           * constant.
           */
          barf("Error in rangeb: Unknown boundary condition '%c' in range",bstr[i]);
        }
        break;
      } // end of switch
    }
  }
}
/***
 * Store the sizes of the index-thread dims
 */
{
  PDLA_Indx i;
  PDLA_Indx nd = ind_pdl->ndims - 1;
  for(i=0; i < nd ; i++)
    $COMP(itdims[i]) = ind_pdl->dims[i+1];
}

/***
 * Check and condition the size piddle, and store sizes of the ranges
 */
{
  PDLA_Indx i,ntsize;

  if( (size == NULL) || (size == &PL_sv_undef) ) {
    // NO size was passed in - not normally executed even if you passed in no size to range(),
    // as range() generates a size array...
    for(i=0;i<$COMP(rdim);i++)
          $COMP(sizes[i]) = 0;

  } else {
    /* Normal case with sizes present in a PDLA */

    if(!(size_pdl = PDLA->SvPDLAV(size))) /* assignment */
      $CROAK("Unable to convert size to a PDLA in range");

    if(size_pdl->nvals == 0) {
      // no values in the size_pdl - Empty or Null.  Just copy 0s to all the range dims
      for(i=0;i<$COMP(rdim);i++)
        $COMP(sizes[i]) = 0;

    } else {

      // Convert size PDLA to PDLA_IND to support indices
      switch(size_pdl->datatype) {
      default:                              /* Most types: */
        size_pdl = PDLA->hard_copy(size_pdl);  /*   copy and fall through */
      case PDLA_B: case PDLA_S: case PDLA_US: case PDLA_L:  case PDLA_LL:
        PDLA->converttype(&size_pdl,PDLA_IND,1); /* convert in place. */
        break;
      case PDLA_IND:
        PDLA->make_physical(size_pdl);
        break;
      }

      $COMP(nsizes) = size_pdl->nvals; /* Store for later permissiveness check */

      /* Copy the sizes, or die if they're the wrong shape */
      if(size_pdl->nvals == 1) {
        for(i=0;i<$COMP(rdim);i++) {
          $COMP(sizes[i]) = *((PDLA_Indx *)(size_pdl->data));
        }

        /* Check for nonnegativity of sizes.  The rdim>0 mask ensures that */
        /* we don't barf on the Empty PDLA (as an index). */
        if( $COMP(rdim) > 0 && $COMP(sizes[0]) < 0 ) {
          $CROAK("  Negative range size is not allowed in range\n");
        }
      }
      else if( size_pdl->nvals <= $COMP(rdim) && size_pdl->ndims == 1) {
        for(i=0;i<$COMP(rdim);i++) {
          $COMP(sizes[i]) = (   (i < size_pdl->nvals) ?
                                ((PDLA_Indx *)(size_pdl->data))[i] :
                                0
                            );
          if($COMP(sizes[i]) < 0)
                $CROAK("  Negative range sizes are not allowed in range\n");
        }
      }
      else {
        $CROAK(" Size must match index's 0th dim in range\n");
      }

    } /* end of nonempty size-piddle code */
  } /* end of defined-size-piddle code */

  /* Insert the number of nontrivial sizes (these get output dimensions) */
  for(i=ntsize=0;i<$COMP(rdim);i++)
    if($COMP(sizes[i]))
      ntsize++;
  $COMP(ntsize) = ntsize;
}

/***
 * Stash coordinates of the corners
 */

{
  PDLA_Indx i,j,k,ioff;
  PDLA_Indx *cptr;
  PDLA_Indx *iter = (PDLA_Indx *)(PDLA->smalloc((STRLEN) (sizeof(PDLA_Indx) * ($COMP(itdim)))));

  /* initialize iterator to loop over index threads */
  cptr = iter;
  for(k=0;k<$COMP(itdim);k++)
    *(cptr++) = 0;

  cptr = $COMP(corners);
  do {
    /* accumulate offset into the index from the iterator */
    for(k=ioff=0;k<$COMP(itdim);k++)
      ioff += iter[k] * ind_pdl->dimincs[k+1];

    /* Loop over the 0th dim of index, copying coords. */
    /* This is the natural place to check for permissive ranging; too */
    /* bad we don't have access to the parent piddle here... */

    for(j=0;j<$COMP(rdim);j++)
        *(cptr++) = ((PDLA_Indx *)(ind_pdl->data))[ioff + ind_pdl->dimincs[0] * j];

    /* Increment the iterator -- the test increments, the body carries. */
    for(k=0; k<$COMP(itdim) && (++(iter[k]))>=($COMP(itdims)[k]) ;k++)
      iter[k] = 0;
  } while(k<$COMP(itdim));



}


$SETREVERSIBLE(1);

EOD-MakeComp

        RedoDims => <<'EOD-RedoDims' ,
{
  PDLA_Indx stdim = $PARENT(ndims) - $COMP(rdim);
  PDLA_Indx dim,inc;
  PDLA_Indx i,rdvalid;

    // Speed bump for ludicrous cases
    if( $COMP(rdim) > $PARENT(ndims)+5 && $COMP(nsizes) != $COMP(rdim)) {
      barf("Ludicrous number of extra dims in range index; leaving child null.\n    (%d implicit dims is > 5; index has %d dims; source has %d dim%s.)\n    This often means that your index PDLA is incorrect.  To avoid this message,\n    allocate dummy dims in the source or use %d dims in range's size field.\n",$COMP(rdim)-$PARENT(ndims),$COMP(rdim),$PARENT(ndims),($PARENT(ndims))>1?"s":"",$COMP(rdim));
    }

    if(stdim < 0)
      stdim = 0;

    /* Set dimensionality of child */
    $CHILD(ndims) = $COMP(itdim) + $COMP(ntsize) + stdim;
    $SETNDIMS($COMP(itdim)+$COMP(ntsize)+stdim);

    inc = 1;
    /* Copy size dimensions to child, crunching as we go. */
    dim = $COMP(itdim);
    for(i=rdvalid=0;i<$COMP(rdim);i++) {
      if($COMP(sizes[i])) {
        rdvalid++;
        $CHILD(dimincs[dim]) = inc;
        inc *= ($CHILD(dims[dim++]) = $COMP(sizes[i])); /* assignment */
      }
    }

    /* Copy index thread dimensions to child */
    for(dim=0; dim<$COMP(itdim); dim++) {
      $CHILD(dimincs[dim]) = inc;
      inc *= ($CHILD(dims[dim]) = $COMP(itdims[dim])); /* assignment */
    }

    /* Copy source thread dimensions to child */
    dim = $COMP(itdim) + rdvalid;
    for(i=0;i<stdim;i++) {
      $CHILD(dimincs[dim]) = inc;
      inc *= ($CHILD(dims[dim++]) = $PARENT(dims[i+$COMP(rdim)])); /* assignment */
    }

    /* Cover bizarre case where the source PDLA is empty - in that case, change */
    /* all non-barfing boundary conditions to truncation, since we have no data */
    /* to reflect, extend, or mirror. */
    if($PARENT(dims[0])==0) {
      for(dim=0; dim<$COMP(rdim); dim++) {
        if($COMP(boundary[dim]))
          $COMP(boundary[dim]) = 1; // force truncation
      }
    }


  $CHILD(datatype) = $PARENT(datatype);

  $SETDIMS();
}

EOD-RedoDims

        EquivCPOffsCode => <<'EOD-EquivCPOffsCode',
{
  PDLA_Indx *iter, *ip;  /* vector iterator */
  PDLA_Indx *sizes, *sp; /* size vector including stdims */
  PDLA_Indx *coords;     /* current coordinates */

  PDLA_Indx k;           /* index */
  PDLA_Indx item;        /* index thread iterator */
  PDLA_Indx pdim = $PARENT_P(ndims);
  PDLA_Indx rdim = $COMP(rdim);
  PDLA_Indx prdim = (rdim < pdim) ? rdim : pdim;
  PDLA_Indx stdim = pdim - prdim;

  /* Allocate iterator and larger size vector -- do it all in one foop
   * to avoid extra calls to smalloc.
   */
    if(!(iter = (PDLA_Indx *)(PDLA->smalloc((STRLEN) (sizeof(PDLA_Indx) * ($PARENT_P(ndims) * 2 + rdim)))))) {
    barf("couldn't get memory for range iterator");
  }
  sizes  = iter + $PARENT_P(ndims);
  coords = sizes + $PARENT_P(ndims);

  /* Figure out size vector */
  for(ip = $COMP(sizes), sp = sizes, k=0; k<rdim; k++)
     *(sp++) = *(ip++);
  for(; k < $PARENT_P(ndims); k++)
     *(sp++) = $PARENT_P(dims[k]);


  /* Loop over all the ranges in the index list */
  for(item=0; item<$COMP(nitems); item++) {

    /* initialize in-range iterator to loop within each range */
    for(ip = iter, k=0; k<$PARENT_P(ndims); k++)
      *(ip++) = 0;

    do {
      PDLA_Indx poff = 0;
      PDLA_Indx coff;
      PDLA_Indx k2;
      char trunc = 0;       /* Flag used to skip truncation case */

      /* Collect and boundary-check the current N-D coords */
      for(k=0; k < prdim; k++){

        PDLA_Indx ck = iter[k] + $COMP(corners[ item * rdim + k  ]) ;

        /* normal case */
          if(ck < 0 || ck >= $PARENT_P(dims[k])) {
            switch($COMP(boundary[k])) {
            case 0: /* no boundary breakage allowed */
	      {
		char barfstr[1024];
		sprintf(barfstr,"index out-of-bounds in range (index vector #%ld)",item);
		barf(barfstr);
	      }
              break;
            case 1: /* truncation */
              trunc = 1;
              break;
            case 2: /* extension -- crop */
              ck = (ck >= $PARENT_P(dims[k])) ? $PARENT_P(dims[k])-1 : 0;
              break;
            case 3: /* periodic -- mod it */
              ck %= $PARENT_P(dims[k]);
              if(ck < 0)   /* Fix mod breakage in C */
                ck += $PARENT_P(dims[k]);
              break;
            case 4: /* mirror -- reflect off the edges */
              ck += $PARENT_P(dims[k]);
              ck %= ($PARENT_P(dims[k]) * 2);
              if(ck < 0) /* Fix mod breakage in C */
                ck += $PARENT_P(dims[k])*2;
              ck -= $PARENT_P(dims[k]);
              if(ck < 0) {
                ck *= -1;
                ck -= 1;
              }
              break;
            default:
              barf("Unknown boundary condition in range -- bug alert!");
              break;
            }
          }

        coords[k] = ck;

      }

      /* Check extra dimensions -- pick up where k left off... */
      for( ; k < rdim ; k++) {
        /* Check for indexing off the end of the dimension list */

        PDLA_Indx ck = iter[k] + $COMP(corners[ item * rdim + k  ]) ;

        switch($COMP(boundary[k])) {
            case 0: /* No boundary breakage allowed -- nonzero corners cause barfage */
              if(ck != 0)
                 barf("Too many dims in range index (and you've forbidden boundary violations)");
              break;
            case 1: /* truncation - just truncate if the corner is nonzero */
              trunc |= (ck != 0);
              break;
            case 2: /* extension -- ignore the corner (same as 3) */
            case 3: /* periodic  -- ignore the corner */
            case 4: /* mirror -- ignore the corner */
              ck = 0;
              break;
            default:
              barf("Unknown boudnary condition in range -- bug alert!");
              /* Note clever misspelling of boundary to distinguish from other case */
              break;
          }
      }

      /* Find offsets into the child and parent arrays, from the N-D coords */
      /* Note we only loop over real source dims (prdim) to accumulate -- */
      /* because the offset is trivial and/or we're truncating for virtual */
      /* dims caused by permissive ranging. */
      coff = $CHILD_P(dimincs[0]) * item;
      for(k2 = $COMP(itdim), poff = k = 0;
          k < prdim;
          k++) {
        poff += coords[k]*$PARENT_P(dimincs[k]);
        if($COMP(sizes[k]))
          coff += iter[k] * $CHILD_P(dimincs[k2++]);
      }

      /* Loop the copy over all the source thread dims (above rdim). */
      do {
        PDLA_Indx poff1 = poff;
        PDLA_Indx coff1 = coff;

        /* Accumulate the offset due to source threading */
        for(k2 = $COMP(itdim) + $COMP(ntsize), k = rdim;
            k < pdim;
            k++) {
          poff1 += iter[k] * $PARENT_P(dimincs[k]);
          coff1 += iter[k] * $CHILD_P(dimincs[k2++]);
        }

        /* Finally -- make the copy
         * EQUIVCPTRUNC works like EQUIVCPOFFS but with checking for
         * out-of-bounds conditions.
         */
        $EQUIVCPTRUNC(coff1,poff1,trunc);

        /* Increment the source thread iterator */
        for( k=$COMP(rdim);
             k < $PARENT_P(ndims) && (++(iter[k]) >= $PARENT_P(dims[k]));
             k++)
          iter[k] = 0;
      } while(k < $PARENT_P(ndims)); /* end of source-thread iteration */

      /* Increment the in-range iterator */
      for(k = 0;
          k < $COMP(rdim) && (++(iter[k]) >= $COMP(sizes[k]));
          k++)
        iter[k] = 0;
    } while(k < $COMP(rdim)); /* end of main iteration */
  } /* end of item do loop */

}

EOD-EquivCPOffsCode

);


pp_def(
        'rld',
        Pars=>'indx a(n); b(n); [o]c(m);',
        PMCode=>'sub PDLA::rld{}', # to make the _rld_int
        Code=>'
          PDLA_Indx i,j=0,an;
          $GENERIC(b) bv;
          loop (n) %{
            an = $a();
            bv = $b();
            for (i=0;i<an;i++) {
              $c(m=>j) = bv;
              j++;
            }
          %}',
);

pp_def(
        'rle',
        Pars=>'c(n); indx [o]a(m); [o]b(m);',
#this RedoDimsCode sets $SIZE(m)==$SIZE(n), but the slice in the PMCode below makes m<=n.
        RedoDimsCode=>'$SIZE(m)=$PDLA(c)->dims[0];',
        PMCode=>'sub PDLA::rle{}', # to make the _rle_int
        Code=>'
          PDLA_Indx j=0,sn=$SIZE(n);
          $GENERIC(c) cv, clv;
          clv = $c(n=>0);
          $b(m=>0) = clv;
          $a(m=>0) = 0;
          loop (n) %{
            cv = $c();
            if (cv == clv) {
              $a(m=>j)++;
            } else {
              j++;
              $b(m=>j) = clv = cv;
              $a(m=>j) = 1;
            }
          %}
          for (j++;j<$SIZE(m);j++) {
            $a(m=>j) = 0;
            $b(m=>j) = 0;
          }
        ',
);

# this one can convert vaffine piddles without(!) physicalising them
# maybe it can replace 'converttypei' in the future?
#
# XXX do not know whether the HandleBad stuff will work here
#
pp_def('flowconvert',
       HandleBad => 1,
       DefaultFlow => 1,
       Reversible => 1,
       Pars => 'PARENT(); [oca]CHILD()',
       OtherPars => 'int totype;',
       Reversible => 1,
       # Forced types
       FTypes => {CHILD => '$COMP(totype)'},
       Code =>
       '$CHILD() = $PARENT();',
       BadCode =>
       'if ( $ISBAD(PARENT()) ) {
           $SETBAD(CHILD());
        } else {
           $CHILD() = $PARENT();
        }',
       BackCode => '$PARENT() = $CHILD();',
       BadBackCode =>
       'if ( $ISBAD(CHILD()) ) {
           $SETBAD(PARENT());
        } else {
           $PARENT() = $CHILD();
        }',
       Doc => 'internal',
);


pp_def(
        'converttypei',
        HandleBad => 1,
        DefaultFlow => 1,
        GlobalNew => 'converttypei_new',
        OtherPars => 'int totype;',
        P2Child => 1,
        NoPdlThread => 1,
        Identity => 1,
        Reversible => 1,
# Forced types
        FTypes => {CHILD => '$COMP(totype)'},
        Doc => 'internal',
);



# the perl wrapper clump is now defined in Core.pm
# this is just the low level interface
pp_def(
        '_clump_int',
        DefaultFlow => 1,
        OtherPars => 'int n',
        P2Child => 1,
	NoPdlThread=>1,
        Priv => 'int nnew; int nrem;',
        RedoDims => 'int i; PDLA_Indx d1;

	         /* truncate overly long clumps to just clump existing dimensions */
		 if($COMP(n) > $PARENT(ndims))
                        $COMP(n) = $PARENT(ndims);

		 if($COMP(n) < -1)
                        $COMP(n) = $PARENT(ndims) + $COMP(n) + 1;

                 $PRIV(nrem) = ($COMP(n)==-1 ? $PARENT(threadids[0]) : $COMP(n));
                 $PRIV(nnew) = $PARENT(ndims) - $PRIV(nrem) + 1;
                 $SETNDIMS($PRIV(nnew));
                 d1=1;
                 for(i=0; i<$PRIV(nrem); i++) {
                        d1 *= $PARENT(dims[i]);
                 }
                 $CHILD(dims[0]) = d1;
                 for(; i<$PARENT(ndims); i++) {
                        $CHILD(dims[i-$PRIV(nrem)+1]) = $PARENT(dims[i]);
                 }
                 $SETDIMS();
                 $SETDELTATHREADIDS(1-$PRIV(nrem));
                 ',
        EquivCPOffsCode => '
                PDLA_Indx i;
                for(i=0; i<$CHILD_P(nvals); i++) {
                        $EQUIVCPOFFS(i,i);
                }
                ',
        Reversible => 1,
        Doc => 'internal',
);

pp_def(
        'xchg',
        OtherPars => 'int n1; int n2;',
        DefaultFlow => 1,
        Reversible => 1,
        P2Child => 1,
        NoPdlThread => 1,
        XCHGOnly => 1,
        EquivDimCheck => 'if ($COMP(n1) <0)
                                $COMP(n1) += $PARENT(threadids[0]);
                          if ($COMP(n2) <0)
                                $COMP(n2) += $PARENT(threadids[0]);
                          if ($COMP(n1) <0 ||$COMP(n2) <0 ||
                             $COMP(n1) >= $PARENT(threadids[0]) ||
                             $COMP(n2) >= $PARENT(threadids[0]))
                barf("One of dims %d, %d out of range: should be 0<=dim<%d",
                        $COMP(n1),$COMP(n2),$PARENT(threadids[0]));',
        EquivPDimExpr => '(($CDIM == $COMP(n1)) ? $COMP(n2) : ($CDIM == $COMP(n2)) ? $COMP(n1) : $CDIM)',
        EquivCDimExpr => '(($PDIM == $COMP(n1)) ? $COMP(n2) : ($PDIM == $COMP(n2)) ? $COMP(n1) : $PDIM)',
);

pp_def(
        'mv',
        OtherPars => 'int n1; int n2;',
        DefaultFlow => 1,
        Reversible => 1,
        P2Child => 1,
        NoPdlThread => 1,
        XCHGOnly => 1,
        EquivDimCheck => 'if ($COMP(n1) <0)
                                $COMP(n1) += $PARENT(threadids[0]);
                          if ($COMP(n2) <0)
                                $COMP(n2) += $PARENT(threadids[0]);
                          if ($COMP(n1) <0 ||$COMP(n2) <0 ||
                             $COMP(n1) >= $PARENT(threadids[0]) ||
                             $COMP(n2) >= $PARENT(threadids[0]))
                barf("One of dims %d, %d out of range: should be 0<=dim<%d",
                        $COMP(n1),$COMP(n2),$PARENT(threadids[0]));',
        EquivPDimExpr => '(($COMP(n1) < $COMP(n2)) ?
        (($CDIM < $COMP(n1) || $CDIM > $COMP(n2)) ?
                $CDIM : (($CDIM == $COMP(n2)) ? $COMP(n1) : $CDIM+1))
        : (($COMP(n2) < $COMP(n1)) ?
                (($CDIM > $COMP(n1) || $CDIM < $COMP(n2)) ?
                        $CDIM : (($CDIM == $COMP(n2)) ? $COMP(n1) : $CDIM-1))
                : $CDIM))',
        EquivCDimExpr => '(($COMP(n2) < $COMP(n1)) ?
        (($PDIM < $COMP(n2) || $PDIM > $COMP(n1)) ?
                $PDIM : (($PDIM == $COMP(n1)) ? $COMP(n2) : $PDIM+1))
        : (($COMP(n1) < $COMP(n2)) ?
                (($PDIM > $COMP(n2) || $PDIM < $COMP(n1)) ?
                        $PDIM : (($PDIM == $COMP(n1)) ? $COMP(n2) : $PDIM-1))
                : $PDIM))',
);

pp_addhdr << 'EOH';
#define sign(x) ( (x) < 0 ? -1 : 1)
EOH

pp_def(
        'oslice',
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        OtherPars => 'char* str',
        Comp => 'int nnew; int nthintact; int intactnew; int ndum;
                 int corresp[$COMP(intactnew)]; PDLA_Indx start[$COMP(intactnew)];
                 PDLA_Indx inc[$COMP(intactnew)]; PDLA_Indx end[$COMP(intactnew)];
                 int nolddims;
                 int whichold[$COMP(nolddims)]; int oldind[$COMP(nolddims)];
                 ',
        AffinePriv => 1,
        MakeComp => q~
                int i;
                int nthnew; int nthold; int nthreal;
                PDLA_Indx dumsize;
                char *s; char *ns;
                int nums[3]; int nthnum;
                $COMP(nnew)=0;
                $COMP(ndum)=0;
                $COMP(nolddims) = 0;
                if(str[0] == '(')
                        $COMP(nolddims)++;
                else if (str[0] == '*')
                        $COMP(ndum)++;
                else if (str[0] != '\0') /* handle empty string */
                        $COMP(nnew)++;
                for(i=0; str[i]; i++)
                        if(str[i] == ',') {
                                if(str[i+1] == '(')
                                        $COMP(nolddims)++;
                                else if(str[i+1] == '*')
                                        $COMP(ndum)++;
                                else
                                        $COMP(nnew)++;
                        }
                $COMP(nthintact) = $COMP(nolddims) + $COMP(nnew);
                $COMP(intactnew) = $COMP(nnew)+$COMP(ndum);
                $DOCOMPDIMS();
                nthnew=0; nthold=0; i=0; nthreal=0;
                s=str-1;
                do {
                        s++;
                        if(isdigit(*s) || *s == '-') {
                                nthnew++; nthreal++;
                                $COMP(inc[nthnew-1]) = 1;
                                $COMP(corresp[nthnew-1]) = nthreal-1;
                                $COMP(start[nthnew-1]) = strtoll(s,&s,10);
                                if(*s != ':') {
                                        $COMP(end[nthnew-1]) =
                                                $COMP(start[nthnew-1]);
                                        goto outlab;
                                }
                                s++;
                                if(!isdigit(*s) && !(*s == '-')) {
                                        barf("Invalid slice str ind1 '%s': '%s'",str,s);
                                }
                                $COMP(end[nthnew-1]) = strtoll(s,&s,10);
                                if(*s != ':') {goto outlab;}
                                s++;
                                if(!isdigit(*s) && !(*s == '-')) {
                                        barf("Invalid slice str ind2 '%s': '%s'",str,s);
                                }
                                $COMP(inc[nthnew-1]) = strtoll(s,&s,10);
                        } else switch(*s) {
                        case ':':
                                s++;
                                /* FALLTHRU */
                        case ',': case '\0':  /* In these cases, no inc s */
                                if ($COMP(intactnew) > 0) {
                                  $COMP(start[nthnew]) = 0;
                                  $COMP(end[nthnew]) = -1;
                                  $COMP(inc[nthnew]) = 1;
                                  $COMP(corresp[nthnew]) = nthreal;
                                  nthnew++; nthreal++;
                                }
                                break;
                        case '(':
                                s++;
                                $COMP(oldind[nthold]) = strtoll(s,&s,10);
                                $COMP(whichold[nthold]) = nthreal;
                                nthold++; nthreal++;
                                if(*s != ')') {
                                        barf("Sliceoblit must end with ')': '%s': '%s'",str,s);
                                }
                                s++;
                                break;
                        case '*':
                                s++;
                                if(isdigit(*s)) {
                                        dumsize = strtoll(s,&s,10);
                                } else {dumsize = 1;}
                                $COMP(corresp[nthnew]) = -1;
                                $COMP(start[nthnew]) = 0;
                                $COMP(end[nthnew]) = dumsize-1;
                                $COMP(inc[nthnew]) = 1;
                                nthnew++;
                                break;
                        }
                   outlab:
                        if(*s != ',' && *s != '\0') {
                                barf("Invalid slice str '%s': '%s'",str,s);
                        }
                } while(*s);
                $SETREVERSIBLE(1); /* XXX Only if incs>0, no dummies */
        ~,
        RedoDims => '
                int i; PDLA_Indx start; PDLA_Indx end; PDLA_Indx inc;
                if ($COMP(nthintact) > $PARENT(ndims)) {

        /* Slice has more dims than parent.  Check that the extra dims are
         * all zero, and if they are then give back What You Probably Wanted,
         * which is a slice with dummy dimensions of order 1 in place of each excessive
         * dimension.  (Note that there are two ways to indicate a zero index: "0" and "-<w>",
         * where <w> happens to be the size of that dim in the original
         * piddle.  The latter case still causes an error.  That is a feature.)
         *    --CED 15-March-2002
         */
                        int ii,parentdim,ok;
                        int n_xtra_dims=0, n_xtra_olddims=0;

                           /* Check index for each extra dim in the ordinary affine list */

                        for(ok=1, ii = 0; ok && ii < $COMP(intactnew) ; ii++) {
                                parentdim = $COMP(corresp[ii]);
/*                              fprintf(stderr,"ii=%d,parent=%d, ndum=%d, nnew=%d...",ii,parentdim,$COMP(ndum),$COMP(nnew));                            */
                                if(parentdim >= $PARENT(ndims)) {

                                        ok = ( ( $COMP(start[ii]) == 0 ) &&
                                                ( $COMP(end[ii]) == 0 || $COMP(end[ii])== -1 )
                                        );
                                        if(ok) {
                                                /* Change this into a dummy dimension, rank 1 */
                                                $COMP(corresp[ii]) = -1;
                                                $COMP(start[ii])   = 0;
                                                $COMP(end[ii])     = 0;
                                                $COMP(inc[ii])     = 1;
                                                $COMP(ndum)++;      /* One more dummy dimension... */
                                                $COMP(nnew)--;      /* ... one less real dimension */
                                                $COMP(nthintact)--; /* ... one less intact dim */
/*                                              fprintf(stderr,"ok, ndum=%d, nnew=%d\n",$COMP(ndum), $COMP(nnew));*/
                                        }
/*                              fflush(stderr);*/
                                }
                        }

                          /* Check index for each indexed parent dimension */
                        for(ii=0; ok && ii < $COMP(nolddims); ii++) {
                                if($COMP(whichold[ii]) >= $PARENT(ndims)) {
                                        ok = ( $COMP(whichold[ii]) < $PARENT(ndims) ) ||
                                                ( $COMP(oldind[ii]) == 0 ) ||
                                                ( $COMP(oldind[ii]) == -1) ;
                                        if(ok) {
                                          int ij;
                                          /* crunch indexed dimensions -- slow but sure */
                                          $COMP(nolddims)--;
                                          for(ij=ii; ij<$COMP(nolddims); ij++) {
                                                $COMP(oldind[ij]) = $COMP(oldind[ij+1]);
                                                $COMP(whichold[ij]) = $COMP(whichold[ij+1]);
                                          }
                                          $COMP(nthintact)--;
                                        }
                                }
                        }
/*      fprintf(stderr,"ok=%d\n",ok);fflush(stderr);*/
                        if(ok) {
                           /* Valid slice: all extra dims are zero. Adjust indices accordingly. */
/*                        $COMP(intactnew) -= $COMP(nthintact) - $PARENT(ndims); */
/*                        $COMP(nthintact) = $PARENT(ndims);*/
                        } else {

                           /* Invalid slice: nonzero extra dimension.  Clean up and die.  */

                         $SETNDIMS(0); /* dirty fix */
                         $PRIV(offs) = 0;
                         $SETDIMS();
                         $CROAK("Too many dims in slice");
                        }
                }
                $SETNDIMS($PARENT(ndims)-$COMP(nthintact)+$COMP(intactnew));
                $DOPRIVDIMS();
                $PRIV(offs) = 0;
                for(i=0; i<$COMP(intactnew); i++) {
                        int parentdim = $COMP(corresp[i]);
                        start = $COMP(start[i]); end = $COMP(end[i]);
                        inc = $COMP(inc[i]);
                        if(parentdim!=-1) {
                                if(-start > $PARENT(dims[parentdim]) ||
                                   -end > $PARENT(dims[parentdim])) {
                                        /* set a state flag to re-trip the RedoDims code later, in
                                         * case this barf is caught in an eval. This slice will
                                         * always croak, so it may be smarter to find a way to
                                         * replace this whole piddle with a "barf" piddle, but this
                                         * will work for now. */
                                        PDLA->changed($CHILD_PTR(), PDLA_PARENTDIMSCHANGED, 0);
                                        barf("Negative slice cannot start or end above limit");
                                }
                                if(start < 0)
                                        start = $PARENT(dims[parentdim]) + start;
                                if(end < 0)
                                        end = $PARENT(dims[parentdim]) + end;
                                if(start >= $PARENT(dims[parentdim]) ||
                                   end >= $PARENT(dims[parentdim])) {
                                        /* set a state flag to re-trip the RedoDims code later, in
                                         * case this barf is caught in an eval. This slice will
                                         * always croak, so it may be smarter to find a way to
                                         * replace this whole piddle with a "barf" piddle, but this
                                         * will work for now. */
                                        PDLA->changed($CHILD_PTR(), PDLA_PARENTDIMSCHANGED, 0);
                                        barf("Slice cannot start or end above limit");
                                }
                                if(sign(end-start)*sign(inc) < 0)
                                        inc = -inc;
                                $PRIV(incs[i]) = $PARENT(dimincs[parentdim]) * inc;
                                $PRIV(offs) += start * $PARENT(dimincs[parentdim]);
                        } else {
                                $PRIV(incs[i]) = 0;
                        }
                        $CHILD(dims[i]) = ((PDLA_Indx)((end-start)/inc))+1;
                        if ($CHILD(dims[i]) <= 0)
                           barf("slice internal error: computed slice dimension must be positive");
                }
                for(i=$COMP(nthintact); i<$PARENT(ndims); i++) {
                        int cdim = i - $COMP(nthintact) + $COMP(intactnew);
                        $PRIV(incs[cdim]) = $PARENT(dimincs[i]);
                        $CHILD(dims[cdim]) = $PARENT(dims[i]);
                }
                for(i=0; i<$COMP(nolddims); i++) {
                        int oi = $COMP(oldind[i]);
                        int wo = $COMP(whichold[i]);
                        if(oi < 0)
                                oi += $PARENT(dims[wo]);
                        if( oi >= $PARENT(dims[wo]) )
                                $CROAK("Cannot obliterate dimension after end");
                        $PRIV(offs) += $PARENT(dimincs[wo])
                                        * oi;
                }
        /*
                for(i=0; i<$CHILD(ndims)-$PRIV(nnew); i++) {
                        $CHILD(dims[i+$COMP(intactnew)]) =
                                $PARENT(dims[i+$COMP(nthintact)]);
                        $PRIV(incs[i+$COMP(intactnew)]) =
                                $PARENT(dimincs[i+$COMP(nthintact)]);
                }
        */
                $SETDIMS();
        ',
);



pp_addhdr(<<END
static int cmp_pdll(const void *a_,const void *b_) {
        int *a = (int *)a_; int *b=(int *)b_;
        if(*a>*b) return 1;
        else if(*a==*b) return 0;
        else return -1;
}
END
);


pp_def( 'affine',
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        Reversible => 1,
        AffinePriv => 1,
        GlobalNew => 'affine_new',
        OtherPars => 'PDLA_Indx offspar; SV *dimlist; SV *inclist;',
        Comp => 'int nd; PDLA_Indx offset; PDLA_Indx sdims[$COMP(nd)];
                PDLA_Indx sincs[$COMP(nd)];',
        MakeComp => '
                int i,n2;
                PDLA_Indx *tmpi;
                PDLA_Indx *tmpd = PDLA->packdims(dimlist,&($COMP(nd)));
                tmpi = PDLA->packdims(inclist,&n2);
                if ($COMP(nd) < 0) {
                      $CROAK("Affine: can not have negative no of dims");
                }
                if ($COMP(nd) != n2)
                      $CROAK("Affine: number of incs does not match dims");
                $DOCOMPDIMS();
                $COMP(offset) = offspar;
                for (i=0; i<$COMP(nd); i++) {
                        $COMP(sdims)[i] = tmpd[i];
                        $COMP(sincs)[i] = tmpi[i];
                }
                ',
        RedoDims => '
                PDLA_Indx i;
                $SETNDIMS($COMP(nd));
                $DOPRIVDIMS();
                $PRIV(offs) = $COMP(offset);
                for (i=0;i<$CHILD(ndims);i++) {
                        $PRIV(incs)[i] = $COMP(sincs)[i];
                        $CHILD(dims)[i] = $COMP(sdims)[i];
                }
                $SETDIMS();
                ',
        Doc => undef,
);

pp_def(
        'diagonalI',
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        Reversible => 1,
        AffinePriv => 1,
        OtherPars => 'SV *list',
        Comp => 'int nwhichdims; int whichdims[$COMP(nwhichdims)];',
        MakeComp => '
                int i,j;
                PDLA_Indx *tmp= PDLA->packdims(list,&($COMP(nwhichdims)));
                if($COMP(nwhichdims) < 1) {
                        $CROAK("Diagonal: must have at least 1 dimension");
                }
                $DOCOMPDIMS();
                for(i=0; i<$COMP(nwhichdims); i++)
                        $COMP(whichdims)[i] = tmp[i];
                qsort($COMP(whichdims), $COMP(nwhichdims), sizeof(int),
                        cmp_pdll);
        ',
        RedoDims => '
                int nthp,nthc,nthd; int cd = $COMP(whichdims[0]);
                $SETNDIMS($PARENT(ndims)-$COMP(nwhichdims)+1);
                $DOPRIVDIMS();
                $PRIV(offs) = 0;
                if ($COMP(whichdims)[$COMP(nwhichdims)-1] >= $PARENT(ndims) ||
                        $COMP(whichdims)[0] < 0)
                        $CROAK("Diagonal: dim out of range");
                nthd=0; nthc=0;
                for(nthp=0; nthp<$PARENT(ndims); nthp++)
                        if (nthd < $COMP(nwhichdims) &&
                            nthp == $COMP(whichdims)[nthd]) {
                                if (!nthd) {
                                        $CHILD(dims)[cd] = $PARENT(dims)[cd];
                                        nthc++;
                                        $PRIV(incs)[cd] = 0;
                                }
                                if (nthd && $COMP(whichdims)[nthd] ==
                                    $COMP(whichdims)[nthd-1])
                                       $CROAK("Diagonal: dims must be unique");
                                nthd++; /* advance pointer into whichdims */
                                if($CHILD(dims)[cd] !=
                                    $PARENT(dims)[nthp]) {
                                        $CROAK("Different dims %d and %d",
                                                $CHILD(dims)[cd],
                                                $PARENT(dims)[nthp]);
                                }
                                $PRIV(incs)[cd] += $PARENT(dimincs)[nthp];
                        } else {
                                $PRIV(incs)[nthc] = $PARENT(dimincs)[nthp];
                                $CHILD(dims)[nthc] = $PARENT(dims)[nthp];
                                nthc++;
                        }
                $SETDIMS();
        ',
);

pp_def(
        'lags',
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        Reversible => 1, # XXX Not really
        AffinePriv => 1,
        OtherPars => 'int nthdim; int step; int n;',
        RedoDims => '
                int i;
                if ($PRIV(nthdim) < 0)  /* the usual conventions */
                   $PRIV(nthdim) = $PARENT(ndims) + $PRIV(nthdim);
                if ($PRIV(nthdim) < 0 || $PRIV(nthdim) >= $PARENT(ndims))
                   $CROAK("lags: dim out of range");
                if ($COMP(n) < 1)
                   $CROAK("lags: number of lags must be positive");
                if ($COMP(step) < 1)
                   $CROAK("lags: step must be positive");
                $PRIV(offs) = 0;
                $SETNDIMS($PARENT(ndims)+1);
                $DOPRIVDIMS();
                for(i=0; i<$PRIV(nthdim); i++) {
                        $CHILD(dims)[i] = $PARENT(dims)[i];
                        $PRIV(incs)[i] = $PARENT(dimincs)[i];
                }
                $CHILD(dims)[i] = $PARENT(dims)[i] - $COMP(step) * ($COMP(n)-1);
                if ($CHILD(dims)[i] < 1)
                  $CROAK("lags: product of step size and "
                         "number of lags too large");
                $CHILD(dims)[i+1] = $COMP(n);
                $PRIV(incs)[i] = ($PARENT(dimincs)[i]);
                $PRIV(incs)[i+1] = - $PARENT(dimincs)[i] * $COMP(step);
                $PRIV(offs) += ($CHILD(dims)[i+1] - 1) * (-$PRIV(incs)[i+1]);
                i++;
                for(; i<$PARENT(ndims); i++) {
                        $CHILD(dims)[i+1] = $PARENT(dims)[i];
                        $PRIV(incs)[i+1] = $PARENT(dimincs)[i];
                }
                $SETDIMS();
        '
);

pp_def(
        'splitdim',
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        Reversible => 1, # XXX Not really
        OtherPars => 'int nthdim; int nsp;',
        AffinePriv => 1,
        RedoDims => '
                int i = $COMP(nthdim);
                int nsp = $COMP(nsp);
                if(nsp == 0) {die("Splitdim: Cannot split to 0\n");}
                if(i <0 || i >= $PARENT(ndims)) {
                        die("Splitdim: nthdim (%d) must not be negative or greater or equal to number of dims (%d)\n",
                                i, $PARENT(ndims));
                }
                if(nsp > $PARENT(dims[i])) {
                        die("Splitdim: nsp (%d) cannot be greater than dim (%"IND_FLAG")\n",
                                nsp, $PARENT(dims[i]));
                }
                $PRIV(offs) = 0;
                $SETNDIMS($PARENT(ndims)+1);
                $DOPRIVDIMS();
                for(i=0; i<$PRIV(nthdim); i++) {
                        $CHILD(dims)[i] = $PARENT(dims)[i];
                        $PRIV(incs)[i] = $PARENT(dimincs)[i];
                }
                $CHILD(dims)[i] = $COMP(nsp);
                $CHILD(dims)[i+1] = $PARENT(dims)[i] / $COMP(nsp);
                $PRIV(incs)[i] = $PARENT(dimincs)[i];
                $PRIV(incs)[i+1] = $PARENT(dimincs)[i] * $COMP(nsp);
                i++;
                for(; i<$PARENT(ndims); i++) {
                        $CHILD(dims)[i+1] = $PARENT(dims)[i];
                        $PRIV(incs)[i+1] = $PARENT(dimincs)[i];
                }
                $SETDIMS();
        ',
);

pp_def('rotate',
        Pars=>'x(n); indx shift(); [oca]y(n)',
        DefaultFlow => 1,
        Reversible => 1,
        Code=>'
        PDLA_Indx i,j;
        PDLA_Indx n_size = $SIZE(n);
        if (n_size == 0)
          barf("can not shift zero size piddle (n_size is zero)");
        j = ($shift()) % n_size;
        if (j < 0)
                j += n_size;
        for(i=0; i<n_size; i++,j++) {
            if (j == n_size)
               j = 0;
            $y(n=>j) = $x(n=>i);
        }',
        BackCode=>'
        PDLA_Indx i,j;
        PDLA_Indx n_size = $SIZE(n);
        j = ($shift()) % n_size;
        if (j < 0)
                j += n_size;
        for(i=0; i<n_size; i++,j++) {
            if (j == n_size)
               j = 0;
            $x(n=>i) = $y(n=>j);
        }
        '
);

# This is a bit tricky. Hope I haven't missed any cases.

pp_def(
        'threadI',
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        Reversible => 1,
        AffinePriv => 1,
        CallCopy => 0,  # Don't CallCopy for subclassed objects because PDLA::Copy calls ThreadI
                        #  (Wouldn't cause recursive loop otherwise)
        OtherPars => 'int id; SV *list',
        Comp => 'int id; int nwhichdims; int whichdims[$COMP(nwhichdims)];
                        int nrealwhichdims; ',
        MakeComp => '
                int i,j;
                PDLA_Indx *tmp= PDLA->packdims(list,&($COMP(nwhichdims)));
                $DOCOMPDIMS();
                for(i=0; i<$COMP(nwhichdims); i++)
                        $COMP(whichdims)[i] = tmp[i];
                $COMP(nrealwhichdims) = 0;
                for(i=0; i<$COMP(nwhichdims); i++) {
                        for(j=i+1; j<$COMP(nwhichdims); j++)
                                if($COMP(whichdims[i]) == $COMP(whichdims[j]) &&
                                   $COMP(whichdims[i]) != -1) {
                                $CROAK("Thread: duplicate arg %d %d %d",
                                        i,j,$COMP(whichdims[i]));
                        }
                        if($COMP(whichdims)[i] != -1) {
                                $COMP(nrealwhichdims) ++;
                        }
                }
                $COMP(id) = id;
                ',
        RedoDims => '
                int nthc,i,j,flag;
                $SETNDIMS($PARENT(ndims));
                $DOPRIVDIMS();
                $PRIV(offs) = 0;
                nthc=0;
                for(i=0; i<$PARENT(ndims); i++) {
                        flag=0;
                        if($PARENT(nthreadids) > $COMP(id) && $COMP(id) >= 0 &&
                           i == $PARENT(threadids[$COMP(id)])) {
                           nthc += $COMP(nwhichdims);
                        }
                        for(j=0; j<$COMP(nwhichdims); j++) {
                                if($COMP(whichdims[j] == i)) {flag=1; break;}
                        }
                        if(flag) {
                                continue;
                        }
                        $CHILD(dims[nthc]) = $PARENT(dims[i]);
                        $PRIV(incs[nthc]) = $PARENT(dimincs[i]);
                        nthc++;
                }
                for(i=0; i<$COMP(nwhichdims); i++) {
                        int cdim,pdim;
                        cdim = i +
                         ($PARENT(nthreadids) > $COMP(id) && $COMP(id) >= 0?
                          $PARENT(threadids[$COMP(id)]) : $PARENT(ndims))
                          - $COMP(nrealwhichdims);
                        pdim = $COMP(whichdims[i]);
                        if(pdim == -1) {
                                $CHILD(dims[cdim]) = 1;
                                $PRIV(incs[cdim]) = 0;
                        } else {
                                $CHILD(dims[cdim]) = $PARENT(dims[pdim]);
                                $PRIV(incs[cdim]) = $PARENT(dimincs[pdim]);
                        }
                }
                $SETDIMS();
                PDLA->reallocthreadids($CHILD_PTR(),
                        ($PARENT(nthreadids)<=$COMP(id) ?
                                $COMP(id)+1 : $PARENT(nthreadids)));
                for(i=0; i<$CHILD(nthreadids); i++) {
                        $CHILD(threadids[i]) =
                         ($PARENT(nthreadids) > i ?
                          $PARENT(threadids[i]) : $PARENT(ndims)) +
                         (i <= $COMP(id) ? - $COMP(nrealwhichdims) :
                          $COMP(nwhichdims) - $COMP(nrealwhichdims));
                }
                $CHILD(threadids[$CHILD(nthreadids)]) = $CHILD(ndims);
                ',
);


# we don't really need this one since it can be achieved with
# a ->threadI(-1,[])
pp_def('identvaff',
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        Reversible => 1,
        AffinePriv => 1,
        RedoDims => '
                int i;
                $SETNDIMS($PARENT(ndims));
                $DOPRIVDIMS();
                $PRIV(offs) = 0;
                for(i=0; i<$PARENT(ndims); i++) {
                        $CHILD(dims[i]) = $PARENT(dims[i]);
                        $PRIV(incs[i]) = $PARENT(dimincs[i]);
                }
                $SETDIMS();
                $SETDELTATHREADIDS(0);
                $CHILD(threadids[$CHILD(nthreadids)]) = $CHILD(ndims);
                ',
);


pp_def(
        'unthread',
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        Reversible => 1,
        AffinePriv => 1,
        OtherPars => 'int atind;',
        RedoDims => '
                int i;
                $SETNDIMS($PARENT(ndims));
                $DOPRIVDIMS();
                $PRIV(offs) = 0;
                for(i=0; i<$PARENT(ndims); i++) {
                        int corc;
                        if(i<$COMP(atind)) {
                                corc = i;
                        } else if(i < $PARENT(threadids[0])) {
                                corc = i + $PARENT(ndims)-$PARENT(threadids[0]);
                        } else {
                                corc = i - $PARENT(threadids[0]) + $COMP(atind);
                        }
                        $CHILD(dims[corc]) = $PARENT(dims[i]);
                        $PRIV(incs[corc]) = $PARENT(dimincs[i]);
                }
                $SETDIMS();
        ',
);


##########
# This is a kludge to pull arbitrary data out of a single-element PDLA, using the Types.pm stuff,
# to make it easier to slice using single-element PDLA arguments inside a slice specifier.
# The string $sliceb_data_kludge generates some code that physicalizes a PDLA, ensures it has
# only one element, and extracts that element in a type-independent manner.  It's a pain because
# we have to generate the switch statement using information in the Config typehash.  But it saves
# time compared to parsing out any passed-in PDLAs on the Perl side.
#
use PDLA::Types;
$sliceb_data_kludge = <<'KLUDGE';
    { pdl *p = PDLA->SvPDLAV( *svp );
      int i;
      PDLA->make_physical(p);
      if(p->nvals==0)
        barf("slice: empty PDLA in slice specifier");
      if(p->nvals > 1)
        barf("slice: multi-element PDLA in slice specifier");
      if( !(p->data) ) {
         barf("slice: no data in slice specifier PDLA! I give up.");
      }
      switch( p->datatype ) {
KLUDGE

for my $type( PDLA::Types::typesrtkeys()) {
    $sliceb_data_kludge .=
"        case $type: nn = *( ($PDLA::Types::typehash{$type}->{realctype} *)(p->data) ); break;\n";
}

$sliceb_data_kludge .= <<'KLUDGE';
         default: barf("Unknown PDLA type in slice specifier!  This should never happen."); break;
      }
    }
KLUDGE


##############################
# sliceb is the core of slice.  The "foo/foob" nomenclature is used to avoid the argument
# counting inherent in a direct Code section call -- "slice" is a front-end that just rolls up a
# whole variable-length argument list into a single AV reference.  
#
# I'm also too lazy to figure out how to make a PMCode section work right on a dataflow PP operator.
# -- CED

pp_def(
        'sliceb',
        P2Child => 1,
        NoPdlThread => 1,
        DefaultFlow => 1,
        OtherPars => 'SV *args;',
#
# Comp stash definitions:
#  nargs - number of args in original call
#  odim[]   - maps argno to output dim (or -1 for squished dims)
#  idim[]   - maps argno to input dim  (or -1 for squished dims)
#  odim_top - one more than the highest odim encountered
#  idim_top - one more than the highest idim encountered
#  start[]  - maps argno to start index of slice range (inclusive)
#  inc[]    - maps argno to increment of slice range
#  end[]    - maps argno to end index of slice range (inclusive)
#
        Comp => 'int nargs;
                 int odim[$COMP(nargs)];
                 int idim[$COMP(nargs)];
                 int idim_top;
                 int odim_top;
                 PDLA_Indx start[$COMP(nargs)];
                 PDLA_Indx inc[$COMP(nargs)];
                 PDLA_Indx end[$COMP(nargs)];
                 ',
        AffinePriv => 1,
        MakeComp => <<'SLICE-MC'
                int i;
                int idim;
                int odim;
                int imax;
                int nargs;
                AV *arglist;

                /*** Make sure we got an array ref as input and extract its corresponding AV ***/
                if(!(  args   &&
                       SvROK(args)   &&
                       SvTYPE(SvRV(args))==SVt_PVAV  )){
                     barf("slice requires an ARRAY ref containing zero or more arguments");
                }

                arglist = (AV *)(SvRV(args));

                /* Detect special case of a single comma-delimited string; in that case, */
                /* split out our own arglist.                                            */

                if( (av_len(arglist) == 0) ) {

                  /***   single-element list: pull first element ***/

                  SV **svp;
                  svp = av_fetch(arglist, 0, 0);

                  if(svp && *svp && *svp != &PL_sv_undef && SvPOKp(*svp)) {

                    /*** The element exists and is not undef and has a cached string value ***/

                    char *s,*ss;
                    s = ss = SvPVbyte_nolen(*svp);
                    for(;  *ss && *ss != ',';  ss++) {}

                    if(*ss == ',') {
		      char *s1;

                      /* the string contains at least one comma.  ATTACK!      */
                      /* We make a temporary array and populate it with        */
                      /* SVs containing substrings -- basically split(/\,/)... */

                      AV *al = (AV *)sv_2mortal((SV *)(newAV()));

                      do {
                        for(s1=s; *s1 && *s1 != ','; s1++);

                        av_push(al, newSVpvn(s, s1-s));
                        if(*s1==',')
                          s = ++s1;
                        else
                          s = s1;
                      } while(*s);

                      arglist = al;  /* al is ephemeral and will evaporate at the next perl gc */

                    } /* end of contains-comma case */
                  } /* end of nontrivial single-element detection */
                }/* end of single-element detection */


                nargs = $COMP(nargs) = av_len( arglist ) + 1;
                $DOCOMPDIMS();


                /**********************************************************************/
                /**** Loop over the elements of the AV input and parse into values ****/
                /**** in the start/inc/end array                                   ****/

                for(odim=idim=i=0; i<nargs; i++) {
                   SV *this;
                   SV **thisp;
                   SV *sv, **svp;
                   char all_flag = 0;
                   char squish_flag = 0;
                   char dummy_flag = 0;
                   char *str;
                   PDLA_Indx n0 = 0;
                   PDLA_Indx n1 = -1;
                   PDLA_Indx n2 = 0;  /* n2 is inc - defaults to 0 (i.e. calc in RedoDims) */

                   thisp = av_fetch( arglist, i, 0 );
                   this = (thisp  ?  *thisp  : 0 );

                   /** Keep the whole dimension if the element is undefined or missing **/
                   all_flag = (  (!this)   ||   (this==&PL_sv_undef)  );

                   if(!all_flag)   {
                     /*
                      * Main branch -- this element is not an empty string
                      */

                     if(SvROK(this)) {

                       /*** It's a reference - it better be an array ref. ***/
                       int nelem;
                       AV *sublist;

                       if( SvTYPE(SvRV(this)) != SVt_PVAV ) barf("slice: non-ARRAY ref in the argument list!");



                       /*** It *is* an array ref!  Expand it into an AV so we can read it. ***/

                       sublist = (AV *)(SvRV(this));
                       if(!sublist) {
                         nelem = 0;
                       } else {
                         nelem = av_len(sublist) + 1;
                       }

                       if(nelem > 3) barf("slice: array refs can have at most 3 elements!");


                       if(nelem==0) {      /* No elements - keep it all */
                         all_flag = 1;

                       } else /* Got at least one element */{

                         /* Load the first into n0 and check for dummy or all-clear */
                         /* (if element is missing use the default value already in n0) */

                         svp = av_fetch(sublist, 0, 0);
                         if(svp && *svp && *svp != &PL_sv_undef) {

			    /* There is a first element.  Check if it's a PDLA, then a string, then an IV */

                            if(SvROK(*svp) && sv_isa(*svp, "PDLA")) {
                              PDLA_Indx nn;
SLICE-MC
. $sliceb_data_kludge  # Quick and dirty single-element parser (from above)
. <<'SLICE-MC'
                              n0 = nn;
                            } else if( SvPOKp(*svp)) {

                               /* Not a PDLA but has associated string */

                               char *str = SvPVbyte_nolen(*svp);
                               switch(*str) {
                                 case 'X':
                                      all_flag = 1; break;
                                 case '*':
                                      dummy_flag = 1;
                                      n0 = 1;         /* n0 is 1 so 2nd field is element count */
                                      n1 = 1;         /* size defaults to 1 for dummy dims */
                                      n2 = 1;         /* n2 is forced to 1 so ['*',0] gives an empty */
                                      break;
                                 default:             /* Doesn't start with '*' or 'X' */
                                      n0 = SvIV(*svp);
                                      n1 = n0;         /* n1 defaults to n0 if n0 is present */
                                      break;
                               }
                           } else /* the element has no associated string - just parse */ {
                                n0 = SvIV(*svp);
                                n1 = n0;           /* n1 defaults to n0 if n0 is present */
                           }
                        } /* end of defined check.  if it's undef, leave the n's at their default value. */


                        /* Read the second element into n1 and check for alternate squish syntax */
                        if( (nelem > 1) && (!all_flag) ) {
                          svp = av_fetch(sublist, 1, 0);

                          if( svp && *svp && *svp != &PL_sv_undef ) {

			    if( SvROK(*svp) && sv_isa(*svp, "PDLA")) {
			      PDLA_Indx nn;
SLICE-MC
. $sliceb_data_kludge
. <<'SLICE-MC'
                              n1 = nn;

                            } else if( SvPOKp(*svp) ) {
			      /* Second element has a string - make sure it's not 'X'. */
                              char *str = SvPVbyte_nolen(*svp);
                              if(*str == 'X') {
                                squish_flag = 1;
                                n1 = n0;
                              } else {
			        n1 = SvIV(*svp);
			      }
                            } else {
			       /* Not a PDLA, no string -- just get the IV */
                               n1 = SvIV(*svp);
                            }
                          } /* If not defined, leave at the default */
                        } /* End of second-element check */


                        /*** Now try to read the third element (inc).  ***/
                        if( (nelem > 2) && !(all_flag) && !(squish_flag) && !(dummy_flag) ) {
                          svp = av_fetch(sublist, 2, 0);
                          if( svp && *svp && *svp != &PL_sv_undef ) {

			    if(SvROK(*svp) && sv_isa(*svp, "PDLA")) {
			      PDLA_Indx nn;
SLICE-MC
. $sliceb_data_kludge
. << 'SLICE-MC'
                              n2 = nn;
			    } else {
                              STRLEN len;
                              SvPV( *svp, len );
                              if(len>0) {           /* nonzero length -> actual value given */
                                n2 = SvIV(*svp);    /* if the step is passed in as 0, it is a squish */
                                if(n2==0) {
                                  n1 = n0;
                                  squish_flag = 1;
                                }
                              }
			    }
                          } /* end of nontrivial third-element parsing */
                        } /* end of third-element parsing  */
                       } /* end of nontrivial sublist parsing */

                     } else /* this argument is not an ARRAY ref - parse as a scalar */ {

                        /****************************************************************/
                        /*** String handling part of slice is here.  Parse out each   ***/
                        /*** term:                                                    ***/
                        /***   <n> (or NV) - extract one element <n> from this dim    ***/
                        /***   <n>:<m>     - extract <n> to <m>; autoreverse if nec.  ***/
                        /***   <n>:<m>:<s> - extract <n> to <m>, stepping by <s>      ***/
                        /***  (<n>)        - extract element and discard this dim     ***/
                        /***  *<n>         - insert a dummy dimension of size <n>     ***/
                        /***  :            - keep this dim in its entirety            ***/
                        /***  X            - keep this dim in its entirety            ***/
                        /****************************************************************/

                        if(SvPOKp(this)) {
                          /* this argument has a cached string */

                          char *s;
                          STRLEN len;
                          int subargno = 0;
                          int flagged = 0;
                          int squish_closed = 0;
                          char buf[161];
                          char ii;
                          s = SvPVbyte(this, len);

                          /* Very stoopid parsing - should probably make some calls to perl string utilities... */
                          while(*s) {
                            if( isspace( *s ) ) {
                              s++;  /* ignore and loop again */
                            } else {
                              /* not whitespace */

                              switch(*(s++)) {
                                case '*':
                                  if(flagged || subargno)
                                    barf("slice: Erroneous '*' (arg %d)",i);
                                  dummy_flag = flagged = 1;
                                  n0 = 1;  /* default this number to 1 (size 1); '*0' yields an empty */
                                  n1 = 1;  /* no second arg allowed - default to 1 so n0 is element count */
                                  n2 = -1; /* -1 so we count down to n1 from n0 */
                                  break;

                                case '(':
                                  if(flagged || subargno)
                                    barf("slice: Erroneous '(' (arg %d)",i);
                                  squish_flag = flagged = 1;

                                  break;

                                case 'X': case 'x':
                                  if(flagged || subargno > 1)
                                    barf("slice: Erroneous 'X' (arg %d)",i);
                                    if(subargno==0) {
                                      all_flag = flagged = 1;
                                    }
                                    else /* subargno is 1 - squish */ {
                                      squish_flag = squish_closed = flagged = 1;
                                    }
                                  break;

                                case '+': case '-':
                                case '0': case '1': case '2': case '3': case '4':
                                case '5': case '6': case '7': case '8': case '9':
                                 switch(subargno) {

                                   case 0: /* first arg - change default to 1 element */
                                           n0 = strtoll(--s, &s, 10);
                                           n1 = n0;
                                           if(dummy_flag) {
                                             n0 = 1;
                                           }
                                           break;

                                   case 1: /* second arg - parse and keep end */
                                           n1 = strtoll(--s, &s, 10);
                                           break;

                                   case 2: /* third arg - parse and keep inc */
                                           if( squish_flag || dummy_flag ) {
                                            barf("slice: erroneous third field in slice specifier (arg %d)",i);
                                           }
                                           n2 = strtoll(--s, &s, 10);
                                           break;

                                   default: /* oops */
                                     barf("slice: too many subargs in scalar slice specifier %d",i);
                                     break;
                                 }
                                 break;

                                case ')':
                                 if( squish_closed || !squish_flag || subargno > 0) {
                                  barf("nslice: erroneous ')' (arg %d)",i);
                                 }
                                 squish_closed = 1;
                                 break;

                                case ':':
                                 if(squish_flag && !squish_closed) {
                                   barf("slice: must close squishing parens (arg %d)",i);
                                 }
				 if( subargno == 0 ) {
				   n1 = -1;   /* Set "<n>:" default to get the rest of the range */
				 }
                                 if( subargno > 1 ) {
                                   barf("slice: too many ':'s in scalar slice specifier %d",i);
                                 }
                                 subargno++;
                                 break;

                                case ',':
                                 barf("slice: ','  not allowed (yet) in scalar slice specifiers!");
                                 break;

                                default:
                                 barf("slice: unexpected '%c' in slice specifier (arg %d)",*s,i);
                                 break;
                              }
                            } /* end of conditional in parse loop */

                          } /* end of parse loop */

                        } else /* end of string parsing */ {

                          /* Simplest case -- there's no cached string, so it   */
                          /* must be a number.  In that case it's a simple      */
                          /* extraction.  Treated as a separate case for speed. */
                          n0 = SvNV(this);
                          n1 = SvNV(this);
                          n2 = 0;
                        }

                     } /* end of scalar handling */

                  } /* end of defined-element handling (!all_flag) */

                  if( (!all_flag) + (!squish_flag) + (!dummy_flag) < 2 ) {
                    barf("Looks like you triggered a bug in  slice.  two flags set in dim %d",i);
                  }

                  /* Force all_flag case to be a "normal" slice */
                  if(all_flag) {
                    n0 = 0;
                    n1 = -1;
                    n2 = 1;
                  }

                  /* Copy parsed values into the limits */
                  $COMP(start[i]) = n0;
                  $COMP(end[i])   = n1;
                  $COMP(inc[i])   = n2;

                  /* Deal with dimensions */
                  if(squish_flag) {
                    $COMP(odim[i]) = -1;
                  } else {
                    $COMP(odim[i]) = odim++;
                  }
                  if(dummy_flag) {
                    $COMP(idim[i]) = -1;
                  } else {
                    $COMP(idim[i]) = idim++;
                  }

                } /* end of arg-parsing loop */

                $COMP(idim_top) = idim;
                $COMP(odim_top) = odim;

                $SETREVERSIBLE(1);

             /*** End of MakeComp for slice       */
             /****************************************/
SLICE-MC
           ,
           RedoDims => q{
                  int o_ndims_extra = 0;
                  PDLA_Indx i;
		  PDLA_Indx PDIMS;

                  if( $COMP(idim_top) < $PARENT(ndims) ) {
                    o_ndims_extra = $PARENT(ndims) - $COMP(idim_top);
                  }

                  /* slurped dims from the arg parsing, plus any extra thread dims */
                  $SETNDIMS( $COMP(odim_top) + o_ndims_extra );
                  $DOPRIVDIMS();
                  $PRIV(offs) = 0;  /* Offset vector to start of slice */

                  for(i=0; i<$COMP(nargs); i++) {
                      PDLA_Indx start, end;

                      /** Belt-and-suspenders **/
                      if( ($COMP(idim[i]) < 0)  && ($COMP(odim[i]) < 0)  ) {
                        PDLA->changed($CHILD_PTR(), PDLA_PARENTDIMSCHANGED, 0);
                        barf("slice: Hmmm, both dummy and squished -- this can never happen.  I quit.");
                      }

                      /** First handle dummy dims since there's no input from the parent **/
                      if( $COMP(idim[i]) < 0 ) {
                         /* dummy dim - offset or diminc. */
                         $CHILD( dims[ $COMP(odim[i]) ] ) = $COMP(end[i]) - $COMP(start[i]) + 1;
                         $PRIV( incs[ $COMP(odim[i]) ] ) = 0;
                      } else {
                        PDLA_Indx pdsize;

                        /** This is not a dummy dim -- deal with a regular slice along it.     **/
                        /** Get parent dim size for this idim, and/or allow permissive slicing **/

                        if( $COMP(idim[i]) < $PARENT(ndims)) {
                          pdsize = $PARENT( dims[$COMP(idim[i])] );
                        } else {
                          pdsize = 1;
                        }

                        start = $COMP(start[i]);
			end = $COMP(end[i]);

			if( pdsize==0 && start==0 && end==-1 && $COMP(inc[i])==0 ) {
			  /** Trap special case: full slices of an empty dim are empty **/
			  $CHILD( dims[ $COMP(odim[i]) ] ) = 0;
                          $PRIV( incs[$COMP(odim[i]) ] ) = 0;
			} else {
			  
			  /** Regularize and bounds-check the start location **/
			  if(start < 0)
			    start += pdsize;
			  if( start < 0 || start >= pdsize ) {
			    PDLA->changed($CHILD_PTR(), PDLA_PARENTDIMSCHANGED, 0);
			    if(i >= $PARENT( ndims )) {
			      barf("slice: slice has too many dims (indexes dim %d; highest is %d)",i,$PARENT( ndims )-1);
			    } else {
			  barf("slice: slice starts out of bounds in pos %d (start is %d; source dim %d runs 0 to %d)",i,start,$COMP(idim[i]),pdsize-1);
			    }
			  }
			  
			  if( $COMP(odim[i]) < 0) {
			    
			    /* squished dim - just update the offset. */
			    /* start is always defined and regularized if we are here here, since */
			    /* both idim[i] and odim[i] can't be <0 */
			    
			    $PRIV(offs) += start * $PARENT( dimincs[ $COMP(idim[i]) ] );
			    
			  } else /* normal operation */ {
			    PDLA_Indx siz;
			    PDLA_Indx inc;
			    
			    /** Regularize and bounds-check the end location **/
			    if(end<0)
                            end += pdsize;
			    if( end < 0 || end >= pdsize ) {
			      PDLA->changed($CHILD_PTR(), PDLA_PARENTDIMSCHANGED, 0);
			      barf("slice: slice ends out of bounds in pos %d (end is %d; source dim %d runs 0 to %d)",i,end,$COMP(idim[i]),pdsize-1);
			    }
			    
			    /* regularize inc */
			    
			    inc = $COMP(inc[i]);
			    if(!inc)
			      inc = (start <= end) ? 1 : -1;
			    
			    siz = (end - start + inc) / inc ;
			    if(siz<0)
			      siz=0;
			    $CHILD( dims[ $COMP(odim[i]) ] ) = siz;
			    $PRIV(  incs[ $COMP(odim[i]) ] ) = $PARENT( dimincs[ $COMP(idim[i]) ] ) * inc;
			    $PRIV(offs) += start * $PARENT( dimincs[ $COMP(idim[i]) ] );
			  } /* end of normal slice case */
			} /* end of trapped strange slice case */
                      } /* end of non-dummy slice case */
                  } /* end of nargs loop */

                  /* Now fill in thread dimensions as needed.  idim and odim persist from the parsing loop */
                  /* up above. */
                  for(i=0; i<o_ndims_extra; i++) {
                    $CHILD( dims   [ $COMP(odim_top) + i ] ) = $PARENT( dims   [ $COMP(idim_top) + i ] );
                    $PRIV( incs[ $COMP(odim_top) + i ] ) = $PARENT( dimincs[ $COMP(idim_top) + i ] );
                  }

                $SETDIMS();

        } # end of RedoDims for slice
);

pp_done();