package Qwit::Commands;

use Exporter qw(import);

@EXPORT = qw(runQwitCommand);

use strict;
use warnings;

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
            " (${dD}d${dH}h${dM}m${dS}s). " . $s->{'conn'}->numRequestsProcessed() .
            " requests.";

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
        my $today = $s->{'model'}->numTodayForID($id);
        my $pl = ($num == 1) ? "that one" : "those $num";

        my $msg = "Including $pl, you've smoked $today cigarette(s) today, $uRef->{total} total.";
        $s->{'conn'}->sendDmsg("$id", "$msg");
    }

    $s->{'model'}->dumpDB();
}

sub qwitCommandToday {
    my $s = shift;
    my $id = shift;

    my $total = $s->{'model'}->numTodayForID($id);

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

sub qwitCommandTotal {
    my ($s, $id) = @_;

    $s->{'conn'}->sendDmsg("$id",
        "According to my records, you've smoked " .
        $s->{'model'}->numTotalForID($id) . " cigarette(s) total.");
}

sub qwitCommandRateToday {
    my ($s, $id) = @_;

    $s->{'conn'}->sendDmsg("$id",
        "Your smoking rate today has been " .
        sprintf("%0.3f", ($s->{'model'}->rateTodayForID($id) / 60 / 60)) .
        " cigarette(s)/hour.");
}

sub qwitCommandRateTotal {
    my ($s, $id) = @_;

    $s->{'conn'}->sendDmsg("$id",
        "Your smoking rate in total has been " .
        sprintf("%0.3f", ($s->{'model'}->rateTotalForID($id) / 60 / 60)) .
        " cigarette(s)/hour.");
}

sub qwitCommandHelp {
    my ($s, $id) = @_;

    $s->{'conn'}->sendDmsg("$id",
        "Available commands: " .
        "today, total, loud, quiet, help, ratetoday, ratetotal, [num] " .
        "(send the number you smoked)");
}

# this is the only exported method
sub runQwitCommand {
    my $s = shift;
    my ($id, $create, $wordsRef) = @_;

    my $cmd = $wordsRef->[0];

    if ($cmd =~ /(\d+)/) 
    {
        qwitCommandIncrement($s, $id, $1, $create);
    }
    elsif ($cmd eq 'today') 
    {
        qwitCommandToday($s, $id);
    }
    elsif ($cmd eq 'quiet') 
    {
        qwitCommandQuietToggle($s, $id, 1);
        $s->{'conn'}->sendDmsg($id, 
            "Quiet mode enabled; will only respond to direct requests. Send 'loud' to disable.");
    }
    elsif ($cmd eq 'loud') 
    {
        qwitCommandQuietToggle($s, $id, 0);
        $s->{'conn'}->sendDmsg($id, "Quiet mode disabled. Send 'quiet' to reenable.");
    }
    elsif ($cmd eq 'total') 
    {
        qwitCommandTotal($s, $id);
    }
    elsif ($cmd eq 'help') 
    {
        qwitCommandHelp($s, $id);
    }
    elsif ($cmd eq 'ratetoday')
    {
        qwitCommandRateToday($s, $id);
    }
    elsif ($cmd eq 'ratetotal')
    {
        qwitCommandRateTotal($s, $id);
    }
    elsif ($cmd eq 'status') 
    {
        qwitCommandStatus($s, $id);
    }
    elsif ($cmd eq 'shutdown') 
    {
        qwitCommandShutdown($s, $id);
    }
}

1;
