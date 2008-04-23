#!/usr/bin/perl

use strict;
use warnings;

our $VERSION = 0.10;

my $confFile = $ARGV[0] || 'qwit.config';

use Qwit;

print "Starting Qwit daemon version $VERSION with config file '$confFile'...\n";

my $qt = Qwit->new( configfile => "$confFile" );

sub catchsig { $qt->shutdown(); }
sub catchquit { $qt->forceRefresh(); }
$SIG{INT} = \&catchsig;
$SIG{TSTP} = \&catchquit;

print "Sleep delay: " . $qt->{'config'}->sleepDelay() . "\n";

$qt->runLoop();
