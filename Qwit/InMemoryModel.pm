package Qwit::InMemoryModel;

use strict;
use warnings;

use Qwit::Debug;
use Qwit::Config;

use Time::HiRes qw(gettimeofday tv_interval);
use Time::Local qw(timelocal);

use Fcntl ':flock';

our $DEFAULT_BACKUP_FREQ = 10;

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
    $s->{'lastBackup'} = 0;

    my $qc = Qwit::Config::singleton();
    $s->{'backupDir'} = $qc->backupDir() || '';
    $s->{'backupFreq'} = $qc->backupFreq() || $DEFAULT_BACKUP_FREQ;

    if ($s->{'file'}) {
        $s->reloadDB();
        return $s;
    }
    else {
        return undef;
    }
}

sub dumpDB {
    my $s = shift;
    my $t0 = [gettimeofday()];

    open (DBF, ">$s->{file}") or
        die "Couldn't open DB file '$s->{file}'! $!\n\n";

    flock(DBF, LOCK_EX) or 
        die "Unable to obtain LOCK_EX on $s->{file}: $!\n\n";

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

        # users options
        if ($u->{'options'}) {
            print DBF "O|$k";

            foreach my $optKey (keys %{$u->{'options'}}) {
                print DBF "|$optKey", if ($u->{'options'}->{"$optKey"});
            }

            print DBF "\n";
        }

        # users brands
        if ((my $b = $u->{brands}))
        {
            print DBF "B|$k";

            foreach my $bk (keys %{$b}) {
                print DBF "|$bk=$b->{$bk}";
            }

            print DBF "\n";
        }
    }

    flock(DBF, LOCK_UN);
    close (DBF);
    pdebugl(2, "dumpDB finished in " . tv_interval($t0) . " seconds.");
}

sub backupDB() {
    my $s = shift;
    my $bDir = $s->{backupDir};
    my $now = time();

    if (!$s->{lastBackup} || ($now - $s->{lastBackup} > $s->{backupFreq} * 60))
    {
        `mkdir -p $bDir`, if (defined($bDir) && !(-e $bDir));
        (my $lpc = $s->{file}) =~ s/.*\///ig;
        my $bStr = $bDir . ($bDir eq '' ? '' : '/') . ($bDir eq '' ? "$s->{file}" : $lpc) . "." . 
	    int(time() / ($s->{backupFreq} * 60)) . ".backup";

        pdebugl(2, "Backing database up to ${bStr}");
        `cp $s->{file} $bStr`;
	$s->{lastBackup} = $now;
    }
}

sub reloadDB() {
    my $s = shift;
    my $t0 = [gettimeofday()];
    my $f = $s->{'file'};

    if ($f && -e $f) {
        $s->backupDB();
        open (DBR, "$f") or die "reloadDB failed on $f: $!\n\n";

        flock(DBR, LOCK_SH) or 
            die "Unable to obtain LOCK_SH on $f: $!\n\n";

        my $db = $s->{'db'} = {};
        pdebugl(4, "Reloading database:");

        while (<DBR>) {
            chomp();
            my @i = split(/\|/);
            my $k = $i[0];

            if ($k eq 'LAST_ID') {
                $s->{'lastMsgId'} = $i[1];
                pdebugl(4, "LastMsgId is $s->{lastMsgId}");
            }
            elsif ($k eq 'E') {
                $k = $i[1];
                push (@{$db->{"$k"}->{'enum'}}, [ @i[2 .. $#i] ]);
            }
            elsif ($k eq 'O') {
                $k = $i[1];

                for (my $c = 2; $c < scalar(@i); $c++) {
                    $db->{"$k"}->{'options'}->{"$i[$c]"} = 1;
                }
            }
            elsif ($k eq 'B')
            {
                $k = $i[1];

                for (my $c = 2; $c < scalar(@i); $c++) {
                    my ($short, $brand) = split(/=/, $i[$c]);
                    $db->{"$k"}->{brands}->{"$short"} = $brand;
                }
            }
            else {
                $db->{"$k"}->{'total'} = $i[1];
                $db->{"$k"}->{'last'} = $i[2];
            }
        }

        flock(DBR, LOCK_UN);
        close (DBR);

        pdebugl(4, "Loaded " . scalar(keys(%{$db})) . " unique users");
    }

    pdebug("reloadDB finished in " . tv_interval($t0) . " seconds.");
}

# setters
# # # # # #

sub setLastMsgId {
    my $s = shift;
    my $lmi = shift;

    $s->{'lastMsgId'} = $lmi, if ($lmi);
    $s->dumpDB();
}

sub addBrandForID {
    my ($s, $id, $brand, $short) = @_;
    my $ret = undef;
    my $uh = undef;

    if ($s && $id && ($uh = $s->{'db'}->{"$id"}) && $brand && $short)
    {
        $uh->{brands} = {}, unless ($uh->{brands});
        $ret = $uh->{brands}->{"$short"} = $brand;
    }

    return $ret;
}

# getters 
# # # # # #
sub lookupBrandByShort {
    my ($s, $id, $short) = @_;
    my $uh = undef;

    if (($uh = $s->{'db'}->{"$id"}) && $uh->{brands})
    {
        return $uh->{brands}->{"$short"};
    }

    return undef;
}

sub brandsForID {
    my ($s, $id) = @_;

    return $s->{'db'}->{"$id"} ? $s->{'db'}->{"$id"}->{brands} : undef;
}

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

# returns an hash ref with keys 's', 'm', 'h', and 'd' if appropriate.
sub lastForID {
    my ($s, $id) = @_;
    my $r = undef; 

    if (my $diff = (time() - $s->{db}->{"$id"}->{last}))
    {
        $r = {};

        $r->{s} = $diff % 60;
        $r->{m} = int($diff / 60);
        $r->{h} = int($r->{m} / 60);
        $r->{d} = int($r->{h} / 24);

        $r->{m} %= 60;
        $r->{h} %= 24;

        # set to undef an values of 0, just in case
        foreach (keys (%{$r})) { $r->{$_} = undef, unless ($r->{$_}); }
    }

    return $r;
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
