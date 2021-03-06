package Qwit::Commands;

use Exporter qw(import);

@EXPORT = qw(runQwitCommand);

use strict;
use warnings;
use POSIX qw(strftime);

use Qwit::Debug;
use Qwit::Config;
use Qwit::InMemoryModel;
use Qwit::Twitter;

sub __pluralize {
    my ($n, $str) = @_;
    my $r = "";

    $r = ("$n " . ($n == 1 ? $str : "${str}s") . " "), if (defined($n));
    return $r;
}

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

    # bad way to ensure no div/0 later, but what's one second?
    my $tDiff = (time() - $s->{'uptime'}) + 1;
    my $dS = $tDiff % 60;
    my $dM = int($tDiff / 60);
    my $dH = int($dM / 60);
    my $dD = int($dH / 24);
    $dM %= 60;
    $dH %= 24;

    my $numReqs = $s->{'conn'}->numRequestsProcessed();
    my $sUptime = scalar(localtime($s->{'uptime'}));
    $sUptime =~ s/\:\d\d\s+\d{4}$//ig;

    my $str = "(status) Up since $sUptime" .
        ", ${dD}d${dH}h${dM}m${dS}s; $numReqs reqs, ~" .
        sprintf("%0.1f", +($numReqs / ($tDiff / 60 / 60))) . "/hr; " . 
        $s->{'model'}->totalNumUsers() . 
        " users; " . sprintf("%0.1f", ($s->{'config'}->sleepDelay() / 60)) . "m delay.";

    $s->{'conn'}->sendDmsg($s->{'config'}->god(), $str);
}

sub qwitCommandConfig {
    my $s = shift;
    my $id = shift;
    my $wordsRef = shift;
    my $gMsg = undef; 

    if (scalar(@{ $wordsRef }) >= 1)
    {
        my $keyToChg = shift(@{ $wordsRef });

        if ($s->{'config'}->isKeyModifiable($keyToChg))
        {
            my $newVal = join(" ", @{ $wordsRef });

            if ($s->{'config'}->setAllowedKey($keyToChg, $newVal)) {
                $gMsg = "Config key '$keyToChg' has new value '$newVal'.";
            } else {
                $gMsg = "Error setting '$keyToChg' to '$newVal'.";
            }

            pdebug("$gMsg");
        }
        elsif ($keyToChg eq 'list')
        {
            $gMsg = "(config list) debuglevel " . $s->{'config'}->debugLevel() . 
                "; sleepdelay " . $s->{'config'}->sleepDelay() . ".";
        }

        $s->{'conn'}->sendDmsg($s->{'config'}->god(), $gMsg), if (defined($gMsg));
    }
}

sub qwitCommandIncrement {
    my $s = shift;
    my ($id, $num, $create, $words) = @_;

    my $uRef = $s->{'model'}->hashForID("$id");

    my $lr = $s->{'model'}->lastForID($id);

    $uRef->{'total'} += $num;
    $uRef->{'last'} = time;

    my @pushArr = ($num, $uRef->{last}, $create);
    my $addStr = "";

    if (scalar(@{$words}) && (my $sc = $words->[0]))
    {
        if ($s->{'model'}->lookupBrandByShort($id, $sc))
        {
            push (@pushArr, $sc); 
        }
        else
        {
            $addStr = " (Err: invalid brand)";
        }
    }

    push (@{$uRef->{'enum'}}, \@pushArr);

    pdebug("Got '$num' from '$id'; new total is $uRef->{total}."); 

    unless ($uRef->{'options'}->{'quiet'}) {
        my $today = $s->{'model'}->numTodayForID($id);
        my $pl = ($num == 1) ? "that one" : "those $num";

        $lr->{m}++, if (!$lr->{m} && !$lr->{h} && !$lr->{d});
        my $lstr = __pluralize($lr->{d}, "day") . __pluralize($lr->{h}, "hr") .
            __pluralize($lr->{m}, "min");

        my $msg = "Including $pl, you've smoked $today cigarette(s) today. " .
            "Your last was ${lstr}ago.$addStr";
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
        "Smoking rate today has been " .
        sprintf("%0.3f", ($s->{'model'}->rateTodayForID($id) / 60 / 60)) .
        " hours between cigarettes.");
}

sub qwitCommandRateTotal {
    my ($s, $id) = @_;

    $s->{'conn'}->sendDmsg("$id",
        "Smoking rate in total has been " .
        sprintf("%0.3f", ($s->{'model'}->rateTotalForID($id) / 60 / 60)) .
        " hours between cigarettes.");
}

sub qwitCommandHelp {
    my ($s, $id) = @_;

    $s->{'conn'}->sendDmsg("$id",
        "Available commands: " .
        "today, total, loud, quiet, help, ratetoday, ratetotal, stats, last, [num]");
}

sub qwitCommandStats {
    my ($s, $id) = @_;

    my $rToday = sprintf("%0.1f", $s->{'model'}->rateTodayForID($id) / 60 / 60);
    my $rTotal = sprintf("%0.1f", $s->{'model'}->rateTotalForID($id) / 60 / 60);

    my $uh = $s->{'model'}->hashForID($id);
    my $total = $uh->{'total'};
    my $today = $s->{'model'}->numTodayForID($id);

    my $now = time();

    my @recs = $s->{'model'}->recordsForID($id);
    my $firstDiff = $now - $recs[0]->[1];
    my $firstMin = int($firstDiff / 60);
    my $firstHr = int($firstMin / 60);
    my $firstDay = int($firstHr / 24);
    $firstMin %= 60;
    $firstHr %= 24;

    my $firstStr = sprintf("%0.2f days ago", ($firstDiff / 60.0 / 60.0 /24.0));

    my $lr = $s->{'model'}->lastForID($id);
    $lr->{m}++, if (!$lr->{m} && !$lr->{h} && !$lr->{d});
    my $lstr = __pluralize($lr->{d}, "day") . __pluralize($lr->{h}, "hr") .
        __pluralize($lr->{m}, "min"); 

    $s->{'conn'}->sendDmsg("$id",
        "(stats) $total smoked, $today today; $rTotal hr/cig total; $rToday hr/cig today; " .
        "last was ${lstr}ago; first was $firstStr");
}

sub qwitCommandLast {
    my ($s, $id) = @_;
    my $msg = undef;

    if (my $lr = $s->{'model'}->lastForID($id))
    {
        $msg = "Your last cigarette was " .
            __pluralize($lr->{d}, "day") .
            __pluralize($lr->{h}, "hour") . ($lr->{h} ? "and " : "") . 
            __pluralize($lr->{m}, "minute") . "ago.";
    }
    else
    {
        $msg = "Don't have a last cigarette on record.";
    }

    $s->{'conn'}->sendDmsg("$id", "$msg"), if (defined($msg));
}
    
sub qwitCommandBrand {
    my ($s, $id, $words) = @_;

    if ($s && $id && $words)
    { 
        if (scalar(@{$words}) >= 2)
        {
            my $short = $words->[0];
            my $brand = join(" ", @{$words}[1 .. $#{$words}]);

            pdebugl(2, "New brand '$brand' (short '$short') for $id");
            if ($s->{'model'}->addBrandForID($id, $brand, $short))
            {
                $s->{'conn'}->sendDmsg("$id",
                    "New brand '$brand' added with shortcode '$short': " .
                    "use this code when updating.");
            }
            else
            {
                $s->{'conn'}->sendDmsg("$id", "Unable to add brand '$brand'.");
            }
        }
        else
        {
            my $str = "Your current brands: ";
            my $brs = $s->{'model'}->brandsForID($id);
            $str .= "$brs->{$_} ($_); ", foreach (keys(%{$brs}));

            $s->{conn}->sendDmsg("$id", $str);
        }
    }
}

# this is the only exported method
sub runQwitCommand {
    my $s = shift;
    my ($id, $create, $wordsRef) = @_;

    my $cmd = shift(@{ $wordsRef });

    if ($cmd =~ /(\d+)/) 
    {
        qwitCommandIncrement($s, $id, $1, $create, $wordsRef);
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
    elsif ($cmd eq 'stats')
    {
        qwitCommandStats($s, $id);
    }
    elsif ($cmd eq 'last')
    {
        qwitCommandLast($s, $id);
    }
    elsif ($cmd eq 'brand')
    {
        qwitCommandBrand($s, $id, $wordsRef);
    }

    # "god" commands
    if ($s->checkGodAuth($id))
    {
        if ($cmd eq 'config')
        {
            qwitCommandConfig($s, $id, $wordsRef);
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
}

1;
