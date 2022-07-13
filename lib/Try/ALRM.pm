package Try::ALRM;

use strict;
use warnings;

use Exporter 5.57 'import';
our @EXPORT = our @EXPORT_OK = qw(alarm try ALRM);

sub alarm (&;@) {
  my ($limit, $DO, $ALRM) = @_;
  local $SIG{ALRM} = $ALRM;
  CORE::alarm $limit->();
  $DO->();
  CORE::alarm 0;
}

sub try (&;@) {
  return @_;
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
    alarm { 5 }
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

=head1 OPTIONS

=head1 AUTHOR AND COPYRIGHT
