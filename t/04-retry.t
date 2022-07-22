use warnings;
use strict;

use Test::More tests => 13;

BEGIN {
    use_ok q{Try::ALRM};
}

is timeout, $Try::ALRM::TIMEOUT, sprintf( qq{default timeout is %d seconds}, timeout );
ok timeout(5), q{'timeout' method called as "setter" without issue};
is 5, $Try::ALRM::TIMEOUT, sprintf( qq{default timeout is %d seconds}, timeout );

retry {
    my ( $attempt, $limit ) = @_;
    printf qq{Attempt %d/%d of something that might take more than 3 second\n}, $attempt, $limit;
    sleep 3;
}
ALRM {
    my ( $attempt, $limit ) = @_;
    ok $attempt <= $limit, qq{retry attempt <= limit, $attempt <= $limit};
    note qq{\tTIMED OUT - Retrying ...\n};
}
finally {
    my ( $attempt, $limit, $ultimately_succeeded ) = @_;
    is $attempt, $limit, qq{expected number of retries found ($limit)};
}
timeout => 1, retries => 2;

is 5, $Try::ALRM::TIMEOUT, sprintf( qq{default timeout is %d seconds}, timeout );

retry {
    my ( $attempt, $limit ) = @_;
    printf qq{Attempt %d/%d of something that might take more than 3 second\n}, $attempt, $limit;
    sleep 3;
}
ALRM {
    my ( $attempt, $limit ) = @_;
    ok $attempt <= $limit, qq{retry attempt <= limit, $attempt <= $limit};
    note qq{\tTIMED OUT - Retrying ...\n};
}
timeout => 1, retries => 2;

retry {
    my ( $attempt, $limit ) = @_;
    printf qq{Attempt %d/%d of something that might take more than 3 second\n}, $attempt, $limit;
    sleep 3;
}
finally {
    my ( $attempt, $limit, $ultimately_succeeded ) = @_;
    is $attempt, $limit, qq{expected number of retries found ($limit)};
}
timeout => 1, retries => 2;

retry {
    my ( $attempt, $limit ) = @_;
    ok $attempt <= $limit, qq{retry attempt <= limit, $attempt <= $limit};
    sleep 3;
} timeout => 1, retries=> 2;
