package Qwit::InMemoryModel;

use strict;
use warnings;

use Qwit::Debug;
use Time::HiRes qw(gettimeofday tv_interval);
use Time::Local qw(timelocal);

sub new {
    my $c = shift;
    my $sFile = shift;
    my $s = {};

    bless ($s, $c);
    $s->{'file'} = $sFile;

    return $s->init();
}

sub init {
    my $s = shift;

    $s->{'db'} = {};
    $s->{'lastMsgId'} = 0;

    return $s;
}

sub dumpDB {
    my $s = shift;
    my $t0 = [gettimeofday()];

    open (DBF, ">$s->{file}") or
        die "Couldn't open DB file '$s->{file}'! $!\n\n";

    print DBF "LAST_ID|$s->{lastMsgId}\n";

    my $db = $s->{'db'};
    foreach my $k (keys (%{$db})) {
        my $u = $db->{"$k"};
        
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
    pdebug("dumpDB finished in " . tv_interval($t0) . " seconds.");
}

sub reloadDB() {
    my $s = shift;
    my $t0 = [gettimeofday()];
    my $f = $s->{'file'};

    if ($f && -e $f) {
        my $bStr = ".$f." . time()  . ".backup";
        `cp $f $bStr`;

        open (DBR, "$f");

        my $db = $s->{'db'} = {};
        pdebug("Reloading database:");

        while (<DBR>) {
            chomp();
            my @i = split(/\|/);
            my $k = $i[0];

            if ($k eq 'LAST_ID') {
                $s->{'lastMsgId'} = $i[1];
                pdebug("LastMsgId is $s->{lastMsgId}");
            }
            elsif ($k eq 'E') {
                $k = $i[1];
                push (@{$db->{"$k"}->{'enum'}}, [ @i[2 .. $#i] ]);
            }
            elsif ($k eq 'O') {
                $k = $i[1];

                my $c = 2;
                for ($c = 2; $c < scalar(@i); $c++) {
                    $db->{"$k"}->{'options'}->{"$i[$c]"} = 1;
                }
            }
            else {
                $db->{"$k"}->{'total'} = $i[1];
                $db->{"$k"}->{'last'} = $i[2];
            }
        }

        close (DBR);

        pdebug("Loaded " . scalar(keys(%{$db})) . " unique users");
    }

    pdebug("reloadDB finished in " . tv_interval($t0) . " seconds.");
}

# setters
# # # # # #

sub setLastMsgId {
    my $s = shift;
    my $lmi = shift;

    $s->{'lastMsgId'} = $lmi;
}

# getters 
# # # # # #
sub lastMsgId {
    return (shift)->{'lastMsgId'};
}

sub hashForID {
    my $s = shift;
    my $id = shift;

    $s->{'db'}->{"$id"} = {}, unless (defined($s->{'db'}->{"$id"}));

    return $s->{'db'}->{"$id"};
}

sub numTotalForID {
    my ($s, $id) = @_;

    return $s->{'db'}->{"$id"}->{'total'};
}

sub numTodayForID {
    my $s = shift;
    my $id = shift;

    my @nowArr = localtime();
    my $cutoff = timelocal(0, 0, 0, $nowArr[3], $nowArr[4], $nowArr[5]);
    my $total = 0;

    my $h = $s->{'db'}->{"$id"};
    foreach my $en (@{$h->{'enum'}}) {
        my $num = $en->[0];
        my $time = $en->[1];

        $total += $num, if ($time >= $cutoff);
    }

    return $total;
}

sub totalNumUsers {
    my $s = shift;

    return scalar(keys(%{ $s->{'db'} }));
}

sub recordsForID {
    my ($s, $id) = @_;

    return @{ $s->{'db'}->{"$id"}->{'enum'} };
}

sub numRecordsForID {
    my ($s, $id) = @_;

    return scalar($s->recordsForID($id));
}

sub rateTodayForID {
    my ($s, $id) = @_;
    my @nowArr = localtime();
    my $cutoff = timelocal(0, 0, 0, $nowArr[3], $nowArr[4], $nowArr[5]);

    return $s->rateSinceCutoffForID($id, $cutoff);
}

sub rateTotalForID {
    my ($s, $id) = @_;
    return $s->rateSinceCutoffForID($id, 0);
}

sub rateSinceCutoffForID {
    my ($s, $id, $cutoff) = @_;
    my $rateRet = 0;

    if ($s && $id) {
        my $count = 0;
        my $last = 0;
        my $accum = 0;

        # accumulate totals if the record has a timestamp >= cutoff time
        foreach my $item ($s->recordsForID($id)) 
        {
            my $itime = $item->[1];

            if ($itime >= $cutoff)
            {
                if ($last != 0 && $itime >= $last) {
                    $accum += ($itime - $last);
                    $count++;
                }
                
                $last = $itime;
            }
        }
        
        $rateRet = $accum / $count, if ($count);
    }

    return $rateRet;
}

1;
