package Plugins::PlaySHN::Importer;

use strict;
use warnings;

use Plugins::PlaySHN::Register;

sub initPlugin {
    my $class = shift;

    Plugins::PlaySHN::Register->registerFormatHandler();
    return 1;
}

sub startScan {
    my $class = shift;
    return;
}

1;
