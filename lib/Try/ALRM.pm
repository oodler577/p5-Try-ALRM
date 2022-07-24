use strict;
use warnings;

package Try::ALRM;

our $VERSION = q{0.5};

use Exporter qw/import/;
our @EXPORT    = qw(try retry ALRM finally timeout tries);
our @EXPORT_OK = qw(try retry ALRM finally timeout tries);

our $TIMEOUT = 60;
our $TRIES   = 3;

# setter/getter for $Try::ALRM::TIMEOUT
sub timeout (;$) {
    my $timeout = shift;
    if ( defined $timeout ) {
        _assert_timeout($timeout);
        $TIMEOUT = $timeout;
    }
    return $TIMEOUT;
}

# setter/getter for $Try::ALRM::TRIES
sub tries (;$) {
    my $tries = shift;
    if ( defined $tries ) {
        _assert_tries($tries);
        $TRIES = $tries;
    }
    return $TRIES;
}

#TODO: investigate making C<try> a case of C<retry>, where C<tries => 1>.
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

    local $TIMEOUT   = $timeout;                     # make available to timeout(;$)
    local $SIG{ALRM} = $ALRM;                        # will either be custom $ALRM or global $SIG{ALRM} (determined above)
                                                     # do trad alarm stuff
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
    my $tries   = $TODO->{tries}   // $TRIES;
    my $FINALLY = $TODO->{finally} // sub { };

    my ( $attempts, $succeeded );

    local $TIMEOUT = $timeout;                       # make available to timeout(;$)
    local $TRIES   = $tries;                         # make available to tries(;$)
  TIMED_ATTEMPTS:
    for my $attempt ( 1 .. $TRIES ) {
        $attempts = $attempt;
        my $retry = 0;

        # NOTE: handler always becomes a local wrapper
        local $SIG{ALRM} = sub {
            ++$retry;
            if ( ref($ALRM) =~ m/^CODE$|::/ ) {
                $ALRM->($attempt);
            }
        };

        # actual alarm code
        alarm($timeout);
        $RETRY->($attempt);
        alarm 0;
        unless ( $retry == 1 ) {
            ++$succeeded;
            last;
        }
    }

    # "finally" (defaults to no-op 'sub {}' if block is not defined)
    $FINALLY->( $attempts, $succeeded );
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
sub _assert_tries {
    my $timeout = shift;
    if ( int $timeout <= 0 ) {
        die qq{timeout must be an integeger >= 1!\n};
    }
}

__PACKAGE__

__END__

=head1 NAME

Try::ALRM - Provides C<try> and C<retry> semantics to C<CORE::alarm>, similar to C<Try::Catch>.

=head1 FRIENDLY TESTING AND FEEDBACK REQUESTED 

While the utility of this module should be clear, there are a few factors that require a
maturing. These issues are addressed throughout the documentation below. Using the module
and providing feedback about it will be extremely appreciated. Please do so at the Github
repo.

=head1 SYNOPSIS

=head2 C<try>

    use Try::ALRM;
     
    try {
      print qq{ doing something that might timeout ...\n};
      sleep 6;
    }
    ALRM {
      print qq{ Wake Up!!!!\n};
    }
    finally {
      # unconditionally do this, note: @_ is empty when called via `try`
    } timeout => 1;

Is equivalent to,

    local $SIG{ALRM} = sub { print qq{ Wake Up!!!!\n} };
    alarm 5;
    print qq{ doing something that might timeout ...\n};
    sleep 6;
    alarm 0; # reset alarm, end of 'try' block implies this "reset"
# finally ...

=head2 C<retry>

    retry {
        my ($attempt) = @_;    # @_ is populated as described in this line
        printf qq{Attempt %d/%d ... \n}, $attempt, tries;
        sleep(5);
    }
    ALRM {
        my ($attempt) = @_;                 # Note: @_ is populated as described in this line when called with retry
        printf qq{\tTIMED OUT};
        if ( $attempt < tries ) {
            printf qq{ - Retrying ...\n};
        }
        else {
            printf qq{ - Giving up ...\n};
        }
    }
    finally {
        my ( $attempts, $success ) = @_;    # Note: @_ is populated as described in this line when called with retry
        my $tries   = tries;                # will be 3
        my $timeout = timeout;              # will be 4
        printf qq{%s after %d of %d attempts (timeout of %d)\n}, ($success) ? q{Success} : q{Failure}, $attempts, $tries, $timeout;
    }
    timeout => 3, tries => 4;

This is equivalent to ... well, checkout the implementation of C<Try::ALRM::retry(&;@)>,
because it is equivalent to that I<:-)>.

However, it should be pointed out that C<try> is a reduced case of C<retry>
where C<< tries => 1 >>.  There might be benefits to using it in this way. Future
developments may be affected by this approach.

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

=head1 THE CLOBBERING OF THE C<try> KEYWORD 

C<Try::ALRM> implements a C<try> method ( though, no C<catch>). It does
provide and exports a C<finally> keyword.

There is a similar opportunity for clobbering the C<finally> keyword.
The proper course of action is still unknown, but could include renaming
C<try> and C<finally>. However, a more fair and permanent solution would be
to not export the C<try> or C<finally> keywords and force the caller to use
C<Try::ALRM::try>, etc. 

To ensure that I<NO> methods get exported by C<Try::ALRM>, it may be loaded
as follows,

    use Try::ALRM qw//; # now all keywords must be called fully qualified

This module has not yet been tested extensively with C<Try::Tiny>, but in
order to eliminate the potential for clobbering the exported C<try> method,
it may be prudent to refer to C<Try::ALRM>'s methods using their fully
qualified package names, e.g., below only C<tries> and C<timeout> are exported
by default. C<retry>, C<ALRM>, and C<finally> are not; and they are
referred to by their fully qualified name (something the author of this
module tends to do often enough anyway):

    use Try::ALRM qw/tries timeout/;
    
    Try::ALRM::retry {
        my ($attempt) = @_;    # @_ is populated as described in this line
        printf qq{Attempt %d/%d ... \n}, $attempt, tries; sleep(5);
    }
    Try::ALRM::ALRM {
        my ($attempt) = @_;    # @_ is populated as described in this line
        printf qq{\tTIMED OUT};
        if ( $attempt < tries ) {
            printf qq{ - Retrying ...\n};
        }
        else {
            printf qq{ - Giving up ...\n};
        }
    }
    Try::ALRM::finally {
        my ( $attempts, $success ) = @_;    # @_ is populated as described in this line
        my $tries   = tries;                # will be 3
        my $timeout = timeout;              # will be 4
        printf qq{%s after %d of %d attempts (timeout of %d)\n}, ($success) ? q{Success} : q{Failure}, $attempts, $tries, $timeout;
    }
    timeout => 3, tries => 4;

As this module matures, this will be explored more thoroughly; as proper deference should be given to C<Try::Tiny> since it's such an extensively
used module.

=head1 EXPORTS

It is possible that this module will in the future I<not> export any subroutines
that might conflict with keywords provided by more commonly used modules (e.g.,
C<Try::Tiny::try>. But for now all methods are exported.

This module exports 6 methods:

B<NOTE>: C<Try::ALRM::try> and C<Try::ALRM::retry> are mutually exclusive, but one
of them is I<required> to invoke any benefits of using this module.

=over 4

=item C<try BLOCK>

Not meant to be used with C<Try::ARLM::retry>.

Primary BLOCK, attempted once with a timeout set by C<$Try::ALRM::TIMEOUT>. If
an C<ALRM> signal is sent, the BLOCK described by C<ALRM> will be called to handle
the signal. If C<ALRM> is not defined, the normal mechanisms of handling C<$SIG{ALRM}>
will be employed. Mutually exclusive of C<retry>.

Accepts blocks: C<ALRM>, C<finally>; and trailing modifier C<< timeout => INT >>.

B<Note>: that C<try> is essentially a trival case of C<retry> with C<< tries => 1 >>; and
in the future it may just become a wrapper around this case. For now it is its own
independant implementation.

=item C<retry BLOCK>

Not meant to be used with C<Try::ARLM::try>.

Primary BLOCK, attempted C<$Try::ALRM::TRIES> number of times with a timeout
governed by C<$Try::ALRM::TIMEOUT>. If an C<ALRM> signal is sent and the number
of C<tries> has not been exhausted, the C<retry> BLOCK will be tried again.
This continues until an C<ALRM> signal is not triggered or if the number of
C<$Try::ALRM::TRIES> has been reached.

Accepts blocks: C<ALRM>, C<finally>; and trailing modifiers C<< timeout => INT >>,
and C<< retries => INT >>.

C<retry> makes values available to each C<BLOCK> that is called via C<@_>, see
description of each BLOCK below for more details. This also applies to the BLOCK
provided for C<retry>.

=item C<ALRM BLOCK>

Optional.

Called when an C<ALRM> signal is detected. If no C<ALRM> BLOCK is defined, then
the default C<$SIG{ALRM}> handler mechanism is invoked. 

When called with C<retry>, C<@_> contains the number of attempts that have been
made so far.

  retry {
    ...
  }
  ALRM {
    my ($attempts) = @_;
  };

=item C<finally BLOCK>

This BLOCK is called unconditionally. When called with C<try>, C<@_> contains an
indication there being a timeout or not in the attempted block.

When called with C<retry>, C<@_> also contains the number of attempts that have been
made before the attempts ceased. There is also a value that is passed that indicates
if C<ALRM> had been invoked;

  ...
  finally {
    my ($tries, $succeeded) = @; 
  };

When used with C<try>, C<@_> is empty. Note that C<try> is essentially a trival case
of C<retry> with C<< tries => 1 >>; and in the future it may just become a wrapper around
this case.

=item C<timeout INT>

Setter/getter for C<$Try::ALRM::TIMEOUT>, which governs the default timeout in number
of seconds. This can be temporarily overridden using the trailing modifier C<< timeout => INT >>
that is supported via C<try> and C<retry>. 

  timeout 10; # sets $Try::ALRM::TIMEOUT to 10
  try {
    ...
  }
  ALRM {
    my ($attempts) = @_;
  };

Can be overridden by I<trailing modifier>, C<< timeout => INT >>.

=item C<tries INT>

Setter/getter for C<$Try::ALRM::TRIES>, which governs the number of attempts C<retry>
will make before giving up. This can be temporarily overridden using the trailing modifier
C<< tries => INT >> that is supported via C<retry>.

  timeout 10; # sets $Try::ALRM::TIMEOUT to 10
  tries   12; # sets $Try:::ALRM::TRIES to 12 
  retry {
    ...
  }
  ALRM {
    my ($attempts) = @_;
  };

Can be overridden by I<trailing modifier>, C<< tries => INT >>.

=back

=head1 PACKAGE ENVIRONMENT

This module exposes C<$Try::ALRM::TIMEOUT> and C<$TRY::ALRM::TRIES> as a
package variables; it can be modified in traditional ways. The module also
provides ways to deal with it, continue reading to learn how.

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
  # default number of tries is $Try::ALRM::TRIES
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

=head1 TRAILING MODIFIERS

=head2 Setting the Timeout

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

=item Trailing after the last BLOCK

  try {
    this_subroutine_call_may_timeout();
  }
  ALRM {
    print qq{ Alarm Clock!!!!\n};
  } timeout => 10; # NB: applies temporarily!

This approach utilizes the effect of defining a Perl prototype, C<&>, which coerces a lexical
block into a subroutine reference (i.e., C<CODE>). The I<< key => value >> syntax was chosen as
a compromise because it makes things a lot more clear I<and> makes the implementation of the
blocks a lot easier (use the source to see how, I<Luke>).

The addition of this timeout affects $Try::ALRM::TIMEOUT for the duration of the C<try> block,
internally is using C<local> to set C<$Try::ALRM::TIMEOUT>. The reason for this is so that
C<timeout> may continue to function properly as a getter I<inside> of the C<try> block.

=back

=head3 C<try>/C<ALRM>/C<finally> Examples

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

=head2 Setting the Number of Tries

The number of total attempts made by C<retry> is controlled by the package variable,
C<$Try::ALRM::TRIES>. And it provides similar controls to what is provided for controlling
the timeout.

=over 4

=item Using the C<tries> keyword will affect the package variable C<$Try::ALRM::TRIES> if
passed an integer value. If passed nothing, the current value of C<$Try::ALRM::TRIES> will
be returned

=item Trailing value after the last BLOCK

An example is best here,

  retry {
    ...
  } timeout => 10, tries => 5;

Using the trailing values in this way allows the number of attempts to be temporarily
set to the RHS value of C<< tries => >>.

=back

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
