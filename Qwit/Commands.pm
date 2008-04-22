package Qwit::Commands;

use Exporter qw(import);

@EXPORT = qw(runQwitCommand);

use strict;
use warnings;

use Time::Local qw(timelocal);

use Qwit::Debug;
use Qwit::Config;
use Qwit::InMemoryModel;
use Qwit::Twitter;

sub qwitCommandShutdown {
    my $s = shift;
    my $id = shift;

    if ($s->checkGodAuth($id)) {
        pdebug("Got an authorized shutdown qwitCommand; ending run...");
        $s->{'run'} = 0;
    }
}

sub qwitCommandStatus {
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

sub qwitCommandIncrement {
    my $s = shift;
    my ($id, $num, $create) = @_;

    my $uRef = $s->{'model'}->hashForID("$id");

    $uRef->{'total'} += $num;
    $uRef->{'last'} = time;
    push (@{$uRef->{'enum'}}, [ $num, $uRef->{'last'}, $create ]);  

    pdebug("Got '$num' from '$id'; new total is $uRef->{total}."); 

    unless ($uRef->{'options'}->{'quiet'}) {
        my $pl = ($num == 1) ? "that one" : "those $num";
        my $msg = "Including $pl, I've tracked $uRef->{'total'} cigarette(s) total for you.";
        $s->{'conn'}->sendDmsg("$id", "$msg");
    }

    $s->{'model'}->dumpDB();
}

sub qwitCommandToday {
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

sub qwitCommandQuietToggle {
    my $s = shift;
    my $id = shift;
    my $newVal = shift;

    $s->{'model'}->hashForID("$id")->{'options'}->{'quiet'} = $newVal;
    $s->{'model'}->dumpDB();
}

# this is the only exported method
sub runQwitCommand {
    my $s = shift;
    my ($id, $create, $wordsRef) = @_;

    my $cmd = $wordsRef->[0];

    if ($cmd =~ /(\d+)/) {
        qwitCommandIncrement($s, $id, $1, $create);
    }
    elsif ($cmd eq 'today') {
        qwitCommandToday($s, $id);
    }
    elsif ($cmd eq 'quiet') {
        qwitCommandQuietToggle($s, $id, 1);
        $s->{'conn'}->sendDmsg($id, 
            "Quiet mode enabled; will only respond to direct requests. Send 'loud' to disable.");
    }
    elsif ($cmd eq 'loud') {
        qwitCommandQuietToggle($s, $id, 0);
        $s->{'conn'}->sendDmsg($id, "Quiet mode disabled. Send 'quiet' to reenable.");
    }
    elsif ($cmd eq 'status') {
        qwitCommandStatus($s, $id);
    }
    elsif ($cmd eq 'shutdown') {
        qwitCommandShutdown($s, $id);
    }
}

1;
