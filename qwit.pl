#!/usr/bin/perl -w

use strict;
use Net::Twitter;
use Data::Dumper;
use POSIX qw(strftime);
use Time::Local;

my $_DEBUG = 1;

my $_t = Net::Twitter->new( username => 'qwit', 
                            password => 'AgxX7y1Sv',
                            clientname => 'QwitBot');

print "Got Net::Twitter object $_t\n\n";
my $god = 1078071;

# things that shouldn't really be global
my $g_LastMsgId = 0;
my $g_Smokers = {};
my $g_Run = 1;
my $g_SerializeFile = 'qwitProd.seralize';
my $g_BaseDelay = 5 * 60;
my $g_UpTime = time();

##########
# Debug and misc functions
##########
sub pdebug($) {
    my $str = shift;
    print STDERR "DEBUG " . (strftime("%a %b %e %H:%M:%S %Y", localtime)) .
        " >> $str\n", if ($_DEBUG);
}

##########
# Twitter functions to check followers and gather messages
##########
sub check_following($) {
    my $tObj = shift;

    my $ers = $tObj->followers();
    my $ing = undef;

    if (defined($ers) && defined($ing = $tObj->following())) 
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

                    $tObj->follow($ersOne->{'id'});

                    my $msg = "Hello $ersOne->{'name'}: I'm now following you as well!";
                    $tObj->new_direct_message( { user => "$ersOne->{'id'}", text => "$msg" } );
                }
            }
        }
    }

    return defined($ers) && defined($ing);
}

sub check_direct_messages($) {
    my $aRef = shift;

    my $dmsgs = $_t->direct_messages( { since_id => $g_LastMsgId } );

    foreach my $dmsg (@{$dmsgs}) {
        pdebug("New direct message id $dmsg->{id} found; pushing.");
       push (@{$aRef}, $dmsg); 
    }

    return $aRef;
}

sub check_replies($) {
    my $aRef = shift;

    my $replies = $_t->replies();

    foreach my $repl (@{$replies}) {
        if ($repl->{'id'} > $g_LastMsgId) {
            pdebug("New \@reply id $repl->{id} found; pushing.");
            push(@{$aRef}, $repl);
        }
    }

    return $aRef;
}

##########
# Serialization functions; for data persistence
##########
sub dump_db() {
    open (DBF, "+>$g_SerializeFile") or
        die "Couldn't open DB file! $!\n\n";

    print DBF "LAST_ID|$g_LastMsgId\n";

    foreach my $k (keys (%{$g_Smokers})) {
        my $u = $g_Smokers->{"$k"};
        
        print DBF "$k|$u->{'total'}|$u->{'last'}\n";

        foreach my $enumed (@{$u->{'enum'}}) {
            print DBF "E|$k";
            print DBF "|$_", foreach (@{$enumed});
            print DBF "\n";
        }

        if ($u->{'options'}) {
            print DBF "O|$k";

            foreach my $optKey (keys %{$u->{'options'}}) {
                print DBF "|$optKey", if ($u->{'options'}->{"$optKey"});
            }

            print DBF "\n";
        }
    }

    close (DBF);
}

sub reload_db() {
    if (-e $g_SerializeFile) {
        my $bStr = ".$g_SerializeFile." . time()  . ".backup";
        `cp $g_SerializeFile $bStr`;
        open (DBR, "$g_SerializeFile");

        $g_Smokers = {};
        pdebug("Reloading database:");

        while (<DBR>) {
            chomp();
            my @i = split(/\|/);
            my $k = $i[0];

            if ($k eq 'LAST_ID') {
                $g_LastMsgId = $i[1];
                pdebug("LastMsgId is $g_LastMsgId");
            }
            elsif ($k eq 'E') {
                $k = $i[1];
                push (@{$g_Smokers->{"$k"}->{'enum'}}, [ @i[2 .. $#i] ]);
            }
            elsif ($k eq 'O') {
                $k = $i[1];

                my $c = 2;
                for ($c = 2; $c < scalar(@i); $c++) {
                    $g_Smokers->{"$k"}->{'options'}->{"$i[$c]"} = 1;
                }
            }
            else {
                $g_Smokers->{"$k"}->{'total'} = $i[1];
                $g_Smokers->{"$k"}->{'last'} = $i[2];
            }
        }

        close (DBR);

        pdebug("Loaded " . scalar(keys(%{$g_Smokers})) . " unique users");
    }

    pdebug("DB reload complete.");
}

##########
# Command functions
##########
sub command_shutdown($) {
    my $id = shift;

    if ($id == $god) {
        pdebug("Got an authorized shutdown command; ending run...");
        $g_Run = 0;
    }
}

sub command_status($) {
    my $id = shift;

    if ($id == $god) {
        my $tDiff = time() - $g_UpTime;
        my $dS = $tDiff % 60;
        my $dM = int($tDiff / 60);
        my $dH = int($dM / 60);
        my $dD = int($dH / 24);

        my $str = "(status) Up since " . scalar(localtime($g_UpTime)) .
            " (${dD}d${dH}h${dM}m${dS}s).";
        $_t->new_direct_message({ user => $god, text => $str});
    }
}

sub command_increment($$$) {
    my ($id, $num, $create) = @_;

    pdebug("Got '$num' from '$id'; adding it to total"); 

    my $uRef = $g_Smokers->{"$id"};
    
    $uRef = $g_Smokers->{"$id"} = {}, unless (defined($uRef));

    $uRef->{'total'} += $num;
    $uRef->{'last'} = time;
    push (@{$uRef->{'enum'}}, [ $num, $uRef->{'last'}, $create ]);  

    unless ($g_Smokers->{"$id"}->{'options'}->{'quiet'}) {
        my $pl = ($num == 1) ? "that one" : "those $num";
        my $msg = "Including $pl, I've tracked $uRef->{'total'} cigarette(s) total for you.";
        $_t->new_direct_message( { user => "$id", text => "$msg" } );
    }
}

sub command_today($) {
    my $id = shift;

    my @nowArr = localtime();
    my $cutoff = timelocal(0, 0, 0, $nowArr[3], $nowArr[4], $nowArr[5]);
    my $total = 0;
    pdebug("Cutoff timeval is $cutoff");

    foreach my $en (@{$g_Smokers->{"$id"}->{'enum'}}) {
        my $num = $en->[0];
        my $time = $en->[1];

        $total += $num, if ($time >= $cutoff);
    }

    my $msg = "According to my records, you've smoked $total cigarette(s) today.";
    $_t->new_direct_message( { user => "$id", text => "$msg" } );
}

sub command_quiet_toggle($$) {
    my $id = shift;
    my $newVal = shift;

    $g_Smokers->{"$id"}->{'options'}->{'quiet'} = $newVal;
}

##########
# Message processing
##########
sub run_command($$$) {
    my ($id, $create, $wordsRef) = @_;

    my $cmd = $wordsRef->[0];

    if ($cmd =~ /(\d+)/) {
        command_increment($id, $1, $create);
    }
    elsif ($cmd eq 'today') {
        command_today($id);
    }
    elsif ($cmd eq 'quiet') {
        command_quiet_toggle($id, 1);
        $_t->new_direct_message({ user => $id, text =>
            "Quiet mode enabled; will only respond to direct requests. Send 'loud' to disable." });
    }
    elsif ($cmd eq 'loud') {
        command_quiet_toggle($id, 0);
        $_t->new_direct_message({ user => $id, text => 
            "Quiet mode disabled. Send 'quiet' to reenable."});
    }
    elsif ($cmd eq 'status') {
        command_status($id);
    }
    elsif ($cmd eq 'shutdown') {
        command_shutdown($id);
    }
}

sub process_messages($) {
    my $aref = shift;

    foreach my $msg (@{$aref}) {
        my $t = $msg->{'text'};
        my $s = $msg->{'sender_screen_name'};
        my $i = $msg->{'sender_id'};
        my $c = $msg->{'created_at'};

        print "Processing '$t' from '$s'\n";

        my @words = split(/\s+/, $t);
        run_command($i, $c, \@words);

        $g_LastMsgId = $msg->{'id'}, if ($msg->{'id'} > $g_LastMsgId);
    }
}

##########
# Signal handler; SIGINT caught automatically shuts the daemon down
##########
sub catch_sigint {
    my $signame = shift;

    command_shutdown($god);
}

##########
# Entry point
##########

$SIG{INT} = \&catch_sigint;

print "Reloading DB...\n";
reload_db();

my $delayMult = 1;
print "Starting main run loop with base delay of " .
    ($g_BaseDelay / 60) . " minutes between iterations.\n";

while ($g_Run) {
    if (check_following($_t)) {
        if ($delayMult > 1) {
            $_t->new_direct_message({ user => $god,
                text => "Connectivity re-established after delay of " .
                    ($delayMult / 60) . " minutes."});

            $delayMult = 1;
        }

        process_messages(check_replies(check_direct_messages([])));
    }
    else {
        $delayMult *= 2;
        pdebug("There appears to be a connectivity issue, bumping delay to " .
            ($g_BaseDelay * $delayMult) . " seconds (${delayMult}x)...");
    }

    sleep(($g_BaseDelay * $delayMult)), if ($g_Run);
}

# will always dump the database upon exiting (gracefully, that is)
print "Quitting; dumping DB.\n";
dump_db();
