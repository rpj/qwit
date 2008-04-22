package Qwit::Debug;

use POSIX qw(strftime);
use Exporter qw(import);

@EXPORT = qw(pdebug pdebugl);

our $__DEBUG = 2;

sub pdebug($) {
    my $str = shift;
    print STDERR "DEBUG " . (strftime("%a %b %e %H:%M:%S %Y", localtime)) .
        " >> $str\n", if ($__DEBUG);
}

sub pdebugl($$) {
    my ($level, $str) = @_;
    pdebug($str), if ($level <= $__DEBUG);
}

sub setDebugLevel {
    $__DEBUG = shift;
}

1;
