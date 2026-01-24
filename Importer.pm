package Plugins::PlaySHN::Importer;

use strict;
use warnings;

use Slim::Music::Import;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.playshn');
my $prefs = preferences('plugin.playshn');

sub initPlugin {
    my $class = shift;

    # Register SHN format handler
    $Slim::Formats::tagClasses{shn} = 'Plugins::PlaySHN::Formats::Shorten';
    return 1;
}

sub startScan {
    my $class = shift;
    return;
}

1;

