
use strict;
use warnings;

my $TIMEOUT = 60;
my $RETRIES = 3;

sub retry(&;@) {
    my ( $code, $ALRM, $FINALLY, %opts ) = @_;
    my $retries = $opts{retries} // $RETRIES;
    my $timeout = $opts{timeout} // $TIMEOUT;
    my ( $attempts, $succeeded );
    for my $attempt ( 1 .. $retries ) {
        my $retry = 0;
        local $SIG{ALRM} = sub {
            ++$retry;
            $attempts = $attempt;
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
# need to check arg count to make this optional
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
    sleep 3;
}
ALRM {
    my ( $attempt, $limit ) = @_;
    printf qq{\tTIMED OUT - Retrying ...\n};
}
finally {
    my ( $attempt, $limit, $ultimately_succeeded ) = @_;
    printf qq{%s after %d/%d attempt%s\n}, ($ultimately_succeeded) ? q{OK} : q{NOT OK}, $attempt, $limit, ( $attempt == 1 ) ? q{} : q{s};
}
timeout => 3, retries => 4;
