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
            
            $self->{'run'} = $self->{'delaymult'} = 1;
            $self->{'conn'} = Qwit::Twitter->new(%{ $self->{'config'}->twitterConf() });

            pdebugl(2, "Qwit got connection $self->{conn}");

            # create a model and attach it to the twitter object
            $self->{'model'} = Qwit::InMemoryModel->new($self->{'config'}->dbFile());
            $self->{'conn'}->attachModel($self->{'model'});
            return $self;
        }
    }

    return undef;
}

##########
# Command functions
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

        print "Processing '$t' from '$s'\n";

        my @words = split(/\s+/, $t);
        runQwitCommand($self, $i, $c, \@words);

        $self->{'model'}->setLastMsgId($msg->{'id'}) if ($msg->{'id'} > $self->{'model'}->lastMsgId());
    }
}

#########
sub runLoop {
    my $s = shift;
    my $dMult = 1;
    my $lastWake = 0;
    my $now = 0;

    $s->{'uptime'} = time();
    
    print "Reloading database...\n";
    $s->{'model'}->reloadDB();

    while ($s->{'run'}) {
        if ((($now = time()) - $lastWake) > ($s->{'config'}->sleepDelay() * $dMult)) {
            $lastWake = $now;
            pdebug("Awake...");

            if ($s->{'conn'}->checkFollowing()) {
                # send 'god' a message if we came out of a delay
                if ($dMult > 1) {
                    $s->{'conn'}->sendDmsg($s->{'config'}->god(),
                        "Connectivity re-restablished after a delay of " .
                            int(($s->{'config'}->sleepDelay() * $dMult) / 60) . " minutes.");

                    $dMult = 1;
                }

                $s->processMessages($s->{'conn'}->collectDmsgs([]));
            }
            else
            {
                # only bump the delay when we get a HTTP 400 back, which usually means we're rate limited
                $dMult *= $s->{'config'}->delayMult(), if ($s->{'conn'}->http_code() == 400);

                pdebug("Appears to be connectivity issues; bumping delay to " .
                    int(($s->{'config'}->sleepDelay() * $dMult) / 60) . " minutes.");
            }
        }

        sleep(1);
    }

    print "Quitting; dumping database...\n";
    $s->{'model'}->dumpDB();
    print "Done.\n";
}

sub shutdown {
    (shift)->{'run'} = 0;
}

1;
