package PDLA::Core;

# Core routines for PDLA module

use strict;
use warnings;
use PDLA::Exporter;
use DynaLoader;
our @ISA    = qw( PDLA::Exporter DynaLoader );
our $VERSION = "2.018001";
bootstrap PDLA::Core $VERSION;
use PDLA::Types ':All';
use Config;

our @EXPORT = qw( piddle pdl null barf ); # Only stuff always exported!
my @convertfuncs = map PDLA::Types::typefld($_,'convertfunc'), PDLA::Types::typesrtkeys();
my @exports_internal = qw(howbig threadids topdl);
my @exports_normal   = (@EXPORT,
  @convertfuncs,
  qw(nelem dims shape null
      convert inplace zeroes zeros ones list listindices unpdl
      set at flows thread_define over reshape dog cat barf type diagonal
      dummy mslice approx flat sclr squeeze
      get_autopthread_targ set_autopthread_targ get_autopthread_actual
      get_autopthread_size set_autopthread_size) );
our @EXPORT_OK = (@exports_internal, @exports_normal);
our %EXPORT_TAGS = (
   Func     => [@exports_normal],
   Internal => [@exports_internal] );

our ($level, @dims, $sep, $sep2, $match);

# Important variables (place in PDLA namespace)
# (twice to eat "used only once" warning)

$PDLA::debug      =	     # Debugging info
$PDLA::debug      = 0;
$PDLA::verbose      =	     # Functions provide chatty information
$PDLA::verbose      = 0;
$PDLA::use_commas   = 0;        # Whether to insert commas when printing arrays
$PDLA::floatformat  = "%7g";    # Default print format for long numbers
$PDLA::doubleformat = "%10.8g";
$PDLA::indxformat   = "%12d";   # Default print format for PDLA_Indx values
$PDLA::undefval     = 0;        # Value to use instead of undef when creating PDLAs
$PDLA::toolongtoprint = 10000;  # maximum pdl size to stringify for printing

################ Exportable functions of the Core ######################

# log10() is now defined in ops.pd

*howbig       = \&PDLA::howbig;	  *unpdl	= \&PDLA::unpdl;
*nelem        = \&PDLA::nelem;	  *inplace	= \&PDLA::inplace;
*dims	      = \&PDLA::dims;	  *list 	= \&PDLA::list;
*threadids    = \&PDLA::threadids; *listindices  = \&PDLA::listindices;
*null	      = \&PDLA::null;	  *set  	= \&PDLA::set;
*at		= \&PDLA::at;	  *flows	= \&PDLA::flows;
*sclr           = \&PDLA::sclr;    *shape        = \&PDLA::shape;

for (map {
  [ PDLA::Types::typefld($_,'convertfunc'), PDLA::Types::typefld($_,'numval') ]
} PDLA::Types::typesrtkeys()) {
  my ($conv, $val) = @$_;
  no strict 'refs';
  *$conv = *{"PDLA::$conv"} = sub {
    return bless [$val], "PDLA::Type" unless @_;
    alltopdl('PDLA', (scalar(@_)>1 ? [@_] : shift), PDLA::Type->new($val));
  };
}

BEGIN {
    *thread_define = \&PDLA::thread_define;
    *convert      = \&PDLA::convert;   *over 	 = \&PDLA::over;
    *dog          = \&PDLA::dog;       *cat 	         = \&PDLA::cat;
    *type         = \&PDLA::type;      *approx        = \&PDLA::approx;
    *diagonal     = \&PDLA::diagonal;
    *dummy        = \&PDLA::dummy;
    *mslice       = \&PDLA::mslice;
    *isempty      = \&PDLA::isempty;
    *string       = \&PDLA::string;
}

=head1 NAME

PDLA::Core - fundamental PDLA functionality and vectorization/threading

=head1 DESCRIPTION

Methods and functions for type conversions, PDLA creation,
type conversion, threading etc.

=head1 SYNOPSIS

 use PDLA::Core;             # Normal routines
 use PDLA::Core ':Internal'; # Hairy routines

=head1 VECTORIZATION/THREADING: METHOD AND NOMENCLATURE

PDLA provides vectorized operations via a built-in engine.
Vectorization is called "threading" for historical reasons.
The threading engine implements simple rules for each operation.

Each PDLA object has a "shape" that is a generalized N-dimensional
rectangle defined by a "dim list" of sizes in an arbitrary
set of dimensions.  A PDLA with shape 2x3 has 6 elements and is
said to be two-dimensional, or may be referred to as a 2x3-PDLA.
The dimensions are indexed numerically starting at 0, so a
2x3-PDLA has a dimension 0 (or "dim 0") with size 2 and a 1 dimension
(or "dim 1") with size 3.

PDLA generalizes *all* mathematical operations with the notion of
"active dims": each operator has zero or more active dims that are
used in carrying out the operation.  Simple scalar operations like
scalar multiplication ('*') have 0 active dims.  More complicated
operators can have more active dims.  For example, matrix
multiplication ('x') has 2 active dims.  Additional dims are
automatically vectorized across -- e.g. multiplying a 2x5-PDLA with a
2x5-PDLA requires 10 simple multiplication operations, and yields a
2x5-PDLA result.

=head2 Threading rules

In any PDLA expression, the active dims appropriate for each operator
are used starting at the 0 dim and working forward through the dim
list of each object.  All additional dims after the active dims are
"thread dims".  The thread dims do not have to agree exactly: they are
coerced to agree according to simple rules:

=over 3

=item * Null PDLAs match any dim list (see below).

=item * Dims with sizes other than 1 must all agree in size.

=item * Dims of size 1 are expanded as necessary.

=item * Missing dims are expanded appropriately.

=back

The "size 1" rule implements "generalized scalar" operation, by
analogy to scalar multiplication.  The "missing dims" rule
acknowledges the ambiguity between a missing dim and a dim of size 1.

=head2 Null PDLAs

PDLAs on the left-hand side of assignment can have the special value
"Null".  A null PDLA has no dim list and no set size; its shape is
determined by the computed shape of the expression being assigned to
it.   Null PDLAs contain no values and can only be assigned to.  When
assigned to (e.g. via the C<.=> operator), they cease to be null PDLAs.

To create a null PDLA, use C<PDLA-E<gt>null()>.

=head2 Empty PDLAs

PDLAs can represent the empty set using "structured Empty" variables.
An empty PDLA is not a null PDLA.

Any dim of a PDLA can be set explicitly to size 0.  If so, the PDLA
contains zero values (because the total number of values is the
product of all the sizes in the PDLA's shape or dimlist).

Scalar PDLAs are zero-dimensional and have no entries in the dim list,
so they cannot be empty.  1-D and higher PDLAs can be empty.  Empty
PDLAs are useful for set operations, and are most commonly encountered
in the output from selection operators such as L<which|PDLA::Primitive>
and L<whichND|PDLA::Primitive>.  Not all empty PDLAs have the same
threading properties -- e.g. a 2x0-PDLA represents a collection of
2-vectors that happens to contain no elements, while a simple 0-PDLA
represents a collection of scalar values (that also happens to contain
no elements).

Note that 0 dims are not adjustable via the threading rules -- a dim
with size 0 can only match a corresponding dim of size 0 or 1.

=head2 Thread rules and assignments

Versions of PDLA through 2.4.10 have some irregularity with threading and
assignments.  Currently the threading engine performs a full expansion of
both sides of the computed assignment operator C<.=> (which assigns values
to a pre-existing PDLA).  This leads to counter-intuitive behavior in
some cases:

=over 3

=item * Generalized scalars and computed assignment

If the PDLA on the left-hand side of C<.=> has a dim of size 1, it can be
treated as a generalized scalar, as in:

    $a = sequence(2,3);
    $b = zeroes(1,3);
    $b .= $a;

In this case, C<$b> is automatically treated as a 2x3-PDLA during the
threading operation, but half of the values from C<$a> silently disappear.
The output is, as Kernighan and Ritchie would say, "undefined".

Further, if the value on the right of C<.=> is empty, then C<.=> becomes
a silent no-op:

    $a = zeroes(0);
    $b = zeroes(1);
    $b .= $a+1;
    print $b;

will print C<[0]>.  In this case, "$a+1" is empty, and "$b" is a generalized
scalar that is adjusted to be empty, so the assignment is carried out for
zero elements (a no-op).

Both of these behaviors are considered harmful and should not be relied upon:
they may be patched away in a future version of PDLA.

=item * Empty PDLAs and generalized scalars

Generalized scalars (PDLAs with a dim of size 1) can match any size in the
corresponding dim, including 0.  Thus,

    $a = ones(2,0);
    $b = sequence(2,1);
    $c = $a * $b;
    print $c;

prints C<Empty[2,0]>.

This behavior is counterintuitive but desirable, and will be preserved
in future versions of PDLA.

=back

=head1 VARIABLES

These are important variables of B<global> scope and are placed
in the PDLA namespace.

=head3 C<$PDLA::debug>

=over 4

When true, PDLA debugging information is printed.

=back

=head3 C<$PDLA::verbose>

=over 4

When true, PDLA functions provide chatty information.

=back

=head3 C<$PDLA::use_commas>

=over 4

Whether to insert commas when printing pdls

=back

=head3 C<$PDLA::floatformat>, C<$PDLA::doubleformat>, C<$PDLA::indxformat>

=over 4

The default print format for floats, doubles, and indx values,
respectively.  The default default values are:

  $PDLA::floatformat  = "%7g";
  $PDLA::doubleformat = "%10.8g";
  $PDLA::indxformat   = "%12d";

=back

=head3 C<$PDLA::undefval>

=over 4

The value to use instead of C<undef> when creating pdls.

=back

=head3 C<$PDLA::toolongtoprint>

=over 4

The maximal size pdls to print (defaults to 10000 elements)

=back

=head1 FUNCTIONS


=head2 barf

=for ref

Standard error reporting routine for PDLA.

C<barf()> is the routine PDLA modules should call to report errors. This
is because C<barf()> will report the error as coming from the correct
line in the module user's script rather than in the PDLA module.

For now, barf just calls Carp::confess()

Remember C<barf()> is your friend. *Use* it!

=for example

At the perl level:

 barf("User has too low an IQ!");

In C or XS code:

 barf("You have made %d errors", count);

Note: this is one of the few functions ALWAYS exported
by PDLA::Core

=cut

use Carp;
sub barf { goto &Carp::confess }
sub cluck { goto &Carp::cluck }
*PDLA::barf  = \&barf;
*PDLA::cluck = \&cluck;

########## Set Auto-PThread Based On Environment Vars ############
PDLA::set_autopthread_targ( $ENV{PDLA_AUTOPTHREAD_TARG} ) if( defined ( $ENV{PDLA_AUTOPTHREAD_TARG} ) );
PDLA::set_autopthread_size( $ENV{PDLA_AUTOPTHREAD_SIZE} ) if( defined ( $ENV{PDLA_AUTOPTHREAD_SIZE} ) );
##################################################################

=head2 pdl

=for ref

PDLA constructor - creates new piddle from perl scalars/arrays, piddles, and strings

=for usage

 $double_pdl = pdl(SCALAR|ARRAY REFERENCE|ARRAY|STRING);  # default type
 $type_pdl   = pdl(PDLA::Type,SCALAR|ARRAY REFERENCE|ARRAY|STRING);

=for example

 $a = pdl [1..10];                    # 1D array
 $a = pdl ([1..10]);                  # 1D array
 $a = pdl (1,2,3,4);                  # Ditto
 $b = pdl [[1,2,3],[4,5,6]];          # 2D 3x2 array
 $b = pdl "[[1,2,3],[4,5,6]]";        # Ditto (slower)
 $b = pdl "[1 2 3; 4 5 6]";           # Ditto
 $b = pdl q[1 2 3; 4 5 6];            # Ditto, using the q quote operator
 $b = pdl "1 2 3; 4 5 6";             # Ditto, less obvious, but still works
 $b = pdl 42                          # 0-dimensional scalar
 $c = pdl $a;                         # Make a new copy

 $u = pdl ushort(), 42                # 0-dimensional ushort scalar
 $b = pdl(byte(),[[1,2,3],[4,5,6]]);  # 2D byte piddle

 $n = pdl indx(), [1..5];             # 1D array of indx values
 $n = pdl indx, [1..5];               # ... can leave off parens
 $n = indx( [1..5] );                 # ... still the same!

 $a = pdl([1,2,3],[4,5,6]);           # 2D
 $a = pdl([1,2,3],[4,5,6]);           # 2D

Note the last two are equivalent - a list is automatically
converted to a list reference for syntactic convenience. i.e. you
can omit the outer C<[]>

You can mix and match arrays, array refs, and PDLAs in your argument
list, and C<pdl> will sort them out.  You get back a PDLA whose last
(slowest running) dim runs across the top level of the list you hand
in, and whose first (fastest running) dim runs across the deepest
level that you supply.

At the moment, you cannot mix and match those arguments with string
arguments, though we can't imagine a situation in which you would
really want to do that.

The string version of pdl also allows you to use the strings C<bad>, C<inf>,
and C<nan>, and it will insert the values that you mean (and set the bad flag
if you use C<bad>). You can mix and match case, though you shouldn't. Here are
some examples:

 $bad = pdl q[1 2 3 bad 5 6];  # Set fourth element to the bad value
 $bad = pdl q[1 2 3 BAD 5 6];  # ditto
 $bad = pdl q[1 2 inf bad 5];  # now third element is IEEE infinite value
 $bad = pdl q[nan 2 inf -inf]; # first value is IEEE nan value

The default constructor uses IEEE double-precision floating point numbers. You
can use other types, but you will get a warning if you try to use C<nan> with
integer types (it will be replaced with the C<bad> value) and you will get a
fatal error if you try to use C<inf>.

Throwing a PDLA into the mix has the same effect as throwing in a list ref:

  pdl(pdl(1,2),[3,4])

is the same as

  pdl([1,2],[3,4]).

All of the dimensions in the list are "padded-out" with undefval to
meet the widest dim in the list, so (e.g.)

  $a = pdl([[1,2,3],[2]])

gives you the same answer as

  $a = pdl([[1,2,3],[2,undef,undef]]);

If your PDLA module has bad values compiled into it (see L<PDLA::Bad>), 
you can pass BAD values into the constructor within pre-existing PDLAs.
The BAD values are automatically kept BAD and propagated correctly.

C<pdl()> is a functional synonym for the 'new' constructor,
e.g.:

 $x = new PDLA [1..10];

In order to control how undefs are handled in converting from perl lists to
PDLAs, one can set the variable C<$PDLA::undefval>.
For example:

 $foo = [[1,2,undef],[undef,3,4]];
 $PDLA::undefval = -999;
 $f = pdl $foo;
 print $f
 [
  [   1    2 -999]
  [-999    3    4]
 ]

C<$PDLA::undefval> defaults to zero.

As a final note, if you include an Empty PDLA in the list of objects to
construct into a PDLA, it is kept as a placeholder pane -- so if you feed
in (say) 7 objects, you get a size of 7 in the 0th dim of the output PDLA.
The placeholder panes are completely padded out.  But if you feed in only
a single Empty PDLA, you get back the Empty PDLA (no padding).

=cut

sub pdl {PDLA->pdl(@_)}

sub piddle {PDLA->pdl(@_)}

=head2 null

=for ref

Returns a 'null' piddle.

=for usage

 $x = null;

C<null()> has a special meaning to L<PDLA::PP|PDLA::PP>. It is used to
flag a special kind of empty piddle, which can grow to
appropriate dimensions to store a result (as opposed to
storing a result in an existing piddle).

=for example

 pdla> sumover sequence(10,10), $ans=null;p $ans
 [45 145 245 345 445 545 645 745 845 945]

=cut

sub PDLA::null{
	my $class = scalar(@_) ? shift : undef; # if this sub called with no
						#  class ( i.e. like 'null()', instead
						#  of '$obj->null' or 'CLASS->null', setup

	if( defined($class) ){
		$class = ref($class) || $class;  # get the class name
	}
	else{
		$class = 'PDLA';  # set class to the current package name if null called
					# with no arguments
	}

	return $class->initialize();
}

=head2 nullcreate

=for ref

Returns a 'null' piddle.

=for usage

 $x = PDLA->nullcreate($arg)

This is an routine used by many of the threading primitives
(i.e. L<sumover|PDLA::Ufunc/sumover>,
L<minimum|PDLA::Ufunc/minimum>, etc.) to generate a null piddle for the
function's output that will behave properly for derived (or
subclassed) PDLA objects.

For the above usage:
If C<$arg> is a PDLA, or a derived PDLA, then C<$arg-E<gt>null> is returned.
If C<$arg> is a scalar (i.e. a zero-dimensional PDLA) then C<PDLA-E<gt>null>
is returned.

=for example

 PDLA::Derived->nullcreate(10)
   returns PDLA::Derived->null.
 PDLA->nullcreate($pdlderived)
   returns $pdlderived->null.

=cut

sub PDLA::nullcreate{
	my ($type,$arg) = @_;
        return ref($arg) ? $arg->null : $type->null ;
}

=head2 nelem

=for ref

Return the number of elements in a piddle

=for usage

 $n = nelem($piddle); $n = $piddle->nelem;

=for example

 $mean = sum($data)/nelem($data);

=head2 dims

=for ref

Return piddle dimensions as a perl list

=for usage

 @dims = $piddle->dims;  @dims = dims($piddle);

=for example

 pdla> p @tmp = dims zeroes 10,3,22
 10 3 22

See also L<shape|shape> which returns a piddle instead.

=head2 shape

=for ref

Return piddle dimensions as a piddle

=for usage

 $shape = $piddle->shape;  $shape = shape($piddle);

=for example

 pdla> p $shape = shape zeroes 10,3,22
 [10 3 22]

See also L<dims|dims> which returns a perl list.

=head2 ndims

=for ref

Returns the number of dimensions in a piddle. Alias
for L<getndims|PDLA::Core/getndims>.

=head2 getndims

=for ref

Returns the number of dimensions in a piddle

=for usage

 $ndims = $piddle->getndims;

=for example

 pdla> p zeroes(10,3,22)->getndims
 3

=head2 dim

=for ref

Returns the size of the given dimension of a piddle. Alias
for L<getdim|PDLA::Core/getdim>.

=head2 getdim

=for ref

Returns the size of the given dimension.

=for usage

 $dim0 = $piddle->getdim(0);

=for example

 pdla> p zeroes(10,3,22)->getdim(1)
 3

Negative indices count from the end of the dims array.
Indices beyond the end will return a size of 1. This
reflects the idea that any pdl is equivalent to an
infinitely dimensional array in which only a finite number of
dimensions have a size different from one. For example, in that sense a
3D piddle of shape [3,5,2] is equivalent to a [3,5,2,1,1,1,1,1,....]
piddle. Accordingly,

  print $a->getdim(10000);

will print 1 for most practically encountered piddles.

=head2 topdl

=for ref

alternate piddle constructor - ensures arg is a piddle

=for usage

 $a = topdl(SCALAR|ARRAY REFERENCE|ARRAY);

The difference between L<pdl()|/pdl> and C<topdl()> is that the
latter will just 'fall through' if the argument is
already a piddle. It will return a reference and I<NOT>
a new copy.

This is particularly useful if you are writing a function
which is doing some fiddling with internals and assumes
a piddle argument (e.g. for method calls). Using C<topdl()>
will ensure nothing breaks if passed with '2'.

Note that C<topdl()> is not exported by default (see example
below for usage).

=for example

 use PDLA::Core ':Internal'; # use the internal routines of
                            # the Core module

 $a = topdl 43;             # $a is piddle with value '43'
 $b = topdl $piddle;        # fall through
 $a = topdl (1,2,3,4);      # Convert 1D array

=head2 get_datatype

=for ref

Internal: Return the numeric value identifying the piddle datatype

=for usage

 $x = $piddle->get_datatype;

Mainly used for internal routines.

NOTE: get_datatype returns 'just a number' not any special
type object, unlike L<type|/type>.

=head2 howbig

=for ref

Returns the sizeof a piddle datatype in bytes.

Note that C<howbig()> is not exported by default (see example
below for usage).

=for usage

 use PDLA::Core ':Internal'; # use the internal routines of
                            # the Core module

 $size = howbig($piddle->get_datatype);

Mainly used for internal routines.

NOTE: NOT a method! This is because get_datatype returns
'just a number' not any special object.

=for example

 pdla> p howbig(ushort([1..10])->get_datatype)
 2


=head2 get_dataref

=for ref

Return the internal data for a piddle, as a perl SCALAR ref.

Most piddles hold their internal data in a packed perl string, to take
advantage of perl's memory management.  This gives you direct access
to the string, which is handy when you need to manipulate the binary
data directly (e.g. for file I/O).  If you modify the string, you'll
need to call L<upd_data|upd_data> afterward, to make sure that the
piddle points to the new location of the underlying perl variable.

Calling C<get_dataref> automatically physicalizes your piddle (see
L<make_physical|/PDLA::make_physical>).  You definitely
don't want to do anything to the SV to truncate or deallocate the
string, unless you correspondingly call L<reshape|/reshape> to make the
PDLA match its new data dimension.

You definitely don't want to use get_dataref unless you know what you
are doing (or are trying to find out): you can end up scrozzling
memory if you shrink or eliminate the string representation of the
variable.  Here be dragons.

=head2 upd_data

=for ref

Update the data pointer in a piddle to match its perl SV.

This is useful if you've been monkeying with the packed string
representation of the PDLA, which you probably shouldn't be doing
anyway.  (see L<get_dataref|get_dataref>.)

=cut

sub topdl {PDLA->topdl(@_)}

####################### Overloaded operators #######################

# This is to used warn if an operand is non-numeric or non-PDLA.
sub warn_non_numeric_op_wrapper {
	my ($cb, $op_name) = @_;
	return sub {
		my ($op1, $op2) = @_;
		unless( Scalar::Util::looks_like_number($op2)
			|| ( Scalar::Util::blessed($op2) && $op2->isa('PDLA') )
			) {
			warn "'$op2' is not numeric nor a PDLA in operator $op_name";
		};
		$cb->(@_);
	}
}

{ package PDLA;
  # use UNIVERSAL 'isa'; # need that later in info function
  use Carp;

  use overload (
		"+"     => \&PDLA::plus,     # in1, in2
		"*"     => \&PDLA::mult, # in1, in2
		"-"     => \&PDLA::minus,    # in1, in2, swap if true
		"/"     => \&PDLA::divide,   # in1, in2, swap if true

		"+="    => sub { PDLA::plus     ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true
		"*="    => sub { PDLA::mult ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true
		"-="    => sub { PDLA::minus    ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true
		"/="    => sub { PDLA::divide   ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true

		">"     => \&PDLA::gt,       # in1, in2, swap if true
		"<"     => \&PDLA::lt,       # in1, in2, swap if true
		"<="    => \&PDLA::le,       # in1, in2, swap if true
		">="    => \&PDLA::ge,       # in1, in2, swap if true
		"=="    => \&PDLA::eq,       # in1, in2
		"eq"    => PDLA::Core::warn_non_numeric_op_wrapper(\&PDLA::eq, 'eq'),
		                            # in1, in2
		"!="    => \&PDLA::ne,       # in1, in2

		"<<"    => \&PDLA::shiftleft,  # in1, in2, swap if true
		">>"    => \&PDLA::shiftright, # in1, in2, swap if true
		"|"     => \&PDLA::or2,        # in1, in2
		"&"     => \&PDLA::and2,       # in1, in2
		"^"     => \&PDLA::xor,        # in1, in2

		"<<="   => sub { PDLA::shiftleft ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true
		">>="   => sub { PDLA::shiftright($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true
		"|="    => sub { PDLA::or2      ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true
		"&="    => sub { PDLA::and2     ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true
		"^="    => sub { PDLA::xor       ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true
	        "**="   => sub { PDLA::power     ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true
	        "%="    => sub { PDLA::modulo    ($_[0], $_[1], $_[0], 0); $_[0]; }, # in1, in2, out, swap if true

		"sqrt"  => sub { PDLA::sqrt ($_[0]); },
		"abs"   => sub { PDLA::abs  ($_[0]); },
		"sin"   => sub { PDLA::sin  ($_[0]); },
		"cos"   => sub { PDLA::cos  ($_[0]); },

		"!"     => sub { PDLA::not  ($_[0]); },
		"~"     => sub { PDLA::bitnot ($_[0]); },

		"log"   => sub { PDLA::log   ($_[0]); },
		"exp"   => sub { PDLA::exp   ($_[0]); },

	        "**"    => \&PDLA::power,          # in1, in2, swap if true

	        "atan2" => \&PDLA::atan2,          # in1, in2, swap if true
	        "%"     => \&PDLA::modulo,         # in1, in2, swap if true

	        "<=>"   => \&PDLA::spaceship,      # in1, in2, swap if true

		"="     =>  sub {$_[0]},          # Don't deep copy, just copy reference

		".="    => sub {
						my @args = reverse &PDLA::Core::rswap;
						PDLA::Ops::assgn(@args);
						return $args[1];
					},

		'x'     =>  sub{my $foo = $_[0]->null();
				  PDLA::Primitive::matmult(@_[0,1],$foo); $foo;},

		'bool'  => sub { return 0 if $_[0]->isnull;
				 croak("multielement piddle in conditional expression (see PDLA::FAQ questions 6-10 and 6-11)")
				     unless $_[0]->nelem == 1;
				 $_[0]->clump(-1)->at(0); },
		"\"\""  =>  \&PDLA::Core::string   );
}

sub rswap { if($_[2]) { return @_[1,0]; } else { return @_[0,1]; } }

##################### Data type/conversion stuff ########################


# XXX Optimize!

sub PDLA::dims {  # Return dimensions as @list
   my $pdl = PDLA->topdl (shift);
   my @dims = ();
   for(0..$pdl->getndims()-1) {push @dims,($pdl->getdim($_))}
   return @dims;
}

sub PDLA::shape {  # Return dimensions as a pdl
   my $pdl = PDLA->topdl (shift);
   my @dims = ();
   for(0..$pdl->getndims()-1) {push @dims,($pdl->getdim($_))}
   return indx(\@dims);
}

sub PDLA::howbig {
	my $t = shift;
	if("PDLA::Type" eq ref $t) {$t = $t->[0]}
	PDLA::howbig_c($t);
}

=head2 threadids

=for ref

Returns the piddle thread IDs as a perl list

Note that C<threadids()> is not exported by default (see example
below for usage).

=for usage

 use PDLA::Core ':Internal'; # use the internal routines of
                            # the Core module

 @ids = threadids $piddle;

=cut

sub PDLA::threadids {  # Return dimensions as @list
   my $pdl = PDLA->topdl (shift);
   my @dims = ();
   for(0..$pdl->getnthreadids()) {push @dims,($pdl->getthreadid($_))}
   return @dims;
}

################# Creation/copying functions #######################


sub PDLA::pdl { my $x = shift; return $x->new(@_) }

=head2 doflow

=for ref

Turn on/off dataflow

=for usage

 $x->doflow;  doflow($x);

=cut

sub PDLA::doflow {
	my $this = shift;
	$this->set_dataflow_f(1);
	$this->set_dataflow_b(1);
}

=head2 flows

=for ref

Whether or not a piddle is indulging in dataflow

=for usage

 something if $x->flows; $hmm = flows($x);

=cut

sub PDLA::flows {
 	my $this = shift;
         return ($this->fflows || $this->bflows);
}

=head2 new

=for ref

new piddle constructor method

=for usage

 $x = PDLA->new(SCALAR|ARRAY|ARRAY REF|STRING);

=for example

 $x = PDLA->new(42);             # new from a Perl scalar
 $x = new PDLA 42;               # ditto
 $y = PDLA->new(@list_of_vals);  # new from Perl list
 $y = new PDLA @list_of_vals;    # ditto
 $z = PDLA->new(\@list_of_vals); # new from Perl list reference
 $w = PDLA->new("[1 2 3]");      # new from Perl string, using
                                # Matlab constructor syntax

Constructs piddle from perl numbers and lists
and strings with Matlab/Octave style constructor
syntax.

The string input is fairly versatile though not
performance optimized. The goal is to make it
easy to copy and paste code from PDLA output and
to offer a familiar Matlab syntax for piddle
construction. As of May, 2010, it is a new
feature, so feel free to report bugs or suggest
new features.  See documentation for L<pdl> for
more examples of usage.


=cut

use Scalar::Util;       # for looks_like_number test
use Carp 'carp';        # for carping (warnings in caller's context)

# This is the code that handles string arguments. It has now gotten quite large,
# so here's the basic explanation. I want to allow expressions like 2, 1e3, +4,
# bad, nan, inf, and more. Checking this can get tricky. This croaks when it
# finds:
# 1) strings of e or E that are longer than 1 character long (like eeee)
# 2) non-supported characters or strings
# 3) expressions that are syntactically erroneous, like '1 2 3 ]', which has an
#    extra bracket
# 4) use of inf when the data type does not support inf (i.e. the integers)

sub PDLA::Core::new_pdl_from_string {
   my ($new, $original_value, $this, $type) = @_;
   my $value = $original_value;

   # Check for input that would generate empty piddles as output:
   my @types = PDLA::Types::types;
   return zeroes($types[$type], 1)->where(zeroes(1) < 0)
      if ($value eq '' or $value eq '[]');

   # I check for invalid characters later, but arbitrary strings of e will
   # pass that check, so I'll check for that here, first.
#   croak("PDLA::Core::new_pdl_from_string: I found consecutive copies of e but\n"
#      . "  I'm not sure what you mean. You gave me $original_value")
#      if ($value =~ /ee/i);
   croak("PDLA::Core::new_pdl_from_string: found 'e' as part of a larger word in $original_value")
      if $value =~ /e\p{IsAlpha}/ or $value =~ /\p{IsAlpha}e/;

   # Only a few characters are allowed in the expression, but we want to allow
   # expressions like 'inf' and 'bad'. As such, convert those values to internal
   # representations that will pass the invalid-character check. We'll replace
   # them with Perl-evalute-able strings in a little bit. Here, I represent
   #  bad => EE
   #  nan => ee
   #  inf => Ee
   #  pi  => eE
   # --( Bad )--
   croak("PDLA::Core::new_pdl_from_string: found 'bad' as part of a larger word in $original_value")
      if $value =~ /bad\B/ or $value =~ /\Bbad/;
   my ($has_bad) = ($value =~ s/\bbad\b/EE/gi);
   # --( nan )--
   my ($has_nan) = 0;
   croak("PDLA::Core::new_pdl_from_string: found 'nan' as part of a larger word in $original_value")
      if $value =~ /\Bnan/ or $value =~ /nan\B/;
   $has_nan++ if ($value =~ s/\bnan\b/ee/gi);
   # Strawberry Perl compatibility:
   croak("PDLA::Core::new_pdl_from_string: found '1.#IND' as part of a larger word in $original_value")
      if $value =~ /IND\B/i;
   $has_nan++ if ($value =~ s/1\.\#IND/ee/gi);
   # --( inf )--
   my ($has_inf) = 0;
   # Strawberry Perl compatibility:
   croak("PDLA::Core::new_pdl_from_string: found '1.#INF' as part of a larger word in $original_value")
      if $value =~ /INF\B/i;
   $has_inf++ if ($value =~ s/1\.\#INF/Ee/gi);
   # Other platforms:
   croak("PDLA::Core::new_pdl_from_string: found 'inf' as part of a larger word in $original_value")
      if $value =~ /inf\B/ or $value =~ /\Binf/;
   $has_inf++ if ($value =~ s/\binf\b/Ee/gi);
   # --( pi )--
   croak("PDLA::Core::new_pdl_from_string: found 'pi' as part of a larger word in $original_value")
      if $value =~ /pi\B/ or $value =~ /\Bpi/;
   $value =~ s/\bpi\b/eE/gi;

   # Some data types do not support nan and inf, so check for and warn or croak,
   # as appropriate:
   if ($has_nan and not $types[$type]->usenan) {
      carp("PDLA::Core::new_pdl_from_string: no nan for type $types[$type]; converting to bad value");
      $value =~ s/ee/EE/g;
      $has_bad += $has_nan;
      $has_nan = 0;
   }
   croak("PDLA::Core::new_pdl_from_string: type $types[$type] does not support inf")
      if ($has_inf and not $types[$type]->usenan);

   # Make the white-space uniform and see if any not-allowed characters are
   # present:
   $value =~ s/\s+/ /g;
   if (my ($disallowed) = ($value =~ /([^\[\]\+\-0-9;,.eE ]+)/)) {
      croak("PDLA::Core::new_pdl_from_string: found disallowed character(s) '$disallowed' in $original_value");
   }

   # Wrap the string in brackets [], so that the following works:
   # $a = new PDLA q[1 2 3];
   # We'll have to check for dimensions of size one after we've parsed
   # the string and built a PDLA from the resulting array.
   $value = '[' . $value . ']';

   # Make sure that each closing bracket followed by an opening bracket
   # has a comma in between them:
   $value =~ s/\]\s*\[/],[/g;

   # Semicolons indicate 'start a new row' and require special handling:
   if ($value =~ /;/) {
      $value =~ s/(\[[^\]]+;[^\]]+\])/[$1]/g;
      $value =~ s/;/],[/g;
   }

   # Remove ending decimal points and insert zeroes in front of starting
   # decimal points. This makes the white-space-to-comma replacement
   # in the next few lines much simpler.
   $value =~ s/(\d\.)(z|[^\d])/${1}0$2/g;
   $value =~ s/(\A|[^\d])\./${1}0./g;

   # Remove whitspace between signs and the numbers that follow them:
   $value =~ s/([+\-])\s+/$1/g;

#   # make unambiguous addition/subtraction (white-space on both sides
#   # of operator) by removing white-space from both sides
#   $value =~ s/([\dEe])\s+([+\-])\s+(?=[Ee\d])/$1$2/g;

   # Replace white-space separators with commas:
   $value =~ s/([.\deE])\s+(?=[+\-eE\d])/$1,/g;

   # Remove all other white space:
   $value =~ s/\s+//g;

   # Croak on operations with bad values. It might be nice to simply replace
   # these with bad values, but that is more difficult that I like, so I'm just
   # going to disallow that here:
   croak("PDLA::Core::new_pdl_from_string: Operations with bad values are not supported")
      if($value =~ /EE[+\-]/ or $value =~ /[+\-]EE/);

   # Check for things that will evaluate as functions and croak if found
   if (my ($disallowed) = ($value =~ /((\D+|\A)[eE]\d+)/)) {
      croak("PDLA::Core::new_pdl_from_string: syntax error, looks like an improper exponentiation: $disallowed\n"
         . "You originally gave me $original_value\n");
   }

   # Replace the place-holder strings with strings that will evaluate to their
   # correct numerical values when we run the eval:
   $value =~ s/\bEE\b/bad/g;
   my $bad = $types[$type]->badvalue;
   $value =~ s/\bee\b/nan/g;
   my $inf = -pdl(0)->log;
   $value =~ s/\bEe\b/inf/g;
   my $nnan = $inf - $inf;
   my $nan= $this->initialize();
   $nan->set_datatype($nnan->get_datatype);
   $nan->setdims([]);

   # pack("d*", "nan") will work here only on perls that numify the string "nan" to a NaN.
   # pack( "d*", (-1.0) ** 0.5 ) will hopefully work in more places, though it seems both
   # pack("d*", "nan") and pack( "d*", (-1.0) ** 0.5 ) fail on *old* MS Compilers (MSVC++ 6.0 and earlier).
   # sisyphus 4 Jan 2013.
   ${$nan->get_dataref}     = pack( "d*", (-1.0) ** 0.5 );

   $nan->upd_data();
   $value =~ s/\beE\b/pi/g;

   my $val = eval {
      # Install the warnings handler:
      my $old_warn_handler = $SIG{__WARN__};
      local $SIG{__WARN__} = sub {
         if ($_[0] =~ /(Argument ".*" isn't numeric)/) {
            # Send the error through die. This is *always* get caught, so keep
            # it simple.
            die "Incorrectly formatted input: $1\n";
         }
         elsif ($old_warn_handler) {
            $old_warn_handler->(@_);
         }
         else {
            warn @_;
         }
      };

      # Let's see if we can parse it as an array-of-arrays:
      local $_ = $value;
      return PDLA::Core::parse_basic_string ($inf, $nan, $nnan, $bad);
   };

   # Respect BADVAL_USENAN
   require PDLA::Config;
   $has_bad += $has_inf + $has_nan if $PDLA::Config{BADVAL_USENAN};

   if (ref $val eq 'ARRAY') {
      my $to_return = PDLA::Core::pdl_avref($val,$this,$type);
      if( $to_return->dim(-1) == 1 ) {
	      if( $to_return->dims > 1 ) {
		      # remove potentially spurious last dimension
		      $to_return = $to_return->mv(-1,1)->clump(2)->sever;
	      } elsif( $to_return->dims == 1 ) {
		      # fix scalar values
		      $to_return->setdims([]);
	      }
      }
      # Mark bad if appropriate
      $to_return->badflag($has_bad > 0);
      return $to_return;
   }
   else {
      my @message = ("PDLA::Core::new_pdl_from_string: string input='$original_value', string output='$value'" );
      if ($@) {
         push @message, $@;
      } else {
         push @message, "Internal error: unexpected output type ->$val<- is not ARRAY ref";
      }
      croak join("\n  ", @message);
   }
}

sub PDLA::Core::parse_basic_string {
	# Assumes $_ holds the string of interest, and modifies that value
	# in-place.

	use warnings;

	# Takes a string with proper bracketing, etc, and returns an array-of-arrays
	# filled with numbers, suitable for use with pdl_avref. It uses recursive
	# descent to handle the nested nature of the data. The string should have
	# no whitespace and should be something that would evaluate into a Perl
	# array-of-arrays (except that strings like 'inf', etc, are allowed).

	my ($inf, $nan, $nnan, $bad) = @_;

	# First character should be a bracket:
	die "Internal error: input string -->$_<-- did not start with an opening bracket\n"
		unless s/^\[//;

	my @to_return;
	# Loop until we run into our closing bracket:
	my $sign = 1;
	my $expects_number = 0;
	SYMBOL: until (s/^\]//) {
		# If we have a bracket, then go recursive:
		if (/^\[/) {
			die "Expected a number but found a bracket at ... ", substr ($_, 0, 10), "...\n"
				if $expects_number;
			push @to_return, PDLA::Core::parse_basic_string(@_);
			next SYMBOL;
		}
		elsif (s/^\+//) {
			die "Expected number but found a plus sign at ... ", substr ($_, 0, 10), "...\n"
				if $expects_number;
			$expects_number = 1;
			redo SYMBOL;
		}
		elsif (s/^\-//) {
			die "Expected number but found a minus sign at ... ", substr ($_, 0, 10), "...\n"
				if $expects_number;
			$sign = -1;
			$expects_number = 1;
			redo SYMBOL;
		}
		elsif (s/^bad//i) {
			push @to_return, $bad;
		}
		elsif (s/^inf//i or s/1\.\#INF//i) {
			push @to_return, $sign * $inf;
		}
		elsif (s/^nan//i or s/^1\.\#IND//i) {
                        if ($sign == -1) {
                          push @to_return, $nnan;
                        } else {
                          push @to_return, $nan;
                        }
		}
		elsif (s/^pi//i) {
			push @to_return, $sign * 4 * atan2(1, 1);
		}
		elsif (s/^e//i) {
			push @to_return, $sign * exp(1);
		}
		elsif (s/^([\d+\-e.]+)//i) {
			# Note that improper numbers are handled by the warning signal
			# handler
                        my $val = $1;
                        my $nval = $val + 0x0;
                        push @to_return, ($sign>0x0) ? $nval : -$nval;
		}
		else {
			die "Incorrectly formatted input at:\n  ", substr ($_, 0, 10), "...\n";
		}
	}
	# Strip off any commas
	continue {
		$sign = 1;
		$expects_number = 0;
		s/^,//;
	}

	return \@to_return;
}

sub PDLA::new {
   # print "in PDLA::new\n";
   my $this = shift;
   return $this->copy if ref($this);
   my $type = ref($_[0]) eq 'PDLA::Type' ? ${shift @_}[0]  : $PDLA_D;
   my $value = (@_ >1 ? [@_] : shift);  # ref thyself

   unless(defined $value) {
       if($PDLA::debug && $PDLA::undefval) {
	   print STDERR "Warning: PDLA::new converted undef to $PDLA::undefval ($PDLA::undefval)\n";
       }
       $value = $PDLA::undefval+0
   }

   return pdl_avref($value,$this,$type) if ref($value) eq "ARRAY";
   my $new = $this->initialize();
   $new->set_datatype($type);


   if (ref(\$value) eq "SCALAR") {
      # The string processing is extremely slow. Benchmarks indicated that it
      # takes 10x longer to process a scalar number compared with normal Perl
      # conversion of a string to a number. So, only use the string processing
      # if the input looks like a real string, i.e. it doesn't look like a plain
      # number. Note that for our purposes, looks_like_number incorrectly
      # handles the strings 'inf' and 'nan' on Windows machines. We want to send
      # those to the string processing, so this checks for them in a way that
      # short-circuits the looks_like_number check.
      if (PDLA::Core::is_scalar_SvPOK($value)
            and ($value =~ /inf/i or $value =~ /nan/i
               or !Scalar::Util::looks_like_number($value))) {
         # new was passed a string argument that doesn't look like a number
         # so we can process as a Matlab-style data entry format.
		return PDLA::Core::new_pdl_from_string($new,$value,$this,$type);
      } elsif ($Config{ivsize} < 8 && $pack[$new->get_datatype] eq 'q*') {
         # special case when running on a perl without 64bit int support
         # we have to avoid pack("q", ...) in this case
         # because it dies with error: "Invalid type 'q' in pack"
         $new->setdims([]);
         set_c($new, [0], $value);
      } else {
         $new->setdims([]);
         ${$new->get_dataref}     = pack( $pack[$new->get_datatype], $value );
         $new->upd_data();
      }
   }
   elsif (blessed($value)) { # Object
       $new = $value->copy;
   }
   else {
       barf("Can not interpret argument $value of type ".ref($value) );
   }
   return $new;
}


=head2 copy

=for ref

Make a physical copy of a piddle

=for usage

 $new = $old->copy;

Since C<$new = $old> just makes a new reference, the
C<copy> method is provided to allow real independent
copies to be made.

=cut

# Inheritable copy method
#
# XXX Must be fixed
# Inplace is handled by the op currently.

sub PDLA::copy {
    my $value = shift;
    barf("Argument is an ".ref($value)." not an object") unless blessed($value);
    my $option  = shift;
    $option = "" if !defined $option;
    if ($value->is_inplace) {   # Copy protection
       $value->set_inplace(0);
       return $value;
    }
    # threadI(-1,[]) is just an identity vafftrans with threadId copying ;)
    my $new = $value->threadI(-1,[])->sever;
    return $new;
}

=head2 hdr_copy

=for ref

Return an explicit copy of the header of a PDLA.

hdr_copy is just a wrapper for the internal routine _hdr_copy, which
takes the hash ref itself.  That is the routine which is used to make
copies of the header during normal operations if the hdrcpy() flag of
a PDLA is set.

General-purpose deep copies are expensive in perl, so some simple
optimization happens:

If the header is a tied array or a blessed hash ref with an associated
method called C<copy>, then that ->copy method is called.  Otherwise, all
elements of the hash are explicitly copied.  References are recursively
deep copied.

This routine seems to leak memory.

=cut

sub PDLA::hdr_copy {
  my $pdl = shift;
  my $hdr = $pdl->gethdr;
  return PDLA::_hdr_copy($hdr);
}

# Same as hdr_copy but takes a hash ref instead of a PDLA.
sub PDLA::_hdr_copy {
  my $hdr = shift;
  my $tobj;

  print "called _hdr_copy\n" if($PDLA::debug);

  unless( (ref $hdr)=~m/HASH/ ) {
    print"returning undef\n" if($PDLA::debug);
    return undef ;
  }

  if($tobj = tied %$hdr) { #
    print "tied..."if($PDLA::debug);
    if(UNIVERSAL::can($tobj,"copy")) {
      my %rhdr;
      tie(%rhdr, ref $tobj, $tobj->copy);
      print "returning\n" if($PDLA::debug);
      return \%rhdr;
    }

    # Astro::FITS::Header is special for now -- no copy method yet
    # but it is recognized.  Once it gets a copy method this will become
    # vestigial:

    if(UNIVERSAL::isa($tobj,"Astro::FITS::Header")) {
      print "Astro::FITS::Header..." if($PDLA::debug);
      my @cards = $tobj->cards;
      my %rhdr;
      tie(%rhdr,"Astro::FITS::Header", new Astro::FITS::Header(Cards=>\@cards));
      print "returning\n" if($PDLA::debug);
      return \%rhdr;
    }
  }
  elsif(UNIVERSAL::can($hdr,"copy")) {
    print "found a copy method\n" if($PDLA::debug);
    return $hdr->copy;
  }

  # We got here if it's an unrecognized tie or if it's a vanilla hash.
  print "Making a hash copy..." if($PDLA::debug);

  return PDLA::_deep_hdr_copy($hdr);

}

#
# Sleazy deep-copier that gets most cases
# --CED 14-April-2003
#

sub PDLA::_deep_hdr_copy {
  my $val = shift;

  if(ref $val eq 'HASH') {
    my (%a,$key);
    for $key(keys %$val) {
      my $value = $val->{$key};
      $a{$key} = (ref $value) ? PDLA::_deep_hdr_copy($value) : $value;
    }
    return \%a;
  }

  if(ref $val eq 'ARRAY') {
    my (@a,$z);
    for $z(@$val) {
      push(@a,(ref $z) ? PDLA::_deep_hdr_copy($z) : $z);
    }
    return \@a;
  }

  if(ref $val eq 'SCALAR') {
    my $a = $$val;
    return \$a;
  }

  if(ref $val eq 'REF') {
    my $a = PDLA::_deep_hdr_copy($$val);
    return \$a;
  }

  # Special case for PDLAs avoids potential nasty header recursion...
  if(UNIVERSAL::isa($val,'PDLA')) {
    my $h;
    $val->hdrcpy(0) if($h = $val->hdrcpy); # assignment
    my $out = $val->copy;
    $val->hdrcpy($h) if($h);
    return $out;
  }

  if(UNIVERSAL::can($val,'copy')) {
    return $val->copy;
  }

  $val;
}


=head2 unwind

=for ref

Return a piddle which is the same as the argument except
that all threadids have been removed.

=for usage

 $y = $x->unwind;

=head2 make_physical

=for ref

Make sure the data portion of a piddle can be accessed from XS code.

=for example

 $a->make_physical;
 $a->call_my_xs_method;

Ensures that a piddle gets its own allocated copy of data. This obviously
implies that there are certain piddles which do not have their own data.
These are so called I<virtual> piddles that make use of the I<vaffine>
optimisation (see L<PDLA::Indexing|PDLA::Indexing>).
They do not have their own copy of
data but instead store only access information to some (or all) of another
piddle's data.

Note: this function should not be used unless absolutely necessary
since otherwise memory requirements might be severly increased. Instead
of writing your own XS code with the need to call C<make_physical> you
might want to consider using the PDLA preprocessor
(see L<PDLA::PP|PDLA::PP>)
which can be used to transparently access virtual piddles without the
need to physicalise them (though there are exceptions).

=cut

sub PDLA::unwind {
	my $value = shift;
	my $foo = $value->null();
	$foo .= $value->unthread();
	return $foo;
}

=head2 dummy

=for ref

Insert a 'dummy dimension' of given length (defaults to 1)

No relation to the 'Dungeon Dimensions' in Discworld!

Negative positions specify relative to last dimension,
i.e. C<dummy(-1)> appends one dimension at end,
C<dummy(-2)> inserts a dummy dimension in front of the
last dim, etc.

If you specify a dimension position larger than the existing
dimension list of your PDLA, the PDLA gets automagically padded with extra
dummy dimensions so that you get the dim you asked for, in the slot you
asked for.  This could cause you trouble if, for example,
you ask for $a->dummy(5000,1) because $a will get 5,000 dimensions,
each of rank 1.

Because padding at the beginning of the dimension list moves existing
dimensions from slot to slot, it's considered unsafe, so automagic
padding doesn't work for large negative indices -- only for large
positive indices.

=for usage

 $y = $x->dummy($position[,$dimsize]);

=for example

 pdla> p sequence(3)->dummy(0,3)
 [
  [0 0 0]
  [1 1 1]
  [2 2 2]
 ]

 pdla> p sequence(3)->dummy(3,2)
 [
  [
   [0 1 2]
  ]
  [
   [0 1 2]
  ]
 ]

 pdla> p sequence(3)->dummy(-3,2)
 Runtime error: PDLA: For safety, <pos> < -(dims+1) forbidden in dummy.  min=-2, pos=-3

=cut

sub PDLA::dummy($$;$) {
   my ($pdl,$dim,$size) = @_;
   barf("Missing position argument to dummy()") unless defined $dim;  # required argument
   $dim = $pdl->getndims+1+$dim if $dim < 0;
   $size = defined($size) ? (1 * $size) : 1;  # make $size a number (sf feature # 3479009)

   barf("For safety, <pos> < -(dims+1) forbidden in dummy.  min="
	 . -($pdl->getndims+1).", pos=". ($dim-1-$pdl->getndims) ) if($dim<0);

   # Avoid negative repeat count warning that came with 5.21 and later.
   my $dim_diff = $dim - $pdl->getndims;
   my($s) = ',' x ( $dim_diff > 0 ? $pdl->getndims : $dim );
   $s .= '*1,'  x ( $dim_diff > 0 ? $dim_diff : 0 );
   $s .= "*$size";

   $pdl->slice($s);
}


## Cheesy, slow way
#   while ($dim>$pdl->getndims){
#     print STDERR "."; flush STDERR;
#     $pdl = $pdl->dummy($pdl->getndims,1);
#   }
#
#   barf ("too high/low dimension in call to dummy, allowed min/max=0/"
# 	 . $_[0]->getndims)
#     if $dim>$pdl->getndims || $dim < 0;
#
#   $_[2] = 1 if ($#_ < 2);
#   $pdl->slice((','x$dim)."*$_[2]");

=head2 clump

=for ref

"clumps" several dimensions into one large dimension

If called with one argument C<$n> clumps the first C<$n>
dimensions into one. For example, if C<$a> has dimensions
C<(5,3,4)> then after

=for example

 $b = $a->clump(2);   # Clump 2 first dimensions

the variable C<$b> will have dimensions C<(15,4)>
and the element C<$b-E<gt>at(7,3)> refers to the element
C<$a-E<gt>at(1,2,3)>.

Use C<clump(-1)> to flatten a piddle. The method L<flat|PDLA::Core/flat>
is provided as a convenient alias.

Clumping with a negative dimension in general leaves that many
dimensions behind -- e.g. clump(-2) clumps all of the first few
dimensions into a single one, leaving a 2-D piddle.

If C<clump> is called with an index list with more than one element
it is treated as a list of dimensions that should be clumped together
into one. The resulting
clumped dim is placed at the position of the lowest index in the list.
This convention ensures that C<clump> does the expected thing in
the usual cases. The following example demonstrates typical usage:

  $a = sequence 2,3,3,3,5; # 5D piddle
  $c = $a->clump(1..3);    # clump all the dims 1 to 3 into one
  print $c->info;          # resulting 3D piddle has clumped dim at pos 1
 PDLA: Double D [2,27,5]

=cut

sub PDLA::clump {
  my $ndims = $_[0]->getndims;
  if ($#_ < 2) {
    return &PDLA::_clump_int(@_);
  } else {
    my ($this,@dims) = @_;
    my $targd = $ndims-1;
    my @dimmark = (0..$ndims-1);
    barf "too many dimensions" if @dims > $ndims;
    for my $dim (@dims) {
      barf "dimension index $dim larger than greatest dimension"
	if $dim > $ndims-1 ;
      $targd = $dim if $targd > $dim;
      barf "duplicate dimension $dim" if $dimmark[$dim]++ > $dim;
    }
    my $clumped = $this->thread(@dims)->unthread(0)->clump(scalar @dims);
    $clumped = $clumped->mv(0,$targd) if $targd > 0;
    return $clumped;
  }
}

=head2 thread_define

=for ref

define functions that support threading at the perl level

=for example

 thread_define 'tline(a(n);b(n))', over {
  line $_[0], $_[1]; # make line compliant with threading
 };


C<thread_define> provides some support for threading (see
L<PDLA::Indexing>) at the perl level. It allows you to do things for
which you normally would have resorted to PDLA::PP (see L<PDLA::PP>);
however, it is most useful to wrap existing perl functions so that the
new routine supports PDLA threading.

C<thread_define> is used to define new I<threading aware>
functions. Its first argument is a symbolic repesentation of the new
function to be defined. The string is composed of the name of the new
function followed by its signature (see L<PDLA::Indexing> and L<PDLA::PP>)
in parentheses. The second argument is a subroutine that will be
called with the slices of the actual runtime arguments as specified by
its signature. Correct dimension sizes and minimal number of
dimensions for all arguments will be checked (assuming the rules of
PDLA threading, see L<PDLA::Indexing>).

The actual work is done by the C<signature> class which parses the signature
string, does runtime dimension checks and the routine C<threadover> that
generates the loop over all appropriate slices of pdl arguments and creates
pdls as needed.

Similar to C<pp_def> and its C<OtherPars> option it is possible to
define the new function so that it accepts normal perl args as well as
piddles. You do this by using the C<NOtherPars> parameter in the
signature. The number of C<NOtherPars> specified will be passed
unaltered into the subroutine given as the second argument of
C<thread_define>. Let's illustrate this with an example:

 PDLA::thread_define 'triangles(inda();indb();indc()), NOtherPars => 2',
  PDLA::over {
    ${$_[3]} .= $_[4].join(',',map {$_->at} @_[0..2]).",-1,\n";
  };

This defines a function C<triangles> that takes 3 piddles as input
plus 2 arguments which are passed into the routine unaltered. This routine
is used to collect lists of indices into a perl scalar that is passed by
reference. Each line is preceded by a prefix passed as C<$_[4]>. Here is
typical usage:

 $txt = '';
 triangles(pdl(1,2,3),pdl(1),pdl(0),\$txt," "x10);
 print $txt;

resulting in the following output

 1,1,0,-1,
 2,1,0,-1,
 3,1,0,-1,

which is used in
L<PDLA::Graphics::TriD::VRML|PDLA::Graphics::TriD::VRML>
to generate VRML output.

Currently, this is probably not much more than a POP (proof of principle)
but is hoped to be useful enough for some real life work.

Check L<PDLA::PP|PDLA::PP> for the format of the signature. Currently, the
C<[t]> qualifier and all type qualifiers are ignored.

=cut

sub PDLA::over (&) { $_[0] }
sub PDLA::thread_define ($$) {
  require PDLA::PP::Signature;
  my ($str,$sub) = @_;
  my $others = 0;
  if ($str =~ s/[,]*\s*NOtherPars\s*=>\s*([0-9]+)\s*[,]*//) {$others = $1}
  barf "invalid string $str" unless $str =~ /\s*([^(]+)\((.+)\)\s*$/x;
  my ($name,$sigstr) = ($1,$2);
  print "defining '$name' with signature '$sigstr' and $others extra args\n"
						  if $PDLA::debug;
  my $sig = new PDLA::PP::Signature($sigstr);
  my $args = @{$sig->names}; # number of piddle arguments
  barf "no piddle args" if $args == 0;
  $args--;
  # TODO: $sig->dimcheck(@_) + proper creating generation
  my $def = "\@_[0..$args] = map {PDLA::Core::topdl(\$_)} \@_[0..$args];\n".
            '$sig->checkdims(@_);
	     PDLA::threadover($others,@_,$sig->realdims,$sig->creating,$sub)';
  my $package = caller;
  local $^W = 0; # supress the 'not shared' warnings
  print "defining...\nsub $name { $def }\n" if $PDLA::debug;
  eval ("package $package; sub $name { $def }");
  barf "error defining $name: $@\n" if $@;
}

=head2 thread

=for ref

Use explicit threading over specified dimensions (see also L<PDLA::Indexing>)

=for usage

 $b = $a->thread($dim,[$dim1,...])

=for example

 $a = zeroes 3,4,5;
 $b = $a->thread(2,0);

Same as L<PDLA::thread1|/PDLA::thread1>, i.e. uses thread id 1.

=cut

sub PDLA::thread {
	my $var = shift;
	$var->threadI(1,\@_);
}

=head2 diagonal

=for ref

Returns the multidimensional diagonal over the specified dimensions.

=for usage

 $d = $x->diagonal(dim1, dim2,...)

=for example

 pdla> $a = zeroes(3,3,3);
 pdla> ($b = $a->diagonal(0,1))++;
 pdla> p $a
 [
  [
   [1 0 0]
   [0 1 0]
   [0 0 1]
  ]
  [
   [1 0 0]
   [0 1 0]
   [0 0 1]
  ]
  [
   [1 0 0]
   [0 1 0]
   [0 0 1]
  ]
 ]

=cut

sub PDLA::diagonal {
	my $var = shift;
	$var->diagonalI(\@_);
}

=head2 thread1

=for ref

Explicit threading over specified dims using thread id 1.

=for usage

 $xx = $x->thread1(3,1)

=for example

 Wibble

Convenience function interfacing to
L<PDLA::Slices::threadI|PDLA::Slices/threadI>.

=cut

sub PDLA::thread1 {
	my $var = shift;
	$var->threadI(1,\@_);
}

=head2 thread2

=for ref

Explicit threading over specified dims using thread id 2.

=for usage

 $xx = $x->thread2(3,1)

=for example

 Wibble

Convenience function interfacing to
L<PDLA::Slices::threadI|PDLA::Slices/threadI>.

=cut

sub PDLA::thread2 {
	my $var = shift;
	$var->threadI(2,\@_);
}

=head2 thread3

=for ref

Explicit threading over specified dims using thread id 3.

=for usage

 $xx = $x->thread3(3,1)

=for example

 Wibble

Convenience function interfacing to
L<PDLA::Slices::threadI|PDLA::Slices/threadI>.

=cut

sub PDLA::thread3 {
	my $var = shift;
	$var->threadI(3,\@_);
}

my %info = (
	    D => {
		  Name => 'Dimension',
		  Sub => \&PDLA::Core::dimstr,
		 },
	    T => {
		  Name => 'Type',
		  Sub => sub { return $_[0]->type->shortctype; },
		 },
	    S => {
		  Name => 'State',
		  Sub => sub { my $state = '';
			       $state .= 'P' if $_[0]->allocated;
			       $state .= 'V' if $_[0]->vaffine &&
				 !$_[0]->allocated; # apparently can be both?
			       $state .= '-' if $state eq '';   # lazy eval
			       $state .= 'C' if $_[0]->anychgd;
 			       $state .= 'B' if $_[0]->badflag;
			       $state;
			     },
		 },
	    F => {
		  Name => 'Flow',
		  Sub => sub { my $flows = '';
			       $flows = ($_[0]->bflows ? 'b':'') .
				 '~' . ($_[0]->fflows ? 'f':'')
				   if ($_[0]->flows);
			       $flows;
			     },
		 },
	    M => {
		  Name => 'Mem',
		  Sub => sub { my ($size,$unit) = ($_[0]->allocated ?
						   $_[0]->nelem*
                      PDLA::howbig($_[0]->get_datatype)/1024 : 0, 'KB');
			       if ($size > 0.01*1024) { $size /= 1024;
							$unit = 'MB' };
			       return sprintf "%6.2f%s",$size,$unit;
			     },
		 },
	    C => {
		  Name => 'Class',
		  Sub => sub { ref $_[0] }
		 },
	    A => {
		  Name => 'Address',
		  Sub => sub { use Config;
                               my $ivdformat = $Config{ivdformat};
                               $ivdformat =~ s/"//g;
                               sprintf "%$ivdformat", $_[0]->address }
		 },
	   );

my $allowed = join '',keys %info;

# print the dimension information about a pdl in some appropriate form
sub dimstr {
  my $this = shift;

  my @dims = $this->dims;
  my @ids  = $this->threadids;
  my ($nids,$i) = ($#ids - 1,0);
  my $dstr = 'D ['. join(',',@dims[0..($ids[0]-1)]) .']';
  if ($nids > 0) {
    for $i (1..$nids) {
      $dstr .= " T$i [". join(',',@dims[$ids[$i]..$ids[$i+1]-1]) .']';
    }
  }
  return $dstr;
}

=head2 sever

=for ref

sever any links of this piddle to parent piddles

In PDLA it is possible for a piddle to be just another
view into another piddle's data. In that case we call
this piddle a I<virtual piddle> and the original piddle owning
the data its parent. In other languages these alternate views
sometimes run by names such as I<alias> or I<smart reference>.

Typical functions that return such piddles are C<slice>, C<xchg>,
C<index>, etc. Sometimes, however, you would like to separate the
I<virtual piddle> from its parent's data and just give it a life of
its own (so that manipulation of its data doesn't change the parent).
This is simply achieved by using C<sever>. For example,

=for example

   $a = $pdl->index(pdl(0,3,7))->sever;
   $a++;       # important: $pdl is not modified!

In many (but not all) circumstances it acts therefore similar to
L<copy|PDLA::Core/copy>.
However, in general performance is better with C<sever> and secondly,
C<sever> doesn't lead to futile copying when used on piddles that
already have their own data. On the other hand, if you really want to make
sure to work on a copy of a piddle use L<copy|PDLA::Core/copy>.

   $a = zeroes(20);
   $a->sever;   # NOOP since $a is already its own boss!

Again note: C<sever> I<is not> the same as L<copy|PDLA::Core/copy>!
For example,

   $a = zeroes(1); # $a does not have a parent, i.e. it is not a slice etc
   $b = $a->sever; # $b is now pointing to the same piddle as $a
   $b++;
   print $a;
 [1]

but

   $a = zeroes(1);
   $b = $a->copy; # $b is now pointing to a new piddle
   $b++;
   print $a;
 [0]


=head2 info

=for ref

Return formatted information about a piddle.

=for usage

 $x->info($format_string);

=for example

 print $x->info("Type: %T Dim: %-15D State: %S");

Returns a string with info about a piddle. Takes an optional
argument to specify the format of information a la sprintf.
Format specifiers are in the form C<%E<lt>widthE<gt>E<lt>letterE<gt>>
where the width is optional and the letter is one of

=over 7

=item T

Type

=item D

Formatted Dimensions

=item F

Dataflow status

=item S

Some internal flags (P=physical,V=Vaffine,C=changed,B=may contain bad data)

=item C

Class of this piddle, i.e. C<ref $pdl>

=item A

Address of the piddle struct as a unique identifier

=item M

Calculated memory consumption of this piddle's data area

=back

=cut

sub PDLA::info {
    my ($this,$str) = @_;
    $str = "%C: %T %D" unless defined $str;
    return ref($this)."->null" if $this->isnull;
    my @hash = split /(%[-,0-9]*[.]?[0-9]*\w)/, $str;
    my @args = ();
    my $nstr = '';
    for my $form (@hash) {
	if ($form =~ s/^%([-,0-9]*[.]?[0-9]*)(\w)$/%$1s/) {
	    barf "unknown format specifier $2" unless defined $info{$2};
	    push @args, &{$info{$2}->{Sub}}($this);
	}
	$nstr .= $form;
    }
    return sprintf $nstr, @args;
}

=head2 approx

=for ref

test for approximately equal values (relaxed C<==>)

=for example

  # ok if all corresponding values in
  # piddles are within 1e-8 of each other
  print "ok\n" if all approx $a, $b, 1e-8;

C<approx> is a relaxed form of the C<==> operator and
often more appropriate for floating point types (C<float>
and C<double>).

Usage:

=for usage

  $res = approx $a, $b [, $eps]

The optional parameter C<$eps> is remembered across invocations
and initially set to 1e-6, e.g.

  approx $a, $b;         # last $eps used (1e-6 initially)
  approx $a, $b, 1e-10;  # 1e-10
  approx $a, $b;         # also 1e-10

=cut

my $approx = 1e-6;  # a reasonable init value
sub PDLA::approx {
  my ($a,$b,$eps) = @_;
  $eps = $approx unless defined $eps;  # the default eps
  $approx = $eps;    # remember last eps
  # NOTE: ($a-$b)->abs breaks for non-piddle inputs
  return abs($a-$b) < $eps;
}

=head2 mslice

=for ref

Convenience interface to L<slice|PDLA::Slices/slice>,
allowing easier inclusion of dimensions in perl code.

=for usage

 $a = $x->mslice(...);

=for example

 # below is the same as $x->slice("5:7,:,3:4:2")
 $a = $x->mslice([5,7],X,[3,4,2]);

=cut

# called for colon-less args
# preserves parens if present
sub intpars { $_[0] =~ /\(.*\)/ ? '('.int($_[0]).')' : int $_[0] }

sub PDLA::mslice {
        my($pdl) = shift;
        return $pdl->slice(join ',',(map {
                        !ref $_ && $_ eq "X" ? ":" :
			   ref $_ eq "ARRAY" ? $#$_ > 1 && @$_[2] == 0 ?
			   "(".int(@$_[0]).")" : join ':', map {int $_} @$_ :
                        !ref $_ ? intpars $_ :
                        die "INVALID SLICE DEF $_"
                } @_));
}

=head2 nslice_if_pdl

=for ref

If C<$self> is a PDLA, then calls C<slice> with all but the last
argument, otherwise $self->($_[-1]) is called where $_[-1} is the
original argument string found during PDLA::NiceSlice filtering.

DEVELOPER'S NOTE: this routine is found in Core.pm.PL but would be
better placed in Slices/slices.pd.  It is likely to be moved there
and/or changed to "slice_if_pdl" for PDLA 3.0.

=for usage

 $a = $x->nslice_if_pdl(...,'(args)');

=cut

sub PDLA::nslice_if_pdl {
   my ($pdl) = shift;
   my ($orig_args) = pop;

   # warn "PDLA::nslice_if_pdl called with (@_) args, originally ($orig_args)\n";

   if (ref($pdl) eq 'CODE') {
      # barf('PDLA::nslice_if_pdl tried to process a sub ref, please use &$subref() syntax')
      @_ = eval $orig_args;
      goto &$pdl;
   }

   unshift @_, $pdl;
   goto &PDLA::slice;
}

=head2 nslice

=for ref

c<nslice> was an internally used interface for L<PDLA::NiceSlice|PDLA::NiceSlice>,
but is now merely a springboard to L<PDLA::Slice|PDLA::Slice>.  It is deprecated
and likely to disappear in PDLA 3.0.

=cut
sub PDLA::nslice {
    unless($PDLA::nslice_warning_issued) {
	$PDLA::nslice_warning_issued = 1;
	warn "WARNING: deprecated call to PDLA::nslice detected.  Use PDLA::slice instead.\n (Warning will be issued only once per session)\n";
    }
    goto &PDLA::slice;
}

sub blessed {
    my $ref = ref(shift);
    return $ref =~ /^(REF|SCALAR|ARRAY|HASH|CODE|GLOB||)$/ ? 0 : 1;
}

# Convert numbers to PDLA if not already

sub PDLA::topdl {
    return $_[0]->new(@_[1..$#_]) if($#_ > 1); # PDLAify an ARRAY
    return $_[1] if blessed($_[1]); # Fall through
    return $_[0]->new($_[1]) if ref(\$_[1]) eq  'SCALAR' or
           ref($_[1]) eq 'ARRAY';
    barf("Can not convert a ".ref($_[1])." to a ".$_[0]);
0;}

# Convert everything to PDLA if not blessed

sub alltopdl {
    if (ref $_[2] eq 'PDLA::Type') {
      return convert($_[1], $_[2]) if blessed($_[1]);
      return $_[0]->new($_[2], $_[1]) if $_[0] eq 'PDLA';
    }
    return $_[1] if blessed($_[1]); # Fall through
    return $_[0]->new($_[1]);
0;}


=head2 inplace

=for ref

Flag a piddle so that the next operation is done 'in place'

=for usage

 somefunc($x->inplace); somefunc(inplace $x);

In most cases one likes to use the syntax C<$y = f($x)>, however
in many case the operation C<f()> can be done correctly
'in place', i.e. without making a new copy of the data for
output. To make it easy to use this, we write C<f()> in such
a way that it operates in-place, and use C<inplace> to hint
that a new copy should be disabled. This also makes for
clear syntax.

Obviously this will not work for all functions, and if in
doubt see the function's documentation. However one
can assume this is
true for all elemental functions (i.e. those which just
operate array element by array element like C<log10>).

=for example

 pdla> $x = xvals zeroes 10;
 pdla> log10(inplace $x)
 pdla> p $x
 [-inf 0    0.30103 0.47712125 0.60205999    0.69897 0.77815125 0.84509804 0.90308999 0.95424251]

=cut

# Flag pdl for in-place operations

sub PDLA::inplace {
    my $pdl = PDLA->topdl(shift); $pdl->set_inplace(1); return $pdl;
}

# Copy if not inplace


=head2 is_inplace

=for ref

Test the in-place flag on a piddle

=for usage

  $out = ($in->is_inplace) ? $in : zeroes($in);
  $in->set_inplace(0)

Provides access to the L<inplace|/inplace> hint flag, within the perl millieu.
That way functions you write can be inplace aware... If given an
argument the inplace flag will be set or unset depending on the value
at the same time. Can be used for shortcut tests that delete the
inplace flag while testing:

  $out = ($in->is_inplace(0)) ? $in : zeroes($in); # test & unset!

=head2 set_inplace

=for ref

Set the in-place flag on a piddle

=for usage

  $out = ($in->is_inplace) ? $in : zeroes($in);
  $in->set_inplace(0);

Provides access to the L<inplace|/inplace> hint flag, within the perl millieu.
Useful mainly for turning it OFF, as L<inplace|/inplace> turns it ON more
conveniently.

=head2 new_or_inplace

=for usage

    $a = new_or_inplace(shift());
    $a = new_or_inplace(shift(),$preferred_type);

=for ref

Return back either the argument pdl or a copy of it depending on whether
it be flagged in-place or no.  Handy for building inplace-aware functions.

If you specify a preferred type (must be one of the usual PDLA type strings,
a list ref containing several of them, or a string containing several of them),
then the copy is coerced into the first preferred type listed if it is not
already one of the preferred types.

Note that if the inplace flag is set, no coersion happens even if you specify
a preferred type.

=cut

sub new_or_inplace {
	my $pdl = shift;
	my $preferred = shift;
	my $force = shift;
	if($pdl->is_inplace) {
		$pdl->set_inplace(0);
		return $pdl;
	} else {
	    unless(defined($preferred)) {
		return $pdl->copy;
	    } else {
		$preferred = join(",",@$preferred) if(ref($preferred) eq 'ARRAY');
		my $s = "".$pdl->type;
		if($preferred =~ m/(^|\,)$s(\,|$)/i) {
		    # Got a match - the PDLA is one of the preferred types.
		    return $pdl->copy();
		} else {
		    # No match - promote it to the first in the list.
		    $preferred =~ s/\,.*//;
		    my $out = PDLA::new_from_specification('PDLA',new PDLA::Type($preferred),$pdl->dims);
		    $out .= $pdl;
		    return $out;
		}
	    }
	}
	barf "PDLA::Core::new_or_inplace - This can never happen!";
}
*PDLA::new_or_inplace = \&new_or_inplace;

# Allow specifications like zeroes(10,10) or zeroes($x)
# or zeroes(inplace $x) or zeroes(float,4,3)

=head2 new_from_specification

=for ref

Internal method: create piddle by specification

This is the argument processing method called by L<zeroes|/zeroes>
and some other functions
which constructs piddles from argument lists of the form:

 [type], $nx, $ny, $nz,...

For C<$nx>, C<$ny>, etc. 0 and 1D piddles are allowed.
Giving those has the same effect as if saying C<$arg-E<gt>list>,
e.g.

   1, pdl(5,2), 4

is equivalent to

   1, 5, 2, 4

Note, however, that in all functions using C<new_from_specification>
calling C<func $piddle> will probably not do what you want. So to play safe
use (e.g. with zeroes)

  $pdl = zeroes $dimpdl->list;

Calling

  $pdl = zeroes $dimpdl;

will rather be equivalent to

  $pdl = zeroes $dimpdl->dims;

However,

  $pdl = zeroes ushort, $dimpdl;

will again do what you intended since it is interpreted
as if you had said

  $pdl = zeroes ushort, $dimpdl->list;

This is unfortunate and confusing but no good solution seems
obvious that would not break existing scripts.

=cut

sub PDLA::new_from_specification{
    my $class = shift;
    my $type = ref($_[0]) eq 'PDLA::Type' ? ${shift @_}[0]  : $PDLA_D;
    my $nelems = 1; my @dims;
    for (@_) {
       if (ref $_) {
         barf "Trying to use non-piddle as dimensions?" unless $_->isa('PDLA');
         barf "Trying to use multi-dim piddle as dimensions?"
              if $_->getndims > 1;
         warn "creating > 10 dim piddle (piddle arg)!"
              if $_->nelem > 10;
         for my $dim ($_->list) {$nelems *= $dim; push @dims, $dim}
       } else {
          if ($_) {  # quiet warnings when $_ is the empty string
             barf "Dimensions must be non-negative" if $_<0;
             $nelems *= $_; push @dims, $_
          } else {
             $nelems *= 0; push @dims, 0;
          }
       }
    }
    my $pdl = $class->initialize();
    $pdl->set_datatype($type);
    $pdl->setdims([@dims]);
    print "Dims: ",(join ',',@dims)," DLen: ",(length $ {$pdl->get_dataref}),"\n" if $PDLA::debug;
    return $pdl;
}

=head2 isnull

=for ref

Test whether a piddle is null

=for usage

 croak("Input piddle mustn't be null!")
     if $input_piddle->isnull;

This function returns 1 if the piddle is null, zero if it is not. The purpose
of null piddles is to "tell" any PDLA::PP methods to allocate new memory for
an output piddle, but only when that PDLA::PP method is called in full-arg
form. Of course, there's no reason you couldn't commandeer the special value
for your own purposes, for which this test function would prove most helpful.
But in general, you shouldn't need to test for a piddle's nullness.

See L</Null PDLAs> for more information.

=head2 isempty

=for ref

Test whether a piddle is empty

=for usage

 print "The piddle has zero dimension\n" if $pdl->isempty;

This function returns 1 if the piddle has zero elements. This is
useful in particular when using the indexing function which. In the
case of no match to a specified criterion, the returned piddle has
zero dimension.

 pdla> $a=sequence(10)
 pdla> $i=which($a < -1)
 pdla> print "I found no matches!\n" if ($i->isempty);
 I found no matches!

Note that having zero elements is rather different from the concept
of being a null piddle, see the L<PDLA::FAQ|PDLA::FAQ> and
L<PDLA::Indexing|PDLA::Indexing>
manpages for discussions of this.

=cut

sub PDLA::isempty {
    my $pdl=shift;
    return ($pdl->nelem == 0);
}

=head2 zeroes

=for ref

construct a zero filled piddle from dimension list or template piddle.

Various forms of usage,

(i) by specification or (ii) by template piddle:

=for usage

 # usage type (i):
 $a = zeroes([type], $nx, $ny, $nz,...);
 $a = PDLA->zeroes([type], $nx, $ny, $nz,...);
 $a = $pdl->zeroes([type], $nx, $ny, $nz,...);
 # usage type (ii):
 $a = zeroes $b;
 $a = $b->zeroes
 zeroes inplace $a;     # Equivalent to   $a .= 0;
 $a->inplace->zeroes;   #  ""

=for example

 pdla> $z = zeroes 4,3
 pdla> p $z
 [
  [0 0 0 0]
  [0 0 0 0]
  [0 0 0 0]
 ]
 pdla> $z = zeroes ushort, 3,2 # Create ushort array
 [ushort() etc. with no arg returns a PDLA::Types token]

See also L<new_from_specification|/PDLA::new_from_specification>
for details on using piddles in the dimensions list.

=cut

sub zeroes { ref($_[0]) && ref($_[0]) ne 'PDLA::Type' ? PDLA::zeroes($_[0]) : PDLA->zeroes(@_) }
sub PDLA::zeroes {
    my $class = shift;
    my $pdl = scalar(@_)? $class->new_from_specification(@_) : $class->new_or_inplace;
    $pdl.=0;
    return $pdl;
}

# Create convenience aliases for zeroes

=head2 zeros

=for ref

construct a zero filled piddle (see zeroes for usage)

=cut

*zeros = \&zeroes;
*PDLA::zeros = \&PDLA::zeroes;

=head2 ones

=for ref

construct a one filled piddle

=for usage

 $a = ones([type], $nx, $ny, $nz,...);
 etc. (see 'zeroes')

=for example

 see zeroes() and add one

See also L<new_from_specification|/PDLA::new_from_specification>
for details on using piddles in the dimensions list.

=cut

sub ones { ref($_[0]) && ref($_[0]) ne 'PDLA::Type' ? PDLA::ones($_[0]) : PDLA->ones(@_) }
sub PDLA::ones {
    my $class = shift;
    my $pdl = scalar(@_)? $class->new_from_specification(@_) : $class->new_or_inplace;
    $pdl.=1;
    return $pdl;
}

=head2 reshape

=for ref

Change the shape (i.e. dimensions) of a piddle, preserving contents.

=for usage

 $x->reshape(NEWDIMS); reshape($x, NEWDIMS);

The data elements are preserved, obviously they will wrap
differently and get truncated if the new array is shorter.
If the new array is longer it will be zero-padded.

***Potential incompatibility with earlier versions of PDLA****
If the list of C<NEWDIMS> is empty C<reshape> will just drop
all dimensions of size 1 (preserving the number of elements):

  $a = sequence(3,4,5);
  $b = $a(1,3);
  $b->reshape();
  print $b->info;
 PDLA: Double D [5]

Dimensions of size 1 will also be dropped if C<reshape> is
invoked with the argument -1:

  $b = $a->reshape(-1);

As opposed to C<reshape> without arguments, C<reshape(-1)>
preserves dataflow:

  $a = ones(2,1,2);
  $b = $a(0)->reshape(-1);
  $b++;
  print $a;
 [
  [
   [2 1]
  ]
  [
   [2 1]
  ]
 ]

Important: Piddles are changed inplace!  

Note: If C<$x> is connected to any other PDLA (e.g. if it is a slice)
then the connection is first severed.

=for example

 pdla> $x = sequence(10)
 pdla> reshape $x,3,4; p $x
 [
  [0 1 2]
  [3 4 5]
  [6 7 8]
  [9 0 0]
 ]
 pdla> reshape $x,5; p $x
 [0 1 2 3 4]

=cut

*reshape = \&PDLA::reshape;
sub PDLA::reshape{
    if (@_ == 2 && $_[1] == -1) {  # a slicing reshape that drops 1-dims
	return $_[0]->slice( map { $_==1 ? [0,0,0] : [] } $_[0]->dims);
    }
    my $pdl = topdl($_[0]);
    $pdl->sever;
    my $nelem = $pdl->nelem;
    my @dims = grep defined, @_[1..$#_];
    for my $dim(@dims) { barf "reshape: invalid dim size '$dim'" if $dim < 0 }
    @dims = grep($_ != 1, $pdl->dims) if @dims == 0; # get rid of dims of size 1
    $pdl->setdims([@dims]);
    $pdl->upd_data;
    if ($pdl->nelem > $nelem) {
	my $tmp=$pdl->clump(-1)->slice("$nelem:-1");
	$tmp .= 0;
    }
    $_[0] = $pdl;
    return $pdl;
}

=head2 squeeze

=for ref

eliminate all singleton dimensions (dims of size 1)

=for example

 $b = $a(0,0)->squeeze;

Alias for C<reshape(-1)>. Removes all singleton dimensions
and preserves dataflow. A more concise interface is
provided by L<PDLA::NiceSlice|PDLA::NiceSlice> via modifiers:

 use PDLA::NiceSlice;
 $b = $a(0,0;-); # same as $a(0,0)->squeeze

=cut

*squeeze = \&PDLA::squeeze;
sub PDLA::squeeze { return $_[0]->reshape(-1) }

=head2 flat

=for ref

flatten a piddle (alias for C<< $pdl->clump(-1) >>)

=for example

  $srt = $pdl->flat->qsort;

Useful method to make a 1D piddle from an
arbitrarily sized input piddle. Data flows
back and forth as usual with slicing routines.
Falls through if argument already E<lt>= 1D.

=cut

*flat = \&PDLA::flat;
sub PDLA::flat { # fall through if < 2D
  return my $dummy = $_[0]->getndims != 1 ? $_[0]->clump(-1) : $_[0];
}

=head2 convert

=for ref

Generic datatype conversion function

=for usage

 $y = convert($x, $newtypenum);

=for example

 $y = convert $x, long
 $y = convert $x, ushort

C<$newtype> is a type B<number>, for convenience they are
returned by C<long()> etc when called without arguments.

=cut

# type to type conversion functions (with automatic conversion to pdl vars)

sub PDLA::convert {
  # we don't allow inplace conversion at the moment
  # (not sure what needs to be changed)
  barf 'Usage: $y = convert($x, $newtypenum)'."\n" if $#_!=1;
  my ($pdl,$type)= @_;
  $pdl = pdl($pdl) unless ref $pdl; # Allow normal numbers
  $type = $type->enum if ref($type) eq 'PDLA::Type';
  barf 'Usage: $y = convert($x, $newtypenum)'."\n" unless Scalar::Util::looks_like_number($type);
  return $pdl if $pdl->get_datatype == $type;
  # make_physical-call: temporary stopgap to work around core bug
  my $conv = $pdl->flowconvert($type)->make_physical->sever;
  return $conv;
}

=head2 Datatype_conversions

=for ref

byte|short|ushort|long|indx|longlong|float|double (shorthands to convert datatypes)

=for usage

 $y = double $x; $y = ushort [1..10];
 # all of the above listed shorthands behave similarly

When called with a piddle argument, they convert to the specific
datatype.

When called with a numeric, list, listref, or string argument they
construct a new piddle. This is a convenience to avoid having to be
long-winded and say C<$x = long(pdl(42))>

Thus one can say:

 $a = float(1,2,3,4);           # 1D
 $a = float q[1 2 3; 4 5 6];    # 2D
 $a = float([1,2,3],[4,5,6]);   # 2D
 $a = float([[1,2,3],[4,5,6]]); # 2D

Note the last three give identical results, and the last two are exactly
equivalent - a list is automatically converted to a list reference for
syntactic convenience. i.e. you can omit the outer C<[]>

When called with no arguments, these functions return a special type token.
This allows syntactical sugar like:

 $x = ones byte, 1000,1000;

This example creates a large piddle directly as byte datatype in
order to save memory.

In order to control how undefs are handled in converting from perl lists to
PDLAs, one can set the variable C<$PDLA::undefval>;
see the function L<pdl()|/pdl> for more details.

=for example

 pdla> p $x=sqrt float [1..10]
 [1 1.41421 1.73205 2 2.23607 2.44949 2.64575 2.82843 3 3.16228]
 pdla> p byte $x
 [1 1 1 2 2 2 2 2 3 3]

=head2 byte

Convert to byte datatype

=head2 short

Convert to short datatype

=head2 ushort

Convert to ushort datatype

=head2 long

Convert to long datatype

=head2 indx

Convert to indx datatype

=head2 longlong

Convert to longlong datatype

=head2 float

Convert to float datatype

=head2 double

Convert to double datatype

=head2 type

=for ref

return the type of a piddle as a blessed type object

A convenience function for use with the piddle constructors, e.g.

=for example

 $b = PDLA->zeroes($a->type,$a->dims,3);
 die "must be float" unless $a->type == float;

See also the discussion of the C<PDLA::Type> class in L<PDLA::Types>.
Note that the C<PDLA::Type> objects have overloaded comparison and
stringify operators so that you can compare and print types:

 $a = $a->float if $a->type < float;
 $t = $a->type; print "Type is $t\";

=cut

sub PDLA::type { return PDLA::Type->new($_[0]->get_datatype); }

##################### Printing ####################

# New string routine

$PDLA::_STRINGIZING = 0;

sub PDLA::string {
    my($self,$format)=@_;
    my $to_return = eval {
		if($PDLA::_STRINGIZING) {
			return "ALREADY_STRINGIZING_NO_LOOPS";
		}
		local $PDLA::_STRINGIZING = 1;
		my $ndims = $self->getndims;
		if($self->nelem > $PDLA::toolongtoprint) {
			return "TOO LONG TO PRINT";
		}
		if ($ndims==0) {
		if ( $self->badflag() and $self->isbad() ) {
			return "BAD";
		} else {
			my @x = $self->at();
			return ($format ? sprintf($format, $x[0]) : "$x[0]");
		}
		}
		return "Null" if $self->isnull;
		return "Empty[".join("x",$self->dims)."]" if $self->isempty; # Empty piddle
		local $sep  = $PDLA::use_commas ? "," : " ";
		local $sep2 = $PDLA::use_commas ? "," : "";
		if ($ndims==1) {
		   return str1D($self,$format);
		}
		else{
		   return strND($self,$format,0);
		}
	};
	if ($@) {
		# Remove reference to this line:
		$@ =~ s/\s*at .* line \d+\s*\.\n*/./;
		PDLA::Core::barf("Stringizing problem: $@");
	}
	return $to_return;
}

############## Section/subsection functions ###################

=head2 list

=for ref

Convert piddle to perl list

=for usage

 @tmp = list $x;

Obviously this is grossly inefficient for the large datasets PDLA is designed to
handle. This was provided as a get out while PDLA matured. It  should now be mostly
superseded by superior constructs, such as PP/threading. However it is still
occasionally useful and is provied for backwards compatibility.

=for example

 for (list $x) {
   # Do something on each value...
 }

If you compile PDLA with bad value support (the default), your machine's
docs will also say this:

=for bad

list converts any bad values into the string 'BAD'.

=cut

# No threading, just the ordinary dims.
sub PDLA::list{ # pdl -> @list
     barf 'Usage: list($pdl)' if $#_!=0;
     my $pdl = PDLA->topdl(shift);
     return () if nelem($pdl)==0;
     @{listref_c($pdl)};
}

=head2 unpdl

=for ref

Convert piddle to nested Perl array references

=for usage

 $arrayref = unpdl $x;

This function returns a reference to a Perl list-of-lists structure
equivalent to the input piddle (within the limitation that while values
of elements should be preserved, the detailed datatypes will not as
perl itself basically has "number" data rather than byte, short, int...
E.g., C<< sum($x - pdl( $x->unpdl )) >> should equal 0.

Obviously this is grossly inefficient in memory and processing for the
large datasets PDLA is designed to handle. Sometimes, however, you really
want to move your data back to Perl, and with proper dimensionality,
unlike C<list>.

=for example

 use JSON;
 my $json = encode_json unpdl $pdl;

If you compile PDLA with bad value support (the default), your machine's
docs will also say this:

=cut

=for bad

unpdl converts any bad values into the string 'BAD'.

=cut

sub PDLA::unpdl {
    barf 'Usage: unpdl($pdl)' if $#_ != 0;
    my $pdl = PDLA->topdl(shift);
    return [] if $pdl->nelem == 0;
    return _unpdl_int($pdl);
}

sub _unpdl_int {
    my $pdl = shift;
    if ($pdl->ndims > 1) {
        return [ map { _unpdl_int($_) } dog $pdl ];
    } else {
        return listref_c($pdl);
    }
}

=head2 listindices

=for ref

Convert piddle indices to perl list

=for usage

 @tmp = listindices $x;

C<@tmp> now contains the values C<0..nelem($x)>.

Obviously this is grossly inefficient for the large datasets PDLA is designed to
handle. This was provided as a get out while PDLA matured. It  should now be mostly
superseded by superior constructs, such as PP/threading. However it is still
occasionally useful and is provied for backwards compatibility.

=for example

 for $i (listindices $x) {
   # Do something on each value...
 }

=cut

sub PDLA::listindices{ # Return list of index values for 1D pdl
     barf 'Usage: list($pdl)' if $#_!=0;
     my $pdl = shift;
     return () if nelem($pdl)==0;
     barf 'Not 1D' if scalar(dims($pdl)) != 1;
     return (0..nelem($pdl)-1);
}

=head2 set

=for ref

Set a single value inside a piddle

=for usage

 set $piddle, @position, $value

C<@position> is a coordinate list, of size equal to the
number of dimensions in the piddle. Occasionally useful,
mainly provided for backwards compatibility as superseded
by use of L<slice|PDLA::Slices/slice> and assignment operator C<.=>.

=for example

 pdla> $x = sequence 3,4
 pdla> set $x, 2,1,99
 pdla> p $x
 [
  [ 0  1  2]
  [ 3  4 99]
  [ 6  7  8]
  [ 9 10 11]
 ]

=cut

sub PDLA::set{    # Sets a particular single value
    barf 'Usage: set($pdl, $x, $y,.., $value)' if $#_<2;
    my $self  = shift; my $value = pop @_;
    set_c ($self, [@_], $value);
    return $self;
}

=head2 at

=for ref

Returns a single value inside a piddle as perl scalar.

=for usage

 $z = at($piddle, @position); $z=$piddle->at(@position);

C<@position> is a coordinate list, of size equal to the
number of dimensions in the piddle. Occasionally useful
in a general context, quite useful too inside PDLA internals.

=for example

 pdla> $x = sequence 3,4
 pdla> p $x->at(1,2)
 7

If you compile PDLA with bad value support (the default), your machine's
docs will also say this:

=for bad

at converts any bad values into the string 'BAD'.

=cut

sub PDLA::at {     # Return value at ($x,$y,$z...)
    barf 'Usage: at($pdl, $x, $y, ...)' if $#_<0;
    my $self = shift;
    at_bad_c ($self, [@_]);
}

=head2 sclr

=for ref

return a single value from a piddle as a scalar

=for example

  $val = $a(10)->sclr;
  $val = sclr inner($a,$b);

The C<sclr> method is useful to turn a piddle into a normal Perl
scalar. Its main advantage over using C<at> for this purpose is the fact
that you do not need to worry if the piddle is 0D, 1D or higher dimensional.
Using C<at> you have to supply the correct number of zeroes, e.g.

  $a = sequence(10);
  $b = $a->slice('4');
  print $b->sclr; # no problem
  print $b->at(); # error: needs at least one zero

C<sclr> is generally used when a Perl scalar is required instead
of a one-element piddle. If the input is a multielement piddle
the first value is returned as a Perl scalar. You can optionally
switch on checks to ensure that the input piddle has only one element:

  PDLA->sclr({Check => 'warn'}); # carp if called with multi-el pdls
  PDLA->sclr({Check => 'barf'}); # croak if called with multi-el pdls

are the commands to switch on warnings or raise an error if
a multielement piddle is passed as input. Note that these options
can only be set when C<sclr> is called as a class method (see
example above). Use

  PDLA->sclr({Check=>0});

to switch these checks off again (default setting);
When called as a class method the resulting check mode is returned
(0: no checking, 1: warn, 2: barf).

=cut

my $chkmode = 0; # default mode no checks
use PDLA::Options;
sub PDLA::sclr {
  my $this = shift;
  if (ref $this) { # instance method
    carp "multielement piddle in 'sclr' call"
      if ($chkmode == 1 && $this->nelem > 1);
    croak "multielement piddle in 'sclr' call"
      if ($chkmode == 2 && $this->nelem > 1);
    return sclr_c($this);
  } else {  # class method
    my $check = (iparse({Check=>0},ifhref($_[0])))[1];
    if (lc($check) eq 'warn') {$chkmode = 1}
    elsif (lc($check) eq 'barf') {$chkmode = 2}
    else {$chkmode = $check != 0 ? 1 : 0}
    return $chkmode;
  }
}

=head2 cat

=for ref

concatenate piddles to N+1 dimensional piddle

Takes a list of N piddles of same shape as argument,
returns a single piddle of dimension N+1.

=for example

 pdla> $x = cat ones(3,3),zeroes(3,3),rvals(3,3); p $x
 [
  [
   [1 1 1]
   [1 1 1]
   [1 1 1]
  ]
  [
   [0 0 0]
   [0 0 0]
   [0 0 0]
  ]
  [
   [1 1 1]
   [1 0 1]
   [1 1 1]
  ]
 ]

If you compile PDLA with bad value support (the default), your machine's
docs will also say this:

=for bad

The output piddle is set bad if any input piddles have their bad flag set.

Similar functions include L<append|PDLA::Primitive/append>, which
appends only two piddles along their first dimension, and
L<glue|PDLA::Primitive/glue>, which can append more than two piddles
along an arbitary dimension.

Also consider the generic constructor L<pdl|pdl>, which can handle
piddles of different sizes (with zero-padding), and will return a
piddle of type 'double' by default, but may be considerably faster (up
to 10x) than cat.

=cut

sub PDLA::cat {
	my $res;
	my $old_err = $@;
	$@ = '';
	eval {
		$res = $_[0]->initialize;
		$res->set_datatype((sort {$b<=>$a} map{$_->get_datatype} @_)[0] );

		my @resdims = $_[0]->dims;
		for my $i(0..$#_){
		    my @d = $_[$i]->dims;
		    for my $j(0..$#d) {
			$resdims[$j] = $d[$j] if( !defined($resdims[$j]) or $resdims[$j]==1 );
			die "mismatched dims\n" if($d[$j] != 1 and $resdims[$j] != $d[$j]);
		    }
		}
		$res->setdims( [@resdims,scalar(@_) ]);
		my ($i,$t); my $s = ":,"x@resdims;
		for (@_) { $t = $res->slice($s."(".$i++.")"); $t .= $_}

		# propagate any bad flags
		for (@_) { if ( $_->badflag() ) { $res->badflag(1); last; } }
	};
	if ($@ eq '') {
		# Restore the old error and return
		$@ = $old_err;
		return $res;
	}

	# If we've gotten here, then there's been an error, so check things
	# and barf out a meaningful message.

	if  ($@ =~ /PDLA::Ops::assgn|mismatched/
	  or $@ =~ /"badflag"/
	  or $@ =~ /"initialize"/) {
		my (@mismatched_dims, @not_a_piddle);
		my $i = 0;

		# non-piddles and/or dimension mismatch.  The first argument is
		# ok unless we have the "initialize" error:
		if ($@ =~ /"initialize"/) {
			# Handle the special case that there are *no* args passed:
			barf("Called PDLA::cat without any arguments") unless @_;

			while ($i < @_ and not eval{ $_[$i]->isa('PDLA')}) {
				push (@not_a_piddle, $i);
				$i++;
			}
		}

		# Get the dimensions of the first actual piddle in the argument
		# list:
		my $first_piddle_argument = $i;
		my @dims = $_[$i]->dims if ref($_[$i]) =~ /PDLA/;

		# Figure out all the ways that the caller screwed up:
		while ($i < @_) {
			my $arg = $_[$i];
			# Check if not a piddle
			if (not eval{$arg->isa('PDLA')}) {
				push @not_a_piddle, $i;
			}
			# Check if different number of dimensions
			elsif (@dims != $arg->ndims) {
				push @mismatched_dims, $i;
			}
			# Check if size of dimensions agree
			else {
				DIMENSION: for (my $j = 0; $j < @dims; $j++) {
					if ($dims[$j] != $arg->dim($j)) {
						push @mismatched_dims, $i;
						last DIMENSION;
					}
				}
			}
			$i++;
		}

		# Construct a message detailing the results
		my $message = "bad arguments passed to function PDLA::cat\n";
		if (@mismatched_dims > 1) {
			# Many dimension mismatches
			$message .= "The dimensions of arguments "
						. join(', ', @mismatched_dims[0 .. $#mismatched_dims-1])
						. " and $mismatched_dims[-1] do not match the\n"
						. "   dimensions of the first piddle argument (argument $first_piddle_argument).\n";
		}
		elsif (@mismatched_dims) {
			# One dimension mismatch
			$message .= "The dimensions of argument $mismatched_dims[0] do not match the\n"
						. "   dimensions of the first piddle argument (argument $first_piddle_argument).\n";
		}
		if (@not_a_piddle > 1) {
			# many non-piddles
			$message .= "Arguments " . join(', ', @not_a_piddle[0 .. $#not_a_piddle-1])
						. " and $not_a_piddle[-1] are not piddles.\n";
		}
		elsif (@not_a_piddle) {
			# one non-piddle
			$message .= "Argument $not_a_piddle[0] is not a piddle.\n";
		}

		# Handle the edge case that something else happened:
		if (@not_a_piddle == 0 and @mismatched_dims == 0) {
			barf("cat: unknown error from the internals:\n$@");
		}

		$message .= "(Argument counting starts from zero.)";
		croak($message);
	}
	else {
		croak("cat: unknown error from the internals:\n$@");
	}
}

=head2 dog

=for ref

Opposite of 'cat' :). Split N dim piddle to list of N-1 dim piddles

Takes a single N-dimensional piddle and splits it into a list of N-1 dimensional
piddles. The breakup is done along the last dimension.
Note the dataflown connection is still preserved by default,
e.g.:

=for example

 pdla> $p = ones 3,3,3
 pdla> ($a,$b,$c) = dog $p
 pdla> $b++; p $p
 [
  [
   [1 1 1]
   [1 1 1]
   [1 1 1]
  ]
  [
   [2 2 2]
   [2 2 2]
   [2 2 2]
  ]
  [
   [1 1 1]
   [1 1 1]
   [1 1 1]
  ]
 ]

=for options

 Break => 1   Break dataflow connection (new copy)

If you compile PDLA with bad value support (the default), your machine's
docs will also say this:

=for bad

The output piddles are set bad if the original piddle has its bad flag set.

=cut

sub PDLA::dog {
  my $opt = pop @_ if ref($_[-1]) eq 'HASH';
  my $p = shift;
  my @res; my $s = ":,"x($p->getndims-1);
  for my $i (0..$p->getdim($p->getndims-1)-1) {
     $res[$i] = $p->slice($s."(".$i.")");
     $res[$i] = $res[$i]->copy if $$opt{Break};
     $i++;
  }
  return @res;
}

###################### Misc internal routines ####################

# Recursively pack an N-D array ref in format [[1,1,2],[2,2,3],[2,2,2]] etc
# package vars $level and @dims must be initialised first.

sub rpack {
    my ($ptype,$a) = @_;  my ($ret,$type);

    $ret = "";
    if (ref($a) eq "ARRAY") {

       if (defined($dims[$level])) {
           barf 'Array is not rectangular' unless $dims[$level] == scalar(@$a);
       }else{
          $dims[$level] = scalar(@$a);
       }

       $type = ref($$a[0]);
        if ($type) {
        $level++;
        for(@$a) {
            barf 'Array is not rectangular' unless $type eq ref($_); # Equal types
            $ret .= rpack($ptype,$_);
        }
        $level--;
        } else {
        # These are leaf nodes
        $ret = pack $ptype, map {defined($_) ? $_ : $PDLA::undefval} @$a;
      }
    } elsif (ref($a) eq "PDLA") {
	barf 'Cannot make a new piddle from two or more piddles, try "cat"';
    } else {
        barf "Don't know how to make a PDLA object from passed argument";
    }
    return $ret;
}

sub rcopyitem {        # Return a deep copy of an item - recursively
    my $x = shift;
    my ($y, $key, $value);
    if (ref(\$x) eq "SCALAR") {
       return $x;
    }elsif (ref($x) eq "SCALAR") {
       $y = $$x; return \$y;
    }elsif (ref($x) eq "ARRAY") {
       $y = [];
       for (@$x) {
           push @$y, rcopyitem($_);
       }
       return $y;
    }elsif (ref($x) eq "HASH") {
       $y={};
       while (($key,$value) = each %$x) {
          $$y{$key} = rcopyitem($value);
       }
       return $y;
    }elsif (blessed($x)) {
       return $x->copy;
    }else{
       barf ('Deep copy of object failed - unknown component with type '.ref($x));
    }
0;}

# N-D array stringifier

sub strND {
    my($self,$format,$level)=@_;
#    $self->make_physical();
    my @dims = $self->dims;
    # print "STRND, $#dims\n";

    if ($#dims==1) { # Return 2D string
       return str2D($self,$format,$level);
    }
    else { # Return list of (N-1)D strings
       my $secbas = join '',map {":,"} @dims[0..$#dims-1];
       my $ret="\n"." "x$level ."["; my $j;
       for ($j=0; $j<$dims[$#dims]; $j++) {
       	   my $sec = $secbas . "($j)";
#	   print "SLICE: $sec\n";

           $ret .= strND($self->slice($sec),$format, $level+1);
	   chop $ret; $ret .= $sep2;
       }
       chop $ret if $PDLA::use_commas;
       $ret .= "\n" ." "x$level ."]\n";
       return $ret;
    }
}


# String 1D array in nice format

sub str1D {
    my($self,$format)=@_;
    barf "Not 1D" if $self->getndims()!=1;
    my $x = listref_c($self);
    my ($ret,$dformat,$t);
    $ret = "[";
    my $dtype = $self->get_datatype();
    $dformat = $PDLA::floatformat  if $dtype == $PDLA_F;
    $dformat = $PDLA::doubleformat if $dtype == $PDLA_D;
    $dformat = $PDLA::indxformat if $dtype == $PDLA_IND;

    my $badflag = $self->badflag();
    for $t (@$x) {
	if ( $badflag and $t eq "BAD" ) {
	    # do nothing
        } elsif ($format) {
	  $t = sprintf $format,$t;
	} else{ # Default
	    if ($dformat && length($t)>7) { # Try smaller
		$t = sprintf $dformat,$t;
	    }
	}
       $ret .= $t.$sep;
    }

    chop $ret; $ret.="]";
    return $ret;
}

# String 2D array in nice uniform format

sub str2D{
    my($self,$format,$level)=@_;
#    print "STR2D:\n"; $self->printdims();
    my @dims = $self->dims();
    barf "Not 2D" if scalar(@dims)!=2;
    my $x = listref_c($self);
    my ($i, $f, $t, $len, $ret);

    my $dtype = $self->get_datatype();
    my $badflag = $self->badflag();

    my $findmax = 1;
    if (!defined $format || $format eq "") {
	# Format not given? - find max length of default
	$len=0;

	if ( $badflag ) {
	    for (@$x) {
		if ( $_ eq "BAD" ) { $i = 3; }
		else               { $i = length($_); }
		$len = $i>$len ? $i : $len;
	    }
	} else {
	    for (@$x) {$i = length($_); $len = $i>$len ? $i : $len };
	}

	$format = "%".$len."s";

	if ($len>7) { # Too long? - perhaps try smaller format
	    if ($dtype == $PDLA_F) {
		$format = $PDLA::floatformat;
	    } elsif ($dtype == $PDLA_D) {
		$format = $PDLA::doubleformat;
	    } elsif ($dtype == $PDLA_IND) {
		$format = $PDLA::indxformat;
	    } else {
		# Stick with default
		$findmax = 0;
	    }
	}
	else {
	    # Default ok
	    $findmax = 0;
	}
    }

    if($findmax) {
	# Find max length of strings in final format
	$len=0;

	if ( $badflag ) {
	    for (@$x) {
		if ( $_ eq "BAD" ) { $i = 3; }
		else               { $i = length(sprintf $format,$_); }
		$len = $i>$len ? $i : $len;
	    }
	} else {
	    for (@$x) {
		$i = length(sprintf $format,$_); $len = $i>$len ? $i : $len;
	    }
	}
    } # if: $findmax

    $ret = "\n" . " "x$level . "[\n";
    {
	my $level = $level+1;
	$ret .= " "x$level ."[";
	for ($i=0; $i<=$#$x; $i++) {

	    if ( $badflag and $$x[$i] eq "BAD" ) {
		$f = "BAD";
	    } else {
		$f = sprintf $format,$$x[$i];
	    }

	    $t = $len-length($f); $f = " "x$t .$f if $t>0;
	    $ret .= $f;
	    if (($i+1)%$dims[0]) {
		$ret.=$sep;
	    }
	    else{ # End of output line
		$ret.="]";
		if ($i==$#$x) { # very last number
		    $ret.="\n";
		}
		else{
		    $ret.= $sep2."\n" . " "x$level ."[";
		}
	    }
	}
    }
    $ret .= " "x$level."]\n";
    return $ret;
}

#
# Sleazy hcpy saves me time typing
#
sub PDLA::hcpy {
  $_[0]->hdrcpy($_[1]);
  $_[0];
}

########## Docs for functions in Core.xs ##################
# Pod docs for functions that are imported from Core.xs and are
#  not documented elsewhere. Currently this is not a complete
#  list. There are others.

=head2 gethdr

=for ref

Retrieve header information from a piddle

=for example

 $pdl=rfits('file.fits');
 $h=$pdl->gethdr;
 print "Number of pixels in the X-direction=$$h{NAXIS1}\n";

The C<gethdr> function retrieves whatever header information is contained
within a piddle. The header can be set with L<sethdr|/sethdr> and is always a
hash reference or undef.

C<gethdr> returns undef if the piddle has not yet had a header
defined; compare with C<hdr> and C<fhdr>, which are guaranteed to return a
defined value.

Note that gethdr() works by B<reference>: you can modify the header
in-place once it has been retrieved:

  $a  = rfits($filename);
  $ah = $a->gethdr();
  $ah->{FILENAME} = $filename;

It is also important to realise that in most cases the header is not
automatically copied when you copy the piddle.  See L<hdrcpy|/hdrcpy>
to enable automatic header copying.

Here's another example: a wrapper around rcols that allows your piddle
to remember the file it was read from and the columns could be easily
written (here assuming that no regexp is needed, extensions are left
as an exercise for the reader)

 sub ext_rcols {
    my ($file, @columns)=@_;
    my $header={};
    $$header{File}=$file;
    $$header{Columns}=\@columns;

    @piddles=rcols $file, @columns;
    foreach (@piddles) { $_->sethdr($header); }
    return @piddles;
 }

=head2 hdr

=for ref

Retrieve or set header information from a piddle

=for example

 $pdl->hdr->{CDELT1} = 1;

The C<hdr> function allows convenient access to the header of a
piddle.  Unlike C<gethdr> it is guaranteed to return a defined value,
so you can use it in a hash dereference as in the example.  If the
header does not yet exist, it gets autogenerated as an empty hash.

Note that this is usually -- but not always -- What You Want.  If you
want to use a tied L<Astro::FITS::Header|Astro::FITS::Header> hash,
for example, you should either construct it yourself and use C<sethdr>
to put it into the piddle, or use L<fhdr|fhdr> instead.  (Note that
you should be able to write out the FITS file successfully regardless
of whether your PDLA has a tied FITS header object or a vanilla hash).

=head2 fhdr

=for ref

Retrieve or set FITS header information from a piddle

=for example

 $pdl->fhdr->{CDELT1} = 1;

The C<fhdr> function allows convenient access to the header of a
piddle.  Unlike C<gethdr> it is guaranteed to return a defined value,
so you can use it in a hash dereference as in the example.  If the
header does not yet exist, it gets autogenerated as a tied
L<Astro::FITS::Header|Astro::FITS::Header> hash.

Astro::FITS::Header tied hashes are better at matching the behavior of
FITS headers than are regular hashes.  In particular, the hash keys
are CAsE INsEnSItiVE, unlike normal hash keys.  See
L<Astro::FITS::Header> for details.

If you do not have Astro::FITS::Header installed, you get back a
normal hash instead of a tied object.

=head2 sethdr

=for ref

Set header information of a piddle

=for example

 $pdl = zeroes(100,100);
 $h = {NAXIS=>2, NAXIS1=>100, NAXIS=>100, COMMENT=>"Sample FITS-style header"};
 # add a FILENAME field to the header
 $$h{FILENAME} = 'file.fits';
 $pdl->sethdr( $h );

The C<sethdr> function sets the header information for a piddle.
You must feed in a hash ref or undef, and the header field of the PDLA is
set to be a new ref to the same hash (or undefined).

The hash ref requirement is a speed bump put in place since the normal
use of headers is to store fits header information and the like.  Of course,
if you want you can hang whatever ugly old data structure you want off
of the header, but that makes life more complex.

Remember that the hash is not copied -- the header is made into a ref
that points to the same underlying data.  To get a real copy without
making any assumptions about the underlying data structure, you
can use one of the following:

  use PDLA::IO::Dumper;
  $pdl->sethdr( deep_copy($h) );

(which is slow but general), or

  $pdl->sethdr( PDLA::_hdr_copy($h) )

(which uses the built-in sleazy deep copier), or (if you know that all
the elements happen to be scalars):

  { my %a = %$h;
    $pdl->sethdr(\%a);
  }

which is considerably faster but just copies the top level.

The C<sethdr> function must be given a hash reference or undef.  For
further information on the header, see L<gethdr|/gethdr>, L<hdr|/hdr>,
L<fhdr|/fhdr> and L<hdrcpy|/hdrcpy>.

=head2 hdrcpy

=for ref

switch on/off/examine automatic header copying

=for example

 print "hdrs will be copied" if $a->hdrcpy;
 $a->hdrcpy(1);       # switch on automatic header copying
 $b = $a->sumover;    # and $b will inherit $a's hdr
 $a->hdrcpy(0);       # and now make $a non-infectious again

C<hdrcpy> without an argument just returns the current setting of the
flag.  See also "hcpy" which returns its PDLA argument (and so is useful
in method-call pipelines).

Normally, the optional header of a piddle is not copied automatically
in pdl operations. Switching on the hdrcpy flag using the C<hdrcpy>
method will enable automatic hdr copying. Note that an actual deep
copy gets made, which is rather processor-inefficient -- so avoid
using header copying in tight loops!

Most PDLAs have the C<hdrcpy> flag cleared by default; however, some
routines (notably L<rfits|PDLA::IO::FITS/rfits()>) set it by default
where that makes more sense.

The C<hdrcpy> flag is viral: if you set it for a PDLA, then derived
PDLAs will get copies of the header and will also have their C<hdrcpy>
flags set.  For example:

  $a = xvals(50,50);
  $a->hdrcpy(1);
  $a->hdr->{FOO} = "bar";
  $b = $a++;
  $c = $b++;
  print $b->hdr->{FOO}, " - ", $c->hdr->{FOO}, "\n";
  $b->hdr->{FOO} = "baz";
  print $a->hdr->{FOO}, " - ", $b->hdr->{FOO}, " - ", $c->hdr->{FOO}, "\n";

will print:

  bar - bar
  bar - baz - bar

Performing an operation in which more than one PDLA has its hdrcpy flag
causes the resulting PDLA to take the header of the first PDLA:

  ($a,$b) = sequence(5,2)->dog;
  $a->hdrcpy(1); $b->hdrcpy(1);
  $a->hdr->{foo} = 'a';
  $b->hdr->{foo} = 'b';
  print (($a+$b)->hdr->{foo} , ($b+$a)->hdr->{foo});

will print:

  a b

=head2 hcpy

=for ref

Switch on/off automatic header copying, with PDLA pass-through

=for example

  $a = rfits('foo.fits')->hcpy(0);
  $a = rfits('foo.fits')->hcpy(1);

C<hcpy> sets or clears the hdrcpy flag of a PDLA, and returns the PDLA
itself.  That makes it convenient for inline use in expressions.

=head2 set_autopthread_targ

=for ref

Set the target number of processor threads (pthreads) for multi-threaded processing.

=for usage

 set_autopthread_targ($num_pthreads);

C<$num_pthreads> is the target number of pthreads the auto-pthread process will try to achieve.

See L<PDLA::ParallelCPU> for an overview of the auto-pthread process.

=for example

  # Example turning on auto-pthreading for a target of 2 pthreads and for functions involving
  #   PDLAs with greater than 1M elements
  set_autopthread_targ(2);
  set_autopthread_size(1);

  # Execute a pdl function, processing will split into two pthreads as long as
  #  one of the pdl-threaded dimensions is divisible by 2.
  $a = minimum($b);

  # Get the actual number of pthreads that were run.
  $actual_pthread = get_autopthread_actual();

=cut

*set_autopthread_targ       = \&PDLA::set_autopthread_targ;

=head2 get_autopthread_targ

=for ref

Get the current target number of processor threads (pthreads) for multi-threaded processing.

=for usage

 $num_pthreads = get_autopthread_targ();

C<$num_pthreads> is the target number of pthreads the auto-pthread process will try to achieve.

See L<PDLA::ParallelCPU> for an overview of the auto-pthread process.

=cut

*get_autopthread_targ       = \&PDLA::get_autopthread_targ;

=head2 get_autopthread_actual

=for ref

Get the actual number of pthreads executed for the last pdl processing function.

=for usage

 $autopthread_actual = get_autopthread_actual();

C<$autopthread_actual> is the actual number of pthreads executed for the last pdl processing function.

See L<PDLA::ParallelCPU> for an overview of the auto-pthread process.

=cut

*get_autopthread_actual      = \&PDLA::get_autopthread_actual;

=head2 set_autopthread_size

=for ref

Set the minimum size (in M-elements or 2^20 elements) of the largest PDLA involved in a function where auto-pthreading will
be performed. For small PDLAs, it probably isn't worth starting multiple pthreads, so this function
is used to define a minimum threshold where auto-pthreading won't be attempted.

=for usage

 set_autopthread_size($size);

C<$size> is the mimumum size, in M-elements or 2^20 elements (approx 1e6 elements) for the largest PDLA involved in a function.

See L<PDLA::ParallelCPU> for an overview of the auto-pthread process.

=for example

  # Example turning on auto-pthreading for a target of 2 pthreads and for functions involving
  #   PDLAs with greater than 1M elements
  set_autopthread_targ(2);
  set_autopthread_size(1);

  # Execute a pdl function, processing will split into two pthreads as long as
  #  one of the pdl-threaded dimensions is divisible by 2.
  $a = minimum($b);

  # Get the actual number of pthreads that were run.
  $actual_pthread = get_autopthread_actual();

=cut

*set_autopthread_size       = \&PDLA::set_autopthread_size;

=head2 get_autopthread_size

=for ref

Get the current autopthread_size setting.

=for usage

 $autopthread_size = get_autopthread_size();

C<$autopthread_size> is the mimumum size limit for auto_pthreading to occur, in M-elements or 2^20 elements (approx 1e6 elements) for the largest PDLA involved in a function

See L<PDLA::ParallelCPU> for an overview of the auto-pthread process.

=cut

*get_autopthread_size       = \&PDLA::get_autopthread_size;

=head1 AUTHOR

Copyright (C) Karl Glazebrook (kgb@aaoepp.aao.gov.au),
Tuomas J. Lukka, (lukka@husc.harvard.edu) and Christian
Soeller (c.soeller@auckland.ac.nz) 1997.
Modified, Craig DeForest (deforest@boulder.swri.edu) 2002.
All rights reserved. There is no warranty. You are allowed
to redistribute this software / documentation under certain
conditions. For details, see the file COPYING in the PDLA
distribution. If this file is separated from the PDLA distribution,
the copyright notice should be included in the file.

=cut

#
# Easier to implement in perl than in XS...
#   -- CED
#

sub PDLA::fhdr {
    my $pdl = shift;

    return $pdl->hdr
	if( (defined $pdl->gethdr) ||
	!defined $Astro::FITS::Header::VERSION
	    );

    # Avoid bug in 1.15 and earlier Astro::FITS::Header
    my @hdr = ("SIMPLE  =                    T");
    my $hdr = new Astro::FITS::Header(Cards=>\@hdr);
    tie my %hdr, "Astro::FITS::Header", $hdr;
    $pdl->sethdr(\%hdr);
    return \%hdr;
}

use Fcntl;

BEGIN {
   eval 'use File::Map 0.47 qw(:all)';
   if ($@) {
      carp "No File::Map found, using legacy mmap (if available)\n" if $PDLA::verbose;
      sub sys_map;
      sub PROT_READ();
      sub PROT_WRITE();
      sub MAP_SHARED();
      sub MAP_PRIVATE();
   }
}

# Implement File::Map::sys_map bug fix.  Also, might be possible
# to implement without so many external (non-Core perl) modules.
#
# sub pdl_do_sys_map {
#         my (undef, $length, $protection, $flags, $fh, $offset) = @_;
#         my $utf8 = File::Map::_check_layers($fh);
#         my $fd = ($flags & MAP_ANONYMOUS) ? (-1) : fileno($fh);
#         $offset ||= 0;
#         File::Map::_mmap_impl($_[0], $length, $protection, $flags, $fd, $offset, $utf8);
#         return;
# }

sub PDLA::set_data_by_file_map {
   my ($pdl,$name,$len,$shared,$writable,$creat,$mode,$trunc) = @_;
   my $pdl_dataref = $pdl->get_dataref();

   # Assume we have no data to free for now
   # pdl_freedata($pdl);

   sysopen(my $fh, $name, ($writable && $shared ? O_RDWR : O_RDONLY) | ($creat ? O_CREAT : 0), $mode)
      or die "Error opening file '$name'\n";

   binmode $fh;

   if ($trunc) {
      truncate($fh,0) or die "set_data_by_mmap: truncate('$name',0) failed, $!";
      truncate($fh,$len) or die "set_data_by_mmap: truncate('$name',$len) failed, $!";
   }

   if ($len) {

      #eval {
      # pdl_do_sys_map(  # will croak if the mapping fails
      if ($PDLA::debug) {
         printf STDERR
         "set_data_by_file_map: calling sys_map(%s,%d,%d,%d,%s,%d)\n",
         $pdl_dataref,
         $len,
         PROT_READ | ($writable ?  PROT_WRITE : 0),
         ($shared ? MAP_SHARED : MAP_PRIVATE),
         $fh,
         0;
      }

      sys_map(  # will croak if the mapping fails
         ${$pdl_dataref},
         $len,
         PROT_READ | ($writable ?  PROT_WRITE : 0),
         ($shared ? MAP_SHARED : MAP_PRIVATE),
         $fh,
         0
      );
      #};

         #if ($@) {
         #die("Error mmapping!, '$@'\n");
         #}

      $pdl->upd_data;

      if ($PDLA::debug) {
         printf STDERR "set_data_by_file_map: length \${\$pdl_dataref} is %d.\n", length ${$pdl_dataref};
      }
      $pdl->set_state_and_add_deletedata_magic( length ${$pdl_dataref} );

   } else {

      #  Special case: zero-length file
      $_[0] = undef;
   }

   # PDLADEBUG_f(printf("PDLA::MMap: mapped to %p\n",$pdl->data));
   close $fh ;
}

1;
