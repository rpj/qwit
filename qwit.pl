#!/usr/bin/perl

use strict;
use warnings;

our $VERSION = 0.10;

use Qwit;

print "Starting Qwit daemon version $VERSION...\n";

my $qt = Qwit->new( configfile => 'qwit.config' );

sub catchsig { $qt->shutdown(); }
$SIG{INT} = \&catchsig;

print "Sleep delay: " . $qt->{'config'}->sleepDelay() . "\n";

print "Starting main run loop...\n";
$qt->runLoop();
