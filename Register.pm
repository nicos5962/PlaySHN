package Plugins::PlaySHN::Register;

# Registers the PlaySHN tag handler. Kept free of any web/UI dependency so it
# can be used by both the server plugin and the scanner importer.

use strict;
use warnings;

use Slim::Formats;
use Slim::Utils::Log;

use constant HANDLER => 'Plugins::PlaySHN::Formats::Shorten';

my $log = logger('plugin.playshn');

sub registerFormatHandler {
    my ($class, $tagClasses) = @_;

    Slim::Formats->init();

    $tagClasses ||= \%Slim::Formats::tagClasses;

    return 0 unless ref($tagClasses) eq 'HASH';

    return 1 if defined $tagClasses->{shn} && $tagClasses->{shn} eq HANDLER;

    $tagClasses->{shn} = HANDLER;

    main::DEBUGLOG && $log->is_debug && $log->debug('PlaySHN: registered shn tag handler');

    return 1;
}

1;
