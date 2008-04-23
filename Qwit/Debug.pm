package Qwit::Debug;

use POSIX qw(strftime);
use Exporter qw(import);

@EXPORT = qw(pdebug pdebugl qprint);

our $__DEBUG = 2;

sub __prependString {
    my $pch = shift || "-";
    return "$0 - " . (strftime("%a %b %e %H:%M:%S %Y", localtime)) . " ${pch}> ";
}

sub qprint($) {
    print __prependString() . (shift) . "\n";
}
sub pdebug($) {
    print STDERR __prependString($__DEBUG) . (shift) . "\n", if ($__DEBUG);
}

sub pdebugl($$) {
    my ($level, $str) = @_;
    pdebug($str), if ($level <= $__DEBUG);
}

sub setDebugLevel {
    $__DEBUG = shift;
}

1;
