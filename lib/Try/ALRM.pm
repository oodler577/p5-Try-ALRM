use strict;
use warnings;

package Try::ALRM;

our $VERSION = q{0.5};

use Exporter qw/import/;
our @EXPORT    = qw(try retry ALRM finally timeout);
our @EXPORT_OK = qw(try retry ALRM finally timeout);

our $TIMEOUT = 60;
our $RETRIES = 3;

# setter/getter for $Try::ALRM::TIMEOUT
sub timeout (;$) {
    my $timeout = shift;
    if ( defined $timeout ) {
        _assert_timeout($timeout);
        $TIMEOUT = $timeout;
    }
    return $TIMEOUT;
}

# setter/getter for $Try::ALRM::RETRIES
sub replies (;$) {
    my $replies = shift;
    if ( defined $replies ) {
        _assert_replies($replies);
        $RETRIES = $replies;
    }
    return $RETRIES;
}

sub try (&;@) {
    unshift @_, q{try};
    my %TODO = @_;
    my $TODO = \%TODO;

    #my ( $TRY, $ALRM, $timeout ) = @_;
    my $TRY     = $TODO->{try}     // sub { };
    my $ALRM    = $TODO->{ALRM}    // $SIG{ALRM};    # local ALRM defaults to global $SIG{ALRM}
    my $timeout = $TODO->{timeout} // $TIMEOUT;      # dev note: if future need arises, `timeout=>sub{ ... }` or `timeout=>[qw/1 2 4 8 .../]` might be useful
    my $FINALLY = $TODO->{finally} // sub { };       # $FINALLY is always called, though defaults to no-op if not set

    # final check on the value of $TIMEOUT
    if ($TIMEOUT) {
        _assert_timeout($TIMEOUT);
    }

    # do trad alarm stuff
    local $TIMEOUT = $timeout;                       # make available to timeout(;$)
    local $SIG{ALRM} = $ALRM;                        # will either be custom $ALRM or global $SIG{ALRM} (determined above)
    CORE::alarm($timeout);
    $TRY->();
    CORE::alarm 0;

    # "finally" (defaults to no-op 'sub {}' if block is not defined)
    $FINALLY->();
}

sub retry(&;@) {
    unshift @_, q{retry};                            # adding marker, will be key for this &
    my %TODO = @_;
    my $TODO = \%TODO;

    my $RETRY   = $TODO->{retry}   // sub { };       # defaults to no-op
    my $ALRM    = $TODO->{ALRM}    // $SIG{ALRM};    # local ALRM defaults to global $SIG{ALRM}
    my $timeout = $TODO->{timeout} // $TIMEOUT;
    my $FINALLY = $TODO->{finally} // sub { };

    my ( $attempts, $succeeded );

  TIMED_ATTEMPTS:
    for my $attempt ( 1 .. $TODO->{retries} ) {
        $attempts = $attempt;
        my $retry = 0;

        # NOTE: handler always becomes a local wrapper
        local $SIG{ALRM} = sub {
            ++$retry;
            if ( ref($ALRM) =~ m/^CODE$|::/ ) {
                $ALRM->( $attempt, $TODO->{retries} );
            }
        };

        # actual alarm code
        alarm($timeout);
        $RETRY->( $attempt, $TODO->{retries} );
        alarm 0;
        unless ( $retry == 1 ) {
            ++$succeeded;
            last;
        }
    }

    # "finally" (defaults to no-op 'sub {}' if block is not defined)
    $FINALLY->( $attempts, $TODO->{retries}, $succeeded );
}

sub ALRM (&;@) {
    unshift @_, q{ALRM};
    return @_;
}

sub finally (&;@) {
    unshift @_, q{finally};    # create marker, will be key for &
    return @_;
}

# internal method, validation
sub _assert_timeout {
    my $timeout = shift;
    if ( int $timeout <= 0 ) {
        die qq{timeout must be an integeger >= 1!\n};
    }
}

# internal method, validation
sub _assert_retries {
    my $timeout = shift;
    if ( int $timeout <= 0 ) {
        die qq{timeout must be an integeger >= 1!\n};
    }
}

__PACKAGE__

__END__

=head1 NAME

Try::ALRM - Provides C<alarm> semantics similar to C<Try::Catch>.

=head1 SYNOPSIS

=head2 C<try>

    use Try::ALRM;
     
    try {
      local $|=1; #autoflush for STDOUT
      print qq{ doing something that might timeout ...\n};
      sleep 6;
    }
    ALRM {
      print qq{ Wake Up!!!!\n};
    } timeout => 1;

Is equivalent to,

    local $SIG{ALRM} = sub { print qq{ Wake Up!!!!\n} };
    alarm 5;
    local $|=1; #autoflush for STDOUT
    print qq{ doing something that might timeout ...\n};
    sleep 6;
    alarm 0; # reset alarm, end of 'try' block implies this "reset"

=head2 C<retry>

retry {
    my ( $attempt, $limit ) = @_;
    printf qq{Attempt %d/%d of something that might take more than 3 second\n}, $attempt, $limit;
    sleep( 1 + int rand(5) );
}
ALRM {
    my ( $attempt, $limit ) = @_;
    printf qq{\tTIMED OUT - Retrying ...\n};
} timeout => 3, retries => 4;

=head1 DESCRIPTION

Provides I<try/catch>-like semantics for handling code being guarded by
C<alarm>. Because it's localized and I<probably> expected, C<ALRM> signals
can be treated as exceptions.

C<alarm> is extremely useful, but it can be cumbersome do add in code. The
goal of this module is to make it more idiomatic, and therefore more accessible.
It also allows for the C<ALRM> signal itself to be treated more semantically
as an exception. Which makes it a more natural to write and read in Perl.

Internally, the I<keywords> are implemented as prototypes and uses the same
sort of coersion of a lexical bloc to a subroutine reference that is used
in C<Try::Tiny>.

=head1 EXPORTS

This module exports 3 methods:

=over 4

=item C<try>

=item C<retry>

=item C<ALRM>

=item C<finally>

=item C<retries>

=item C<timeout>

=back

=head1 PACKAGE ENVIRONMENT

This module exposes C<$Try::ALRM::TIMEOUT> as a package variable; it can be
modified in traditional ways. The module also provides ways to deal with it,
continue reading to learn how.

=head2 The C<try> keyword

This module has not yet been tested extensively with C<Try::Tiny>, but in
order to eliminate the potential for clobbering the exported C<try> method,
it may be prudent to refer to C<Try::ALRM>'s methods using their fully
qualified package names, e.g.:

  use strict;
  use warnings;
  use Try::ALRM qw/ALRM timeout/; #<~ NB!
  use Try::Tiny;

  # starts as default, $Try::ALRM::TIMEOUT;
  printf qq{default timeout is %d seconds\n}, timeout;

  # set timeout (persists)
  timeout 5;
  printf qq{timeout is set globally to %d seconds\n}, timeout;

  # try/ALRM
  Try::ALRM::try {
      local $| = 1;

      try {
        die qq{foo\n};
      }
      catch {
        print qq{$_\n};
      };

      # timeout is set to 1 due to trailing value after ALRM block
      printf qq{timeout is now set locally to %d seconds\n}, timeout;
      sleep 6;
  }
  ALRM {
      print qq{Alarm Clock!!\n};
  } timeout => 1; # <~ temporarily overrides $Try::ALRM::TIMEOUT

  printf qq{timeout is set globally to %d seconds\n}, timeout;

As this module matures, this will be explored more thoroughly; as proper
deference should be given to C<Try::Tiny> since it's such an extensively
used module.

=head1 USAGE

C<Try::ALRM> doesn't really have options, it's more of a structure. So this
section is meant to descript that structure and ways to control it. 

=over 4

=item C<try>

This familiar idiom include the block of code that may run longer than one
wishes and is need of an C<alarm> signal.

  # default timeout is $Try::ALRM::TIMEOUT
  try {
    this_subroutine_call_may_timeout();
  };

If just C<try> is used here, what happens is functionall equivalent to:

  alarm 60; # e.g., the default value of $Try::ALRM::TIMEOUT
  this_subroutine_call_may_timeout();
  alarm 0;

And the default handler for C<$SIG{ALRM}> is invoked if an C<ALRM> is
ssued.

=item C<retry>

  # default timeout is $Try::ALRM::TIMEOUT
  # default number of retries is $Try::ALRM::RETRIES
  retry {
    this_subroutine_call_may_timeout_and_we_want_to_retry();
  };

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
C<$Try::ALRM::TIMEOUT>. This module presents 2 different ways to control the value of
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
  } timeout => 10; # NB: applies temporarily!

This approach utilizes the effect of defining a Perl prototype, C<&>, which coerces a lexical
block into a subroutine reference (i.e., C<CODE>). The I<key=>value> syntax was chosen as
a compromise because it makes things a lot more clear I<and> makes the implementation of the
blocks a lot easier (use the source to see how, I<Luke>).

The addition of this timeout affects $Try::ALRM::TIMEOUT for the duration of the C<try> block,
internally is using C<local> to set C<$Try::ALRM::TIMEOUT>. The reason for this is so that
C<timeout> may continue to function properly as a getter I<inside> of the C<try> block.

=back

=head2 C<try>/C<ALRM>/C<finally> Examples

Using the two methods above, the following code demonstrats the usage of C<timeout> and the
effect of the trailing timeout value,

    # set timeout (persists)
    timeout 5;
    printf qq{now %d seconds timeout\n}, timeout;
     
    # try/ALRM
    try {
      printf qq{ doing something that might timeout before %d seconds are up ...\n}, timeout;
      sleep 6;
    }
    ALRM {
      print qq{Alarm Clock!!\n};
    } timeout => 1; # <~ trailing timeout
    
    # will still be 5 seconds
    printf qq{now %d seconds timeout\n}, timeout;

The output of this block is,

  default timeout is 60 seconds
  timeout is set globally to 5 seconds
  timeout is now set locally to 1 seconds
  Alarm Clock!!
  timeout is set globally to 5 seconds

=head2 C<retry>/C<ALRM>/C<finally> Examples

=head1 Bugs

Very likey.

MMV. If found, please file issue on GH repo.

=head1 AUTHOR

oodler577

=head1 ACKNOWLEDGEMENTS

"I<To the least of you among of all of us. You make more of a difference
than any of you will ever know.>" -Anonymous

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 by oodler577

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.30.0
or, at your option, any later version of Perl 5 you may have
available.
