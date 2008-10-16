package QwitWeb;

use strict;
use warnings;

sub new {
    my $c = shift;
    my $model = shift;
    my $s = {};

    if (defined($model)) {
        bless($s, $c);
        $s->{'model'} = $model;
        return $s->init();
    }
    else {
        return undef;
    }
}

sub init {
    my $s = shift;

    return $s;
}

1;
