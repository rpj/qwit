package Qwit::Twitter;

use warnings;
use strict;

use Qwit::Debug;
use Net::Twitter;
use Exporter qw(import);

use Data::Dumper;

sub new {
    my $class = shift;
    my %conf = @_;
    my $self = {};

    bless($self, $class);

    $self->{'conf'} = { %conf }, if (%conf);
    return $self->init();
}

sub init {
    my $self = shift;

    $self->{'conn'} = Net::Twitter->new(%{$self->{'conf'}});

    return $self;
}

sub attachModel {
    my $self = shift;
    my $model = shift;

    $self->{'model'} = $model;
}

sub numRequestsProcessed {
    return (shift)->{'reqInfo'}->{'count'};
}

sub __accum_request {
    my $self = shift;

    $self->{'reqInfo'} = {}, unless (defined($self->{'reqInfo'}));
    $self->{'reqInfo'}->{'last'} = time();
    $self->{'reqInfo'}->{'count'}++;

    push (  @{$self->{'reqInfo'}->{'enum'}}, 
            [ $self->{'reqInfo'}->{'count'}, $self->{'reqInfo'}->{'last'} ]);

    pdebugl(2, "Accumlated a request: now at $self->{reqInfo}->{count}");
}

sub __check_last_request {
    my $self = shift;
    my $code = $self->{'conn'}->http_code();
    
    if ($code >= 400) {
        pdebug("Last request returned an HTTP error $code:");
        pdebug("\t'" . $self->{'conn'}->http_message() . "'");

        return undef;
    }

    return ($code == 200);
}

sub __check_and_accum($) {
    my $self = shift;
    my $reqPassThru = shift;

    if ($self->__check_last_request()) {
        $self->__accum_request();
    } else {
        $reqPassThru = undef;
    }

    return $reqPassThru;
}

sub followers {
    my $self = shift;
    return $self->__check_and_accum($self->{'conn'}->followers());
}

sub following {
    my $self = shift;
    return $self->__check_and_accum($self->{'conn'}->following());
}

# pass thrus
sub http_code { return (shift)->{'conn'}->http_code(); }
sub http_message { return (shift)->{'conn'}->http_message(); }

sub sendDmsg {
    my $s = shift;
    my $to = shift;
    my $msg = shift;

    return $s->{'conn'}->new_direct_message( { user => "$to", text => "$msg" } );
}

sub collectDmsgs {
    my $s = shift;
    my $aRef = shift;
    $aRef = [], unless (defined($aRef));

    my $dmsgs = $s->{'conn'}->direct_messages( { since_id => $s->{'model'}->lastMsgId() } );

    foreach my $dmsg (@{$dmsgs}) {
        pdebug("New direct message id $dmsg->{id} found; collecting.");
        push (@{$aRef}, $dmsg); 
    }

    return $aRef;
}

sub collectReplies {
    my $s = shift;
    my $aRef = shift;
    $aRef = [], unless (defined($aRef));

    my $replies = $s->{'conn'}->replies();

    foreach my $repl (@{$replies}) {
        if ($repl->{'id'} > $s->{'model'}->lastMsgId()) {
            pdebug("New \@reply id $repl->{id} found; collecting.");
            push(@{$aRef}, $repl);
        }
    }

    return $aRef;
}

sub checkFollowing {
    my $s = shift;

    my $ers = $s->followers();
    my $ing = undef;

    if (defined($ers) && defined($ing = $s->following())) 
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

                    $s->{'conn'}->follow($ersOne->{'id'});

                    my $msg = "Hello $ersOne->{'name'}: I'm now following you as well!";
                    $s->sendDmsg("$ersOne->{'id'}", "$msg");
                }
            }
        }
    }

    return defined($ers) && defined($ing);
}

1;
