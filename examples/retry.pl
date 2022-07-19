
use strict;
use warnings;

my $TIMEOUT = 60;
my $RETRIES = 3;

sub retry(&;@) {
    my ( $code, $ALRM, $FINALLY, %opts ) = @_;

#TODO: detect #args, look for $ALRM & $FINALLY
    my $retries = $opts{retries} // $RETRIES;
    my $timeout = $opts{timeout} // $TIMEOUT;
    my ( $attempts, $succeeded );

    for my $attempt ( 1 .. $retries ) {
        $attempts = $attempt;
        my $retry = 0;

        # NOTE: handler always becomes a wrapper

#TODO: wrap existing $SIG{ALRM} if $ALRM is not defined
        local $SIG{ALRM} = sub {
            ++$retry;
            $ALRM->( $attempt, $retries ) if ( ref($ALRM) =~ m/^CODE$|::/ );
        };
        alarm($timeout);
        $code->( $attempt, $retries );
        alarm 0;
        unless ( $retry == 1 ) {
            ++$succeeded;
            last;
        }
    }

#TODO: need to check arg count to make this optional
    $FINALLY->( $attempts, $retries, $succeeded );
}

sub ALRM(&;@) {
    return @_;
}

sub finally (&;@) {
    return @_;
}

# -- try it out

retry {
    my ( $attempt, $limit ) = @_;
    printf qq{Attempt %d/%d of something that might take more than 3 second\n}, $attempt, $limit;
    sleep( 1 + int rand(3) );
}
ALRM {
    my ( $attempt, $limit ) = @_;
    printf qq{\tTIMED OUT - Retrying ...\n};
}
finally {
    my ( $attempt, $limit, $ultimately_succeeded ) = @_;
    printf qq{%s after %d/%d attempt%s\n}, ($ultimately_succeeded) ? q{OK} : q{NOT OK}, $attempt, $limit, ( $attempt == 1 ) ? q{} : q{s};
}
timeout => 2, retries => 4;

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

