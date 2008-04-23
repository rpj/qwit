package Qwit::Config;

use strict;
use warnings;

use Exporter qw(import);

use Qwit::Debug;
use Data::Dumper;

my $ModifiableKeys = "debuglevel sleepdelay";

sub new {
    my $c = shift;
    my %conf = @_;
    my $s = {};

    bless ($s, $c);
    $s->{'conf'} = { %conf }, if (%conf);

    return $s->init();
}

sub init {
    my $s = shift;
    my $ret = $s;
    
    $s->{'twitterConf'} = undef;

    if ($s->{'conf'}->{'configfile'}) {
        $s->__load_config_from_file();
    }
    elsif ($s->{'conf'}->{'username'} && $s->{'conf'}->{'password'})
    {
        $s->{'twitterConf'} = $s->{'conf'};
    }
    else
    {
        $ret = undef;
    }

    pdebugl(2, "Qwit::Config::init has hash: ". Dumper($s->{'twitterConf'}));
    return $ret;
}

sub __load_config_from_file {
    my $s = shift;
    my $count = 0;

    open (CONF, "$s->{conf}->{configfile}") or
        die "Unable to open config file at '$s->{conf}->{configfile}': $!\n\n";

    while (<CONF>) {
        # match 'key = var' style lines
        if (/^(\w+)\s+\=\s+(.*?)$/ig) {
            $s->{'conf'}->{$1} = $2;    
            $count++;

            if ($1 eq 'username' ||
                $1 eq 'password' ||
                $1 eq 'clientname'
                ) 
            {
                $s->{'twitterConf'}->{$1} = $2;
            }
        }
    }

    pdebugl(2, "__load_config_from_file loaded $count directives from '$s->{conf}->{configfile}'");
    close (CONF);
}

sub twitterConf {
    my $s = shift;

    return $s->{'twitterConf'}, if ($s->{'twitterConf'});
    return undef;
}

sub sleepDelay {
    return (shift)->{'conf'}->{'sleepdelay'};
}

sub delayMult {
    return (shift)->{'conf'}->{'delaymult'};
}

sub dbFile {
    return (shift)->{'conf'}->{'dbfile'};
}

sub god {
    return (shift)->{'conf'}->{'godid'};
}

sub debugLevel {
    return (shift)->{'conf'}->{'debuglevel'};
}

sub isKeyModifiable {
    my ($s, $k) = @_;

    return (index($ModifiableKeys, $k) >= 0);
}

sub setAllowedKey {
    my ($s, $k, $v) = @_;
    my $rv = 0;

    if ($k eq 'debuglevel') {
        $rv = $s->setDebugLevel($v);
    }
    elsif ($k eq 'sleepdelay') {
        $rv = $s->setSleepDelay($v);
    }

    return $rv;
}

sub setDebugLevel {
    my ($s, $l) = @_;
    
    if ($l =~ /^\d+$/) {
        $s->{'conf'}->{'debuglevel'} = int($l);
        Qwit::Debug::setDebugLevel(int($l));

        return 1;
    }

    return 0;
}

sub setSleepDelay {
    my ($s, $d) = @_;

    if ($d =~ /^\d+$/ && int($d) > 60) {
        $s->{'conf'}->{'sleepdelay'} = int($d);

        return 1;
    }

    return 0;
}

1;
