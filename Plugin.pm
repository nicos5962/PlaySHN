package Plugins::PlaySHN::Plugin;

use strict;
use warnings;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Plugins::PlaySHN::Register;

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.playshn',
    defaultLevel => 'INFO',
    description  => 'PLUGIN_PLAYSHN',
});

sub initPlugin {
    my $class = shift;

    my $version = $class->_pluginDataFor('version') || 'unknown';
    $log->info("Initializing PlaySHN plugin $version");

    Plugins::PlaySHN::Register->registerFormatHandler();

    $class->SUPER::initPlugin(@_);
}

sub getDisplayName { 'PLUGIN_PLAYSHN' }

1;
