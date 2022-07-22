use strict;
use warnings;

my $TIMEOUT = 60;
my $RETRIES = 3;

#TODO: get this in lib/Try/ALRM.pm
#TODO: update unit tests for 'retry'
=pod
sub retry(&;@) {
    unshift @_, q{retry};    # adding marker, will be key for this &
    my %TODO = @_;
    my $TODO = \%TODO;

    my $TRY = $TODO->{retry};
    #TODO: ^^^^ die if $TRY is not CODE

    my $ALRM    = $TODO->{ALRM};
    my $FINALLY = $TODO->{finally} // sub { };
    my $timeout = $TODO->{timeout} // $TIMEOUT;

    my ( $attempts, $succeeded );
    $SIG{ALRM} //= sub { };
    my $current_SIG_ALRM = $SIG{ALRM};

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

            # fallback to original $SIG{ALRM}, if not set is no-op 'sub {}'
            else {
                $current_SIG_ALRM->();
            }
        };

        # actual alarm code
        alarm($timeout);
        $TRY->( $attempt, $TODO->{retries} );
        alarm 0;
        unless ( $retry == 1 ) {
            ++$succeeded;
            last;
        }
    }

    # "finally" (defaults to no-op 'sub {}' if block is not defined)
    $FINALLY->( $attempts, $TODO->{retries}, $succeeded );
}

sub ALRM(&;@) {
    unshift @_, q{ALRM};    # create marker, will be key for &
    return @_;
}

sub finally (&;@) {
    unshift @_, q{finally};    # create marker, will be key for &
    return @_;
}

=cut

use Try::ALRM;
# -- try it out

retry {
    my ( $attempt, $limit ) = @_;
    printf qq{Attempt %d/%d of something that might take more than 3 second\n}, $attempt, $limit;
    sleep( 1 + int rand(5) );
}
ALRM {
    my ( $attempt, $limit ) = @_;
    printf qq{\tTIMED OUT - Retrying ...\n};
}
finally {
    my ( $attempts, $limit, $success ) = @_;
    printf qq{%s after %d of %d attempts\n}, ($success)?q{Success}:q{Failure}, $attempts, $limit; 
}
timeout => 3, retries => 4;
#TODO: timeout to be a subroutine or array of numbers that match with the retry?

__END__

Example output:

Eventual success:
	Attempt 1/4 of something that might take more than 3 second
		TIMED OUT - Retrying ...
	Attempt 2/4 of something that might take more than 3 second
		TIMED OUT - Retrying ...
	Attempt 3/4 of something that might take more than 3 second
	OK after 3/4 attempts

Total fail:

	Attempt 1/4 of something that might take more than 3 second
		TIMED OUT - Retrying ...
	Attempt 2/4 of something that might take more than 3 second
		TIMED OUT - Retrying ...
	Attempt 3/4 of something that might take more than 3 second
		TIMED OUT - Retrying ...
	Attempt 4/4 of something that might take more than 3 second
		TIMED OUT - Retrying ...
	NOT OK after 4/4 attempts

