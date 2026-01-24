package Plugins::PlaySHN::Plugin;

use strict;
use warnings;

use base qw(Slim::Plugin::OPMLBased Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);
use Plugins::PlaySHN::Settings;

sub getDisplayName { 'PLUGIN_PLAYSHN' }

# Create log category
my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.playshn',
    defaultLevel => 'INFO',
    description  => getDisplayName(),
});

sub initPlugin {
    my $class = shift;
    my $version = $class->_pluginDataFor('version') || 'unknown';

    $log->info("Initializing PlaySHN plugin $version");

    Slim::Web::Pages->addPageLinks(
        "icons",
        { "PLAYSHN_SETTINGS" => "plugins/PlaySHN/html/images/playshn.png" }
    );

    Plugins::PlaySHN::Settings->new();
    Plugins::PlaySHN::Settings->init;

    # Register SHN format scanner
    $Slim::Formats::tagClasses{shn} ||= 'Plugins::PlaySHN::Formats::Shorten';
}

sub pluginDir { shift->_pluginDataFor('basedir') }

sub shutdownPlugin {
	my $class = shift;
	$log->info("Shutting down PlaySHN plugin");
}
1;

