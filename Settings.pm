package Plugins::PlaySHN::Settings;

use strict;
use warnings;
use parent qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.playshn');
my $prefs = preferences('plugin.playshn');

# Optional reference to main plugin class if needed
my $plugin;

sub name {
    # Localized string ID from strings.txt
    return 'PLUGIN_PLAYSHN';
}

sub page {
    return 'plugins/PlaySHN/settings/basic.html';
}

sub new {
    my ($class, $main_plugin) = @_;
    $plugin = $main_plugin;
    return $class->SUPER::new;
}

sub init {
    my $self = shift;
    # Initialize settings here if needed
}

sub handler {
    my ($class, $client, $params) = @_;
    $params->{icon} = "plugins/PlaySHN/html/images/playshn.png";
    return $class->SUPER::handler($client, $params);
}

1;

