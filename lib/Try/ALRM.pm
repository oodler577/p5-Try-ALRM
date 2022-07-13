package Try::ALRM;

use strict;
use warnings;

use Exporter 5.57 'import';
our @EXPORT    = qw(try ALRM timeout);
our @EXPORT_OK = qw(try ALRM timeout);

our $TIMEOUT   = 60;

sub _assert_timeout {
  my $timeout = shift;
  if ( int $timeout <= 0 ) {
    die qq{timeout must be an integeger >= 1!\n};
  }
}

# setter/getter for $Try::ALRM::TIMEOUT 
sub timeout (;$) {
  my $timeout = shift;
  if ($timeout) {
    _assert_timeout($timeout);
    $TIMEOUT = $timeout;
  }
  return $TIMEOUT;
}

sub try (&;@) {
  my ($TRY, $CATCH, $timeout) = @_;
  local $SIG{ALRM} = $CATCH;
  if ($timeout) {
    _assert_timeout($timeout);
  }
  local $TIMEOUT = $timeout;
  CORE::alarm($TIMEOUT);
  $TRY->();
  CORE::alarm 0;
}

sub ALRM (&;@) {
  return @_;
}

__PACKAGE__

__END__

=head1 NAME

  Try::ALRM - Provides semantics similar to C<Try::Catch>.

=head1 SYNOPSIS

    use Try::ALRM;
    timeout 5;
    try {
      local $|=1; 
      print qq{ doing something that might timeout ...\n};
      sleep 6;
    }
    ALRM {
      print qq{ Alarm Clock!!!!\n};
    };

Is equivalent to,

    local $SIG{ALRM} = sub { print qq{ Alarm Clock!!!\n} }; # on limitd
    alarm 5;
    local $|=1;
    print qq{ doing something that might timeout ...\n};
    sleep 6;
    alarm 0; # reset alarm

=head1 DESCRIPTION

Provides I<try/catch>-like semantics for handling code being guarded by
C<alarm>. Because it's localized and potentially expected, C<ALRM> signals
can be treated as exceptions.

C<alarm> is extremely useful, but it can be cumbersome do add in code. The
goal of this module is to make it more idiomatic, and therefore more accessible.
It also allows for the C<ALRM> signal itself to be treated more semantically
as an exception. Which makes it a more natural to write and read in Perl.
That's the idea, anyway.

Internally, the I<keywords> are implemented as prototypes and uses the same
sort of coersion of a lexical bloc to a subroutine reference that is used
in C<Try::Tiny>.

=head1 USAGE

C<Try::ALRM> doesn't really have options, it's more of a structure. So this
section is meant to descript that structure and ways to control it. 

=over 4

=item C<try>

This familiar idiom include the block of code that may run longer than one
wishes and is need of an C<alarm>.

  # default timeout is $Try::ALRM::TIMEOUT
  try {
    this_subroutine_call_may_timeout();
  };

If just C<try> is used here, what happens is functionall equivalent to:

  alarm 60; # e.g., the default value of $Try::ALRM::TIMEOUT
  this_subroutine_call_may_timeout();
  alarm 0;

And the default handler for C<$SIG{ALRM}> is invoked if an C<ALRM> is
send.

=item C<ALRM>

This keyword is for setting C<$SIG{ALRM}> with the block that gets passed to
it; e.g.:

  # default timeout is $Try::ALRM::TIMEOUT
  try {
    this_subroutine_call_may_timeout();
  }
  ALRM {
    print qq{ Alarm Clock!!!!\n};
  };

The addition of the C<ALRM> block above is functionally equivalent to the typical
idiom of using C<alarm> and setting C<$SIG{ALRM}>,

  local $SIG{ALRM} = sub { print qq{ Alarm Clock!!!!\n};
  alarm 60; # e.g., the default value of $Try::ALRM::TIMEOUT
  this_subroutine_call_may_timeout();
  alarm 0;

So while this module present C<alarm> with I<try/catch> semantics, there are no
actualy exceptions getting thrown via C<die>; the traditional signal handling mechanism
is being invoked as the exception handler.

=back

=head1 SETTING TIMEOUT

The timeout value passed to C<alarm> internally is controlled with the package variable,
C<$Try::ALRM::TIMEOUT>. This module presents 3 different ways to control the value of
this variable.

=over 4

=item C<timeout>

Due to limitations with the way Perl prototypes work for creating syntactical structures,
the most idiomatic solution is to use a setter/getter function to update the package
variable:

  timeout 10; # changes $Try::ALRM::TIMEOUT to 10
  try {
    this_subroutine_call_may_timeout();
  }
  ALRM {
    print qq{ Alarm Clock!!!!\n};
  };

If used without an input value, C<timeout> returns the current value of C<$Try::ALRM::TIMEOUT>.

=item Trailing value after the C<ALRM> block

  try {
    this_subroutine_call_may_timeout();
  }
  ALRM {
    print qq{ Alarm Clock!!!!\n};
  } 10; # NB: no comma; applies temporarily!

This approach utilizes the effect of defining a Perl prototype, C<&>, which coerces a lexical
block into a subroutine reference (i.e., C<CODE>).

The addition of this timeout affects $Try::ALRM::TIMEOUT for the duration of the C<try> block,
internally is using C<local> to set C<$Try::ALRM::TIMEOUT>. The reason for this is so that
C<timeout> may continue to function properly as a getter.

=back

=head2 Example

Using the two methods above, the following code demonstrats the usage of C<timeout> and the
effect of the trailing timeout value,

    # set timeout (persists)
    timeout 5;
    printf qq{now %d seconds timeout\n}, timeout;
     
    # try/ALRM
    try {
      local $|=1;
      printf qq{ doing something that might timeout before %d seconds are up ...\n}, timeout;
      sleep 6;
    }
    ALRM {
      print qq{Alarm Clock!!\n};
    } 1; # <~ trailing timeout
    
    # will still be 5 seconds
    printf qq{now %d seconds timeout\n}, timeout;

The output of this block is,

  default timeout is 60 seconds
  timeout is set globally to 5 seconds
  timeout is now set locally to 1 seconds
  Alarm Clock!!
  timeout is set globally to 5 seconds

=head1 AUTHOR AND COPYRIGHT
