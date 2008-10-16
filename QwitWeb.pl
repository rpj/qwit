#!/usr/bin/perl

use QwitWeb;

use Qwit::Debug;
use Qwit::InMemoryModel;
use Qwit::Config;

use Data::Dumper;

pdebug("QwitWeb starting up...");

my $config = $ARGV[0] || "./qwit.config";

my $model = Qwit::InMemoryModel->new(Qwit::Config->singleton($config)->dbFile());

if ($model) {
    pdebug("Initalized.");
    my $web = QwitWeb->new($model);

    pdebug("Web started: $web");
}
