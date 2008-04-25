#!/usr/bin/perl

use strict;
use warnings;

our $VERSION = 0.45;

my $confFile = $ARGV[0] || 'qwit.config';

use Qwit;
use Qwit::Debug;

qprint "Starting Qwit daemon version $VERSION with config file '$confFile'...";

my $qt = Qwit->new( configfile => "$confFile" );

sub catchsig { $qt->shutdown(); }
sub catchquit { $qt->forceRefresh(); }
$SIG{INT} = \&catchsig;
$SIG{TSTP} = \&catchquit;

qprint "Sleep delay: " . $qt->{'config'}->sleepDelay();

$qt->runLoop();
