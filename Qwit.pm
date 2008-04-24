package Qwit;

use strict;
use warnings;
use Exporter qw(import);
use Time::Local qw(timelocal);

use Qwit::Twitter;
use Qwit::Debug;
use Qwit::Config;
use Qwit::InMemoryModel;
use Qwit::Commands;

sub new {
    my $class = shift;
    my %conf = @_;
    my $self = {};

    bless($self, $class);

    $self->{'confHash'} = { %conf }, if (%conf);
    return $self->init();
}

sub init {
    my $self = shift;

    if ($self->{'confHash'}) {
        $self->{'config'} = Qwit::Config->new(%{ $self->{'confHash'} });

        if ($self->{'config'}) {
            if ((my $dbLvl = $self->{'config'}->debugLevel())) {
                Qwit::Debug::setDebugLevel($dbLvl);
            }

            $self->{'model'} = Qwit::InMemoryModel->new($self->{'config'}->dbFile());

            $self->{'run'} = $self->{'delaymult'} = 1;
            $self->{'conn'} = Qwit::Twitter->new($self->{'config'}, $self->{'model'});

            pdebugl(2, "Qwit got connection $self->{conn}");
            return $self;
        }
    }

    warn "Qwit::new unable to configure correctly.";
    return undef;
}

##########
# Misc functions
##########
sub checkGodAuth {
    my $s = shift;
    my $id = shift;

    return ($id == $s->{'config'}->god());
}

sub processMessages {
    my $self = shift;
    my $aref = shift;

    foreach my $msg (@{$aref}) {
        my $t = $msg->{'text'};
        my $s = $msg->{'sender_screen_name'};
        my $i = $msg->{'sender_id'};
        my $c = $msg->{'created_at'};

        qprint "Processing '$t' from '$s'";

        my @words = split(/\s+/, $t);
        runQwitCommand($self, $i, $c, \@words);

        $self->{'model'}->setLastMsgId($msg->{'id'}), if ($msg->{'id'} > $self->{'model'}->lastMsgId());
    }
}

#########
sub runLoop {
    my $s = shift;
    my $dMult = 1;
    my $now = 0;

    $s->{'uptime'} = time();
    $s->{'lastWake'} = 0;
    $s->{'lastFollowerCheck'} = 0;
    
    $s->{'model'}->reloadDB();

    while ($s->{'run'}) 
    {
        if (my $hbf = $s->{'config'}->heartbeatFile())
        {
            open (HBF, "+>./$hbf") or warn "hbfile $hbf: $!\n\n";
            print HBF "$s->{uptime} $s->{lastWake} $s->{lastFollowerCheck}";
            close (HBF);
        }

        if ((($now = time()) - $s->{'lastWake'}) > ($s->{'config'}->sleepDelay() * $dMult)) 
        {
            pdebugl(2, "Awake...");

            $s->{'lastWake'} = $now;
            my $errStr = undef;

            my @msgsRef = @{ $s->{'conn'}->collectDmsgs() };
            if ($s->{'conn'}->http_code() == 200)
            {
                if (($now - $s->{'lastFollowerCheck'}) > (30 * 60))
                {   # only run follower check twice an hour
                    pdebug("Checking for new followers...");

                    if ($s->{'conn'}->checkFollowing()) {
                        $s->{'lastFollowerCheck'} = $now;
                    }
                    else {
                        $errStr = "follower check"; 
                    }
                }

                if (scalar(@msgsRef))
                {
                    @msgsRef = reverse(@msgsRef);
                    $s->processMessages(\@msgsRef);
                }
            }
            else
            {
                $errStr = "direct message collection";
            }

            if (defined($errStr))
            {
                # only bump the delay when we get a HTTP 400 back, which usually means we're rate limited
                $s->{'lastErrorCode'} = $s->{'conn'}->http_code();
                $s->{'lastErrorMsg'} = $s->{'conn'}->http_message();
                $s->{'lastErrorStr'} = $errStr;

                $dMult *= $s->{'config'}->delayMult(), if ($s->{'lastErrorCode'} == 400);

                pdebug("Error in $errStr (HTTP $s->{lastErrorCode}); delay is now " .
                    sprintf("%0.1f", (($s->{'config'}->sleepDelay() * $dMult)
                    / 60)) . " minutes.");
            } 
            elsif ($dMult > 1)
            {
               $s->{'conn'}->sendDmsg($s->{'config'}->god(),
                    "Reconnected after " .
                     sprintf("%0.1f", (($s->{'config'}->sleepDelay() * $dMult)
                     / 60)) .
                     "m. Last error was '$s->{lastErrorCode}: " .
                     "$s->{lastErrorMsg}' in $s->{lastErrorStr}.");

                $dMult = 1;
            }
        }

        sleep(2);   # my webserver runs really fast, so 2 ~= 1 on it!
    }

    qprint "Quitting; dumping database...";
    $s->{'model'}->dumpDB();
    qprint "Done.\n";
}

sub forceRefresh {
    my $s = shift;

    qprint "Forcing refresh...";
    $s->{'model'}->dumpDB();

    # force refresh by pretending we never woke up before
    $s->{'lastWake'} = 0;
}

sub shutdown {
    (shift)->{'run'} = 0;
}

1;
