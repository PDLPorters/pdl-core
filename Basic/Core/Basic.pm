
=head1 NAME

PDLA::Basic -- Basic utility functions for PDLA

=head1 DESCRIPTION

This module contains basic utility functions for
creating and manipulating piddles. Most of these functions
are simplified interfaces to the more flexible functions in
the modules 
L<PDLA::Primitive|PDLA::Primitive> 
and 
L<PDLA::Slices|PDLA::Slices>.

=head1 SYNOPSIS

 use PDLA::Basic;

=head1 FUNCTIONS

=cut

package PDLA::Basic;
use PDLA::Core '';
use PDLA::Types;
use PDLA::Exporter;
use PDLA::Options;

@ISA=qw/PDLA::Exporter/;
@EXPORT_OK = qw/ ndcoords rvals axisvals allaxisvals xvals yvals zvals sec ins hist whist
	similar_assign transpose sequence xlinvals ylinvals
	zlinvals axislinvals/;
%EXPORT_TAGS = (Func=>[@EXPORT_OK]);

# Exportable functions
*axisvals       = \&PDLA::axisvals;		
*allaxisvals       = \&PDLA::allaxisvals;		
*sec            = \&PDLA::sec;		
*ins            = \&PDLA::ins;		
*hist           = \&PDLA::hist;		
*whist           = \&PDLA::whist;		
*similar_assign = \&PDLA::similar_assign;
*transpose      = \&PDLA::transpose;
*xlinvals 	= \&PDLA::xlinvals;
*ylinvals 	= \&PDLA::ylinvals;
*zlinvals 	= \&PDLA::zlinvals;

=head2 xvals

=for ref

Fills a piddle with X index values.  Uses similar specifications to
L<zeroes|zeroes> and L<new_from_specification|new_from_specification>.

CAVEAT: 

If you use the single argument piddle form (top row
in the usage table) the output will have the same type as the input;
this may give surprising results if, e.g., you have a byte array with
a dimension of size greater than 256.  To force a type, use the third form.

=for usage

 $x = xvals($somearray);
 $x = xvals([OPTIONAL TYPE],$nx,$ny,$nz...);
 $x = xvals([OPTIONAL TYPE], $somarray->dims);

etc. see L<zeroes|PDLA::Core/zeroes>.

=for example

  pdla> print xvals zeroes(5,10)
  [
   [0 1 2 3 4]
   [0 1 2 3 4]
   [0 1 2 3 4]
   [0 1 2 3 4]
   [0 1 2 3 4]
   [0 1 2 3 4]
   [0 1 2 3 4]
   [0 1 2 3 4]
   [0 1 2 3 4]
   [0 1 2 3 4]
  ]

=head2 yvals

=for ref

Fills a piddle with Y index values.  See the CAVEAT for L<xvals|xvals>.

=for usage

 $x = yvals($somearray); yvals(inplace($somearray));
 $x = yvals([OPTIONAL TYPE],$nx,$ny,$nz...);

etc. see L<zeroes|PDLA::Core/zeroes>.

=for example

 pdla> print yvals zeroes(5,10)
 [
  [0 0 0 0 0]
  [1 1 1 1 1]
  [2 2 2 2 2]
  [3 3 3 3 3]
  [4 4 4 4 4]
  [5 5 5 5 5]
  [6 6 6 6 6]
  [7 7 7 7 7]
  [8 8 8 8 8]
  [9 9 9 9 9]
 ]

=head2 zvals

=for ref

Fills a piddle with Z index values.  See the CAVEAT for L<xvals|xvals>.

=for usage

 $x = zvals($somearray); zvals(inplace($somearray));
 $x = zvals([OPTIONAL TYPE],$nx,$ny,$nz...);

etc. see L<zeroes|PDLA::Core/zeroes>.

=for example

 pdla> print zvals zeroes(3,4,2)
 [
  [
   [0 0 0]
   [0 0 0]
   [0 0 0]
   [0 0 0]
  ]
  [
   [1 1 1]
   [1 1 1]
   [1 1 1]
   [1 1 1]
  ]
 ]

=head2 xlinvals

=for ref

X axis values between endpoints (see L<xvals|/xvals>).

=for usage

 $a = zeroes(100,100);
 $x = $a->xlinvals(0.5,1.5);
 $y = $a->ylinvals(-2,-1);
 # calculate Z for X between 0.5 and 1.5 and
 # Y between -2 and -1.
 $z = f($x,$y);            

C<xlinvals>, C<ylinvals> and C<zlinvals> return a piddle with the same shape
as their first argument and linearly scaled values between the two other
arguments along the given axis.

=head2 ylinvals

=for ref

Y axis values between endpoints (see L<yvals|/yvals>).

See L<xlinvals|/xlinvals> for more information.

=head2 zlinvals

=for ref

Z axis values between endpoints (see L<zvals|/zvals>).

See L<xlinvals|/xlinvals> for more information.

=head2 xlogvals

=for ref

X axis values logarithmically spaced between endpoints (see L<xvals|/xvals>).

=for usage

 $a = zeroes(100,100);
 $x = $a->xlogvals(1e-6,1e-3);
 $y = $a->ylinvals(1e-4,1e3);
 # calculate Z for X between 1e-6 and 1e-3 and
 # Y between 1e-4 and 1e3.
 $z = f($x,$y);            

C<xlogvals>, C<ylogvals> and C<zlogvals> return a piddle with the same shape
as their first argument and logarithmically scaled values between the two other
arguments along the given axis.

=head2 ylogvals

=for ref

Y axis values logarithmically spaced between endpoints (see L<yvals|/yvals>).

See L<xlogvals|/xlogvals> for more information.

=head2 zlogvals

=for ref

Z axis values logarithmically spaced between endpoints (see L<zvals|/zvals>).

See L<xlogvals|/xlogvals> for more information.

=cut

# Conveniently named interfaces to axisvals()

sub xvals { ref($_[0]) && ref($_[0]) ne 'PDLA::Type' ? $_[0]->xvals : PDLA->xvals(@_) }
sub yvals { ref($_[0]) && ref($_[0]) ne 'PDLA::Type' ? $_[0]->yvals : PDLA->yvals(@_) }
sub zvals { ref($_[0]) && ref($_[0]) ne 'PDLA::Type' ? $_[0]->zvals : PDLA->zvals(@_) }
sub PDLA::xvals {
    my $class = shift;
    my $pdl = scalar(@_)? $class->new_from_specification(@_) : $class->new_or_inplace;
    axisvals2($pdl,0);
    return $pdl;
}
sub PDLA::yvals {
    my $class = shift;
    my $pdl = scalar(@_)? $class->new_from_specification(@_) : $class->new_or_inplace;
    axisvals2($pdl,1);
    return $pdl;
}
sub PDLA::zvals {
    my $class = shift;
    my $pdl = scalar(@_)? $class->new_from_specification(@_) : $class->new_or_inplace;
    axisvals2($pdl,2);
    return $pdl;
}

sub PDLA::xlinvals {
	my $dim = $_[0]->getdim(0);
	barf "Must have at least two elements in dimension for xlinvals"
		if $dim <= 1;
	return $_[0]->xvals * (($_[2] - $_[1]) / ($dim-1)) + $_[1];
}

sub PDLA::ylinvals {
	my $dim = $_[0]->getdim(1);
	barf "Must have at least two elements in dimension for ylinvals"
		if $dim <= 1;
	return $_[0]->yvals * (($_[2] - $_[1]) / ($dim-1)) + $_[1];
}

sub PDLA::zlinvals {
	my $dim = $_[0]->getdim(2);
	barf "Must have at least two elements in dimension for zlinvals"
		if $dim <= 1;
	return $_[0]->zvals * (($_[2] - $_[1]) / ($dim-1)) + $_[1];
}

sub PDLA::xlogvals {
	my $dim = $_[0]->getdim(0);
	barf "Must have at least two elements in dimension for xlogvals"
		if $dim <= 1;
	my ($xmin,$xmax) = @_[1,2];
	barf "xmin and xmax must be positive"
	  if $xmin <= 0 || $xmax <= 0;
	my ($lxmin,$lxmax) = (log($xmin), log($xmax));
	return exp($_[0]->xvals * (($lxmax - $lxmin) / ($dim-1)) + $lxmin);
}

sub PDLA::ylogvals {
	my $dim = $_[0]->getdim(1);
	barf "Must have at least two elements in dimension for xlogvals"
		if $dim <= 1;
	my ($xmin,$xmax) = @_[1,2];
	barf "xmin and xmax must be positive"
	  if $xmin <= 0 || $xmax <= 0;
	my ($lxmin,$lxmax) = (log($xmin), log($xmax));
	return exp($_[0]->yvals * (($lxmax - $lxmin) / ($dim-1)) + $lxmin);
}

sub PDLA::zlogvals {
	my $dim = $_[0]->getdim(2);
	barf "Must have at least two elements in dimension for xlogvals"
		if $dim <= 1;
	my ($xmin,$xmax) = @_[1,2];
	barf "xmin and xmax must be positive"
	  if $xmin <= 0 || $xmax <= 0;
	my ($lxmin,$lxmax) = (log($xmin), log($xmax));
	return exp($_[0]->zvals * (($lxmax - $lxmin) / ($dim-1)) + $lxmin);
}


=head2 allaxisvals

=for ref

Synonym for L<ndcoords|ndcoords> - enumerates all coordinates in a
PDLA or dim list, adding an extra dim on the front to accommodate
the vector coordinate index (the form expected by L<indexND|indexND>,
L<range|range>, and L<interpND|interpND>).  See L<ndcoords|ndcoords> for more detail.

=for usage

$indices = allaxisvals($pdl);
$indices = allaxisvals(@dimlist);
$indices = allaxisvals($type,@dimlist);

=cut

=head2 ndcoords

=for ref

Enumerate pixel coordinates for an N-D piddle

Returns an enumerated list of coordinates suitable for use in
L<indexND|PDLA::Slices/indexND> or L<range|PDLA::Slices/range>: you feed
in a dimension list and get out a piddle whose 0th dimension runs over
dimension index and whose 1st through Nth dimensions are the
dimensions given in the input.  If you feed in a piddle instead of a
perl list, then the dimension list is used, as in L<xvals|xvals> etc.

Unlike L<xvals|xvals> etc., if you supply a piddle input, you get 
out a piddle of the default piddle type: double.   This causes less
surprises than the previous default of keeping the data type of
the input piddle since that rarely made sense in most usages.

=for usage

$indices = ndcoords($pdl);
$indices = ndcoords(@dimlist);
$indices = ndcoords($type,@dimlist);

=for example

  pdla> print ndcoords(2,3)

  [
   [
    [0 0]
    [1 0]
   ]
   [
    [0 1]
    [1 1]
   ]
   [
    [0 2]
    [1 2]
   ]
  ]

  pdla> $a = zeroes(byte,2,3);        # $a is a 2x3 byte piddle
  pdla> $b = ndcoords($a);            # $b inherits $a's type
  pdla> $c = ndcoords(long,$a->dims); # $c is a long piddle, same dims as $b
  pdla> help $b;
  This variable is   Byte D [2,2,3]              P            0.01Kb
  pdla> help $c;
  This variable is   Long D [2,2,3]              P            0.05Kb


=cut

sub PDLA::ndcoords { 
  my $type;
  if(ref $_[0] eq 'PDLA::Type') {
    $type = shift;
  }
  
  my @dims = (ref $_[0]) ? (shift)->dims : @_;
  my @d = @dims;
  unshift(@d,scalar(@dims));
  unshift(@d,$type) if defined($type);

  $out = PDLA->zeroes(@d);
  
  for my $d(0..$#dims) {
    my $a = $out->index($d)->mv($d,0);
    $a .= xvals($a);
  }

  $out;
}
*ndcoords = \&PDLA::ndcoords;
*allaxisvals = \&PDLA::ndcoords;
*PDLA::allaxisvals = \&PDLA::ndcoords;
 

=head2 hist

=for ref

Create histogram of a piddle

=for usage

 $hist = hist($data);
 ($xvals,$hist) = hist($data);

or

 $hist = hist($data,$min,$max,$step);
 ($xvals,$hist) = hist($data,[$min,$max,$step]);

If C<hist> is run in list context, C<$xvals> gives the
computed bin centres as double values.

A nice idiom (with 
L<PDLA::Graphics::PGPLOT|PDLA::Graphics::PGPLOT>) is

 bin hist $data;  # Plot histogram

=for example

 pdla> p $y
 [13 10 13 10 9 13 9 12 11 10 10 13 7 6 8 10 11 7 12 9 11 11 12 6 12 7]
 pdla> $h = hist $y,0,20,1; # hist with step 1, min 0 and 20 bins
 pdla> p $h
 [0 0 0 0 0 0 2 3 1 3 5 4 4 4 0 0 0 0 0 0]

=cut

sub PDLA::hist {

    my $usage = "\n" . '  Usage:          $hist  = hist($data)' . "\n" .
                       '                  $hist  = hist($data,$min,$max,$step)' . "\n" .
                       '          ($xvals,$hist) = hist($data)' . "\n" .
                       '          ($xvals,$hist) = hist($data,$min,$max,$step)' . "\n" ;
    barf($usage) if $#_<0;

    my($pdl,$min,$max,$step)=@_;
    my $xvals;

    ($step, $min, $bins, $xvals) = 
        _hist_bin_calc($pdl, $min, $max, $step, wantarray());

    PDLA::Primitive::histogram($pdl->clump(-1),(my $hist = null),
			      $step,$min,$bins);

    return wantarray() ? ($xvals,$hist) : $hist;
}

=head2 whist

=for ref

Create a weighted histogram of a piddle

=for usage

 $hist = whist($data, $wt, [$min,$max,$step]);
 ($xvals,$hist) = whist($data, $wt, [$min,$max,$step]);

If requested, C<$xvals> gives the computed bin centres
as type double values.  C<$data> and C<$wt> should have
the same dimensionality and extents.

A nice idiom (with 
L<PDLA::Graphics::PGPLOT|PDLA::Graphics::PGPLOT>) is

 bin whist $data, $wt;  # Plot histogram

=for example

 pdla> p $y
 [13 10 13 10 9 13 9 12 11 10 10 13 7 6 8 10 11 7 12 9 11 11 12 6 12 7]
 pdla> $wt = grandom($y->nelem)
 pdla> $h = whist $y, $wt, 0, 20, 1 # hist with step 1, min 0 and 20 bins
 pdla> p $h                        
 [0 0 0 0 0 0 -0.49552342  1.7987439 0.39450696  4.0073722 -2.6255299 -2.5084501  2.6458365  4.1671676 0 0 0 0 0 0]


=cut

sub PDLA::whist {
    barf('Usage: ([$xvals],$hist) = whist($data,$wt,[$min,$max,$step])')
            if @_ < 2;
    my($pdl,$wt,$min,$max,$step)=@_;
    my $xvals;

    ($step, $min, $bins, $xvals) = 
        _hist_bin_calc($pdl, $min, $max, $step, wantarray());

    PDLA::Primitive::whistogram($pdl->clump(-1),$wt->clump(-1),
			       (my $hist = null), $step, $min, $bins);
    return wantarray() ? ($xvals,$hist) : $hist;
}

sub _hist_bin_calc {
    my($pdl,$min,$max,$step,$wantarray)=@_;
    $min = $pdl->min() unless defined $min;
    $max = $pdl->max() unless defined $max;
    my $nelem = $pdl->nelem;
    barf "empty piddle, no values to work with" if $nelem == 0;

    $step = ($max-$min)/(($nelem>10_000) ? 100 : sqrt($nelem)) unless defined $step;
    barf "step is zero (or all data equal to one value)" if $step == 0;

    my $bins = int(($max-$min)/$step+0.5);
    print "hist with step $step, min $min and $bins bins\n"
	if $PDLA::debug;
    # Need to use double for $xvals here
    my $xvals = $min + $step/2 + sequence(PDLA::Core::double,$bins)*$step if $wantarray;

    return ( $step, $min, $bins, $xvals );
}


=head2 sequence

=for ref

Create array filled with a sequence of values

=for usage

 $a = sequence($b); $a = sequence [OPTIONAL TYPE], @dims;

etc. see L<zeroes|PDLA::Core/zeroes>.

=for example

 pdla> p sequence(10)
 [0 1 2 3 4 5 6 7 8 9]
 pdla> p sequence(3,4)
 [
  [ 0  1  2]
  [ 3  4  5]
  [ 6  7  8]
  [ 9 10 11]
 ]

=cut

sub sequence { ref($_[0]) && ref($_[0]) ne 'PDLA::Type' ? $_[0]->sequence : PDLA->sequence(@_) }
sub PDLA::sequence {
    my $class = shift;
    my $pdl = scalar(@_)? $class->new_from_specification(@_) : $class->new_or_inplace;
    my $bar = $pdl->clump(-1)->inplace;
    my $foo = $bar->xvals;
    return $pdl;
}

=head2 rvals

=for ref

Fills a piddle with radial distance values from some centre.

=for usage

 $r = rvals $piddle,{OPTIONS};
 $r = rvals [OPTIONAL TYPE],$nx,$ny,...{OPTIONS};

=for options

 Options:

 Centre => [$x,$y,$z...] # Specify centre
 Center => [$x,$y.$z...] # synonym.

 Squared => 1 # return distance squared (i.e., don't take the square root)

=for example

 pdla> print rvals long,7,7,{Centre=>[2,2]}
 [
  [2 2 2 2 2 3 4]
  [2 1 1 1 2 3 4]
  [2 1 0 1 2 3 4]
  [2 1 1 1 2 3 4]
  [2 2 2 2 2 3 4]
  [3 3 3 3 3 4 5]
  [4 4 4 4 4 5 5]
 ]

If C<Center> is not specified, the midpoint for a given dimension of
size C<N> is given by C< int(N/2) > so that the midpoint always falls
on an exact pixel point in the data.  For dimensions of even size,
that means the midpoint is shifted by 1/2 pixel from the true center
of that dimension.

Also note that the calculation for C<rvals> for integer values
does not promote the datatype so you will have wraparound when
the value calculated for C< r**2 > is greater than the datatype
can hold.  If you need exact values, be sure to use large integer
or floating point datatypes.

For a more general metric, one can define, e.g.,

 sub distance {
   my ($a,$centre,$f) = @_;
   my ($r) = $a->allaxisvals-$centre;
   $f->($r);
 }
 sub l1 { sumover(abs($_[0])); }
 sub euclid { use PDLA::Math 'pow'; pow(sumover(pow($_[0],2)),0.5); }
 sub linfty { maximum(abs($_[0])); }

so now

 distance($a, $centre, \&euclid);

will emulate rvals, while C<\&l1> and C<\&linfty> will generate other
well-known norms. 

=cut

sub rvals { ref($_[0]) && ref($_[0]) ne 'PDLA::Type' ? $_[0]->rvals(@_[1..$#_]) : PDLA->rvals(@_) }
sub PDLA::rvals { # Return radial distance from given point and offset
    my $class = shift;
    my $opt = pop @_ if ref($_[$#_]) eq "HASH";
    my %opt = defined $opt ? 
               iparse( {
			CENTRE  => undef, # needed, otherwise centre/center handling painful
			Squared => 0,
		       }, $opt ) : ();
    my $r =  scalar(@_)? $class->new_from_specification(@_) : $class->new_or_inplace;

    my @pos;
    @pos = @{$opt{CENTRE}} if defined $opt{CENTRE};
    my $offset;

    $r .= 0.0;
    my $tmp = $r->copy;
    my $i;
    for ($i=0; $i<$r->getndims; $i++) {
         $offset = (defined $pos[$i] ? $pos[$i] : int($r->getdim($i)/2));
	 # Note careful coding for speed and min memory footprint
	 PDLA::Primitive::axisvalues($tmp->xchg(0,$i));
	 $tmp -= $offset; $tmp *= $tmp;
         $r += $tmp;
    }
    return $opt{Squared} ? $r : $r->inplace->sqrt;
}

=head2 axisvals

=for ref

Fills a piddle with index values on Nth dimension

=for usage

 $z = axisvals ($piddle, $nth);

This is the routine, for which L<xvals|/xvals>, L<yvals|/yvals> etc
are mere shorthands. C<axisvals> can be used to fill along any dimension,
using a parameter.

See also L<allaxisvals|allaxisvals>, which generates all axis values 
simultaneously in a form useful for L<range|range>, L<interpND|interpND>, 
L<indexND|indexND>, etc.

Note the 'from specification' style (see L<zeroes|PDLA::Core/zeroes>) is
not available here, for obvious reasons.

=cut

sub PDLA::axisvals {
	my($this,$nth) = @_;
	my $dummy = $this->new_or_inplace;
	if($dummy->getndims() <= $nth) {
		# This is 'kind of' consistency...
		$dummy .= 0;
		return $dummy;
#		barf("Too few dimensions given to axisvals $nth\n");
	}
	my $bar = $dummy->xchg(0,$nth);
	PDLA::Primitive::axisvalues($bar);
	return $dummy;
}

# We need this version for xvals etc to work in place
sub axisvals2 {
	my($this,$nth) = @_;
	my $dummy = shift;
	if($dummy->getndims() <= $nth) {
		# This is 'kind of' consistency...
		$dummy .= 0;
		return $dummy;
#		barf("Too few dimensions given to axisvals $nth\n");
	}
	my $bar = $dummy->xchg(0,$nth);
	PDLA::Primitive::axisvalues($bar);
	return $dummy;
}
sub PDLA::sec {
	my($this,@coords) = @_;
	my $i; my @maps;
	while($#coords > -1) {
		$i = int(shift @coords) ;
		push @maps, "$i:".int(shift @coords);
	}
	my $tmp = PDLA->null;
	$tmp .= $this->slice(join ',',@maps);
	return $tmp;
}

sub PDLA::ins {
	my($this,$what,@coords) = @_;
	my $w = PDLA::Core::alltopdl($PDLA::name,$what);
	my $tmp;
	if($this->is_inplace) {
	  $this->set_inplace(0);
	} else {
	  $this = $this->copy;
	}
	($tmp = $this->slice(
	   (join ',',map {int($coords[$_]).":".
	   	((int($coords[$_])+$w->getdim($_)-1)<$this->getdim($_) ?
	   	(int($coords[$_])+$w->getdim($_)-1):$this->getdim($_))
	   	}
	   	0..$#coords)))
		.= $w;
	return $this;
}

sub PDLA::similar_assign {
	my($from,$to) = @_;
	if((join ',',@{$from->dims}) ne (join ',',@{$to->dims})) {
		barf "Similar_assign: dimensions [".
			(join ',',@{$from->dims})."] and [".
			(join ',',@{$to->dims})."] do not match!\n";
	}
	$to .= $from;
}

=head2 transpose

=for ref

transpose rows and columns. 

=for usage

 $b = transpose($a); 

=for example

 pdla> $a = sequence(3,2)
 pdla> p $a
 [
  [0 1 2]
  [3 4 5]
 ]                                                                               
 pdla> p transpose( $a )
 [
  [0 3]
  [1 4]
  [2 5]                                                                          
 ]

=cut

sub PDLA::transpose {
	my($this) = @_;
	if($this->getndims <= 1) {
	    if($this->getndims==0) {
		return pdl $this->dummy(0)->dummy(0);
	    } else {
		return pdl $this->dummy(0);
	    }
	}
	return $this->xchg(0,1);
}

1;

