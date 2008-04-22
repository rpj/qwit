package Qwit::InMemoryModel;

use strict;
use warnings;

use Qwit::Debug;

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
}

sub reloadDB() {
    my $s = shift;
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

    pdebug("Qwit::InMemoryModel::reload_db complete.");
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

1;
