package Qwit::Twitter;

use warnings;
use strict;

use Qwit::Debug;
use Net::Twitter;
use Exporter qw(import);

use Data::Dumper;

our $RATE_RATIO_LOW_LIMIT = 0.25;
our $MIN_SLEEP_TIME_COEFF = 5;

sub new {
    my $class = shift;
    my $conf = shift;
    my $model = shift;
    my $self = {};

    if ($conf && $model) {
        bless($self, $class);

        $self->{'config'} = $conf;
        $self->{'model'} = $model;

        return $self->init();
    }

    warn "Qwit::Twitter::new needs args of Qwit::Config and a model.";
    return undef;
}

sub __update_rate_limit_info {
    my $self = shift;
    my $rls = $self->{conn}->rate_limit_status();

    $self->{reqInfo}->{limit} = $rls->{hourly_limit};
    $self->{reqInfo}->{remaining} = $rls->{remaining_hits};
    $self->{reqInfo}->{count} = $self->{reqInfo}->{limit} - $self->{reqInfo}->{remaining};
    $self->{reqInfo}->{resetTime} = $rls->{reset_time_in_seconds};
    $self->{reqInfo}->{lastRateRatio} = $self->{conn}->rate_ratio();

    pdebugl(4, "__update_rate_limit_info: " . Data::Dumper::Dumper($self->{reqInfo}));
}

sub init {
    my $self = shift;

    $self->{'conf'} = $self->{'config'}->twitterConf();
    $self->{'conn'} = Net::Twitter->new(%{ $self->{'conf'} });

    $self->{reqInfo} = {};
    $self->{reqInfo}->{contAdj} = $self->{reqInfo}->{last} = 0;
    $self->{reqInfo}->{lifecount} = 0;

    $self->__update_rate_limit_info();

    $self->{minTime} = $self->minSleepTimeAllowed();

    return $self;
}

sub numRequestsProcessed {
    return (shift)->{'reqInfo'}->{'lifecount'};
}

sub __accum_request {
    my $self = shift;

    $self->{'reqInfo'}->{'last'} = time();
    $self->{'reqInfo'}->{'count'}++;
    $self->{reqInfo}->{lifecount}++;
    $self->{reqInfo}->{remaining}--;

    my $intRm = $self->{reqInfo}->{limit} - $self->{reqInfo}->{count};
    pdebugl(1, "Internal count ($intRm) doesn't match external ($self->{reqInfo}->{remaining})"),
    	if ($intRm != $self->{reqInfo}->{remaining}); 

    $self->__update_rate_limit_info(), if (time() > $self->{reqInfo}->{resetTime});

    #push (  @{$self->{'reqInfo'}->{'enum'}}, 
    #        [ $self->{'reqInfo'}->{'count'}, $self->{'reqInfo'}->{'last'} ]);

    pdebugl(2, "Accumlated a request: now at $self->{reqInfo}->{count}");
}

sub __check_last_request {
    my $self = shift;
    my $code = $self->{'conn'}->http_code();
    
    if ($code >= 400) {
        qprint("Last request returned an HTTP error $code:");
        qprint("\t'" . $self->{'conn'}->http_message() . "'");

        return undef;
    }

    return ($code == 200);
}

sub __check_and_accum($) {
    my $self = shift;
    my $reqPassThru = shift;

    if ($self->__check_last_request()) {
        $self->__accum_request();
    } else {
        $reqPassThru = undef;
    }

    return $reqPassThru;
}

sub followers {
    my $self = shift;
    return $self->__check_and_accum($self->{'conn'}->followers());
}

sub following {
    my $self = shift;
    return $self->__check_and_accum($self->{'conn'}->friends());
}

# pass thrus
sub http_code { return (shift)->{'conn'}->http_code(); }
sub http_message { return (shift)->{'conn'}->http_message(); }

sub sendDmsg {
    my $s = shift;
    my $to = shift;
    my $msg = shift;

    return $s->{'conn'}->new_direct_message( { user => "$to", text => "$msg" } );
}

sub updateStatus {
    my $self = shift;
    my $msg = shift;

    return $self->__check_and_accum($self->{conn}->update($msg));
}

sub rateRatio {
    my $self = shift;
    return $self->{conn}->rate_ratio();
}

sub adjustSleepViaRateInfo($) {
    my $self = shift;
    my $sleep = shift;
    my $lowlim = $self->{minTime};
    my $rr = $self->{conn}->rate_ratio();
    my $ruone = $self->{conn}->until_rate(1.0);
    my $lrr = $self->{reqInfo}->{lastRateRatio};
    my $addr = 0;

    if ($rr < $self->{reqInfo}->{lastRateRatio} && $rr > 0.0)
    {
        my $diff = ($lrr - $rr) * 100.0;
        my $lnr = $lrr / $rr;
	    $addr = int(($diff * $ruone * $lnr) + 0.5 + $self->{reqInfo}->{contAdj});
	    pdebugl(3, " -- ratio has negative slope! rr = $rr, last = $lrr, contAdj = $self->{reqInfo}->{contAdj}");
	    pdebugl(3, " -- diff = $diff, lnr = $lnr, addr = $addr (ur = $ruone)");
	    $self->{reqInfo}->{contAdj} += 1.0;
    }
    else { 
        $self->{reqInfo}->{contAdj} = 0;
    }

    my $rv = ($rr > $RATE_RATIO_LOW_LIMIT ? int(($sleep * (1 / $rr)) + $addr) : $ruone);

    pdebugl(3, " -- adjustSleepViaRateInfo($sleep, $lowlim): with ratio == $rr && inv == ". 
        ($rr > 0 ? (1 / $rr) : "NaN") .", addr = $addr; adjusted value is $rv");

    $self->{reqInfo}->{lastRateRatio} = $rr;
    return ($rv < $lowlim ? $sleep : $rv);
}

sub minSleepTimeAllowed() {
    return int((((shift)->{reqInfo}->{limit} / 3600) + 1.5) * $MIN_SLEEP_TIME_COEFF);
}

sub collectDmsgs {
    my $s = shift;
    my $aRef = shift;
    $aRef = [], unless (defined($aRef));

    my $dmsgs = $s->__check_and_accum(
                    $s->{'conn'}->direct_messages( { since_id => $s->{'model'}->lastMsgId() } )
                    );

    pdebug("Found " . scalar(@{$dmsgs}) . " new dMessages; collecting."),
        if (defined($dmsgs) && scalar(@{$dmsgs}));

    foreach my $dmsg (@{$dmsgs}) {
        pdebugl(2, "New direct message id $dmsg->{id}.");
        push (@{$aRef}, $dmsg); 
    }

    return $aRef;
}

sub collectReplies {
    my $s = shift;
    my $aRef = shift;
    $aRef = [], unless (defined($aRef));

    my $replies = $s->{'conn'}->replies();

    foreach my $repl (@{$replies}) {
        if ($repl->{'id'} > $s->{'model'}->lastMsgId()) {
            pdebug("New \@reply id $repl->{id} found; collecting.");
            push(@{$aRef}, $repl);
        }
    }

    return $aRef;
}

sub checkFollowing {
    my $s = shift;

    my $ers = $s->followers();
    my $ing = undef;

    if (defined($ers) && defined($ing = $s->following())) 
    {
        if (scalar(@{$ers}) != scalar(@{$ing}))
        {
            pdebug("Er/Ing counts are different.");

            foreach my $ersOne (@{$ers})
            {
                my $matched = 0;

                foreach my $ingOne (@{$ing})
                {
                    pdebug("Looking at er '$ersOne->{'name'}' vs. ing '$ingOne->{'name'}'");

                    last, if ($matched = ($ersOne->{'id'} == $ingOne->{'id'}));
                }

                if (!$matched)
                {
                    pdebug("Looks like '$ersOne->{'name'}' (ID $ersOne->{'id'}) is a new follower; following!");

                    $s->{'conn'}->follow($ersOne->{'id'});

                    my $msg = "Hello $ersOne->{'name'}: I'm now following you as well!";
                    $s->sendDmsg("$ersOne->{'id'}", "$msg");

                    my $url = defined($ersOne->{'url'}) ? "url $ersOne->{url};" : "";

                    $s->sendDmsg($s->{'config'}->god(),
                     "I'm now following $ersOne->{name} " .
                     "($ersOne->{screen_name}); " .
                     "$url $ersOne->{followers_count} followers");
                        
                        
                }
            }
        }
    }

    return defined($ers) && defined($ing);
}

1;
