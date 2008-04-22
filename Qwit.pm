package Qwit;

use strict;
use warnings;
use Exporter qw(import);
use Time::Local qw(timelocal);

use Qwit::Twitter;
use Qwit::Debug;
use Qwit::Config;
use Qwit::InMemoryModel;

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
            $self->{'run'} = $self->{'delaymult'} = 1;
            $self->{'conn'} = Qwit::Twitter->new(%{ $self->{'config'}->twitterConf() });

            pdebug("Qwit got connection $self->{conn}");

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

sub commandShutdown {
    my $s = shift;
    my $id = shift;

    if ($s->checkGodAuth($id)) {
        pdebug("Got an authorized shutdown command; ending run...");
        $s->{'run'} = 0;
    }
}

sub commandStatus {
    my $s = shift;
    my $id = shift;

    if ($s->checkGodAuth($id)) {
        my $tDiff = time() - $s->{'uptime'};
        my $dS = $tDiff % 60;
        my $dM = int($tDiff / 60);
        my $dH = int($dM / 60);
        my $dD = int($dH / 24);

        my $str = "(status) Up since " . scalar(localtime($s->{'uptime'})) .
            " (${dD}d${dH}h${dM}m${dS}s).";
        $s->{'conn'}->sendDmsg($s->{'config'}->god(), $str);
    }
}

sub commandIncrement {
    my $s = shift;
    my ($id, $num, $create) = @_;

    pdebug("Got '$num' from '$id'; adding it to total"); 

    my $uRef = $s->{'model'}->hashForID("$id");

    $uRef->{'total'} += $num;
    $uRef->{'last'} = time;
    push (@{$uRef->{'enum'}}, [ $num, $uRef->{'last'}, $create ]);  

    unless ($uRef->{'options'}->{'quiet'}) {
        my $pl = ($num == 1) ? "that one" : "those $num";
        my $msg = "Including $pl, I've tracked $uRef->{'total'} cigarette(s) total for you.";
        $s->{'conn'}->sendDmsg("$id", "$msg");
    }

    $s->{'model'}->dumpDB();
}

sub commandToday {
    my $s = shift;
    my $id = shift;

    my @nowArr = localtime();
    my $cutoff = timelocal(0, 0, 0, $nowArr[3], $nowArr[4], $nowArr[5]);
    my $total = 0;
    pdebug("Cutoff timeval is $cutoff");

    my $h = $s->{'model'}->hashForID("$id");
    foreach my $en (@{$h->{'enum'}}) {
        my $num = $en->[0];
        my $time = $en->[1];

        $total += $num, if ($time >= $cutoff);
    }

    my $msg = "According to my records, you've smoked $total cigarette(s) today.";
    $s->{'conn'}->sendDmsg("$id", "$msg");
}

sub commandQuietToggle {
    my $s = shift;
    my $id = shift;
    my $newVal = shift;

    $s->{'model'}->hashForID("$id")->{'options'}->{'quiet'} = $newVal;
    $s->{'model'}->dumpDB();
}

sub runCommand {
    my $s = shift;
    my ($id, $create, $wordsRef) = @_;

    my $cmd = $wordsRef->[0];

    if ($cmd =~ /(\d+)/) {
        $s->commandIncrement($id, $1, $create);
    }
    elsif ($cmd eq 'today') {
        $s->commandToday($id);
    }
    elsif ($cmd eq 'quiet') {
        $s->commandQuietToggle($id, 1);
        $s->{'conn'}->sendDmsg($id, 
            "Quiet mode enabled; will only respond to direct requests. Send 'loud' to disable.");
    }
    elsif ($cmd eq 'loud') {
        $s->commandQuietToggle($id, 0);
        $s->{'conn'}->sendDmsg($id, "Quiet mode disabled. Send 'quiet' to reenable.");
    }
    elsif ($cmd eq 'status') {
        $s->commandStatus($id);
    }
    elsif ($cmd eq 'shutdown') {
        $s->commandShutdown($id);
    }
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
        $self->runCommand($i, $c, \@words);

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
            pdebugl(2, "Awake!");

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
                $dMult *= $s->{'config'}->delayMult();
                pdebug("Appears to be a connectivity issues; bumping delay to " .
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
