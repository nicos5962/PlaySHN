package Plugins::PlaySHN::Formats::Shorten;

use strict;
use warnings;
use base qw(Slim::Formats);

use Fcntl qw(:seek);
use File::Basename;

use Audio::Scan;
use Slim::Utils::Log;

my $log = logger('plugin.playshn');

# Mapping of APEv2 tags to expected LMS tags
my %tagMapping = (
    'Track'                  => 'TRACKNUM',
    'Disc'                   => 'DISC',
    'Artist'                 => 'ARTIST',
    'Title'                  => 'TITLE',
    'Album'                  => 'ALBUM',
    'Year'                   => 'YEAR',
    'Genre'                  => 'GENRE',
    'Totaldisc'              => 'DISCC',
    'Foobar_channels'        => 'CHANNELS',
    'Foobar_samplerate'      => 'RATE',
);

#==========================
# Main method: getTag
#==========================
sub getTag {
    my ($class, $file) = @_;
    return {} unless $file;

    # Scan audio info
    open my $fh, '<', $file or do {
        $log->warn("Could not open $file: $!");
        return {};
    };

    my $s = Audio::Scan->scan_fh(mp3 => $fh);
    close $fh;

    my $info = $s->{info};
    my $tags = $s->{tags};

    # Basic audio info
    $tags->{TAGVERSION}   = $info->{id3_version};
    $tags->{OFFSET}       = $info->{audio_offset};
    $tags->{SIZE}         = $info->{audio_size};
    $tags->{SECS}         = $info->{song_length_ms} / 1000;
    $tags->{BITRATE}      = $info->{bitrate};
    $tags->{STEREO}       = $info->{stereo};
    $tags->{CHANNELS}     = $info->{stereo} ? 2 : 1;
    $tags->{RATE}         = $info->{samplerate};
    $tags->{LAYER_ID}     = $info->{layer}; # 2 = mp2, 1 = mp3
    $tags->{DLNA_PROFILE} = $info->{dlna_profile} || undef;
    $tags->{SAMPLESIZE}   = 16;

    # Read companion APEv2 .tag file
    my $shn_tags = _readAPEv2Tag($file);

    # Map APEv2 tags to LMS expected tags
    foreach my $key (keys %$shn_tags) {
        if (exists $tagMapping{$key}) {
            $tags->{$tagMapping{$key}} = $shn_tags->{$key};
        } else {
            $tags->{$key} = $shn_tags->{$key};
        }
    }

    # Map tags for legacy LMS usage
    $class->doTagMapping($tags);

    # Update bitrate if Foobar tag exists
    if (exists $tags->{Foobar_bitrate}) {
        $info->{bitrate} = $tags->{Foobar_bitrate} * 1000;
        $tags->{BITRATE} = $tags->{Foobar_bitrate} * 1000;
    }

    # Parse duration from Foobar_duration if exists
    if (exists $tags->{Foobar_duration}) {
        my @arr = split(':', $tags->{Foobar_duration});
        my $time_format = ($tags->{Foobar_duration} =~ tr/://);
        my $sec = 0;

        if ($time_format == 2) {
            $sec = $arr[0]*3600 + $arr[1]*60 + $arr[2];
        } else {
            $sec = $arr[0]*60 + $arr[1];
        }
        $tags->{SECS} = $sec;
    }

    return $tags;
}

#==========================
# Proper APEv2 tag parser
#==========================
sub _readAPEv2Tag {
    my ($file) = @_;
    my %tags;

    # Companion .tag file
    (my $tagfile = $file) =~ s/\.\w+$/\.tag/;

    open my $fh, '<:raw', $tagfile or do {
        warn "Could not open $tagfile: $!";
        return \%tags;
    };

    # Get file size
    my $size = -s $fh;

    # Read last 32 bytes for footer
    seek($fh, $size - 32, 0);
    read($fh, my $footer, 32);

    return \%tags unless substr($footer, 0, 8) eq 'APETAGEX';

    my $tag_size = unpack('V', substr($footer, 12, 4));

    # Read entire tag block
    seek($fh, $size - $tag_size, 0);
    read($fh, my $tag_data, $tag_size);

    my $offset = 0;
    my $items_end = $tag_size - 32; # exclude footer

    while ($offset < $items_end) {
        my ($len, $flags) = unpack('VV', substr($tag_data, $offset, 8));
        $offset += 8;

        my $key_end = index($tag_data, "\0", $offset);
        my $key = substr($tag_data, $offset, $key_end - $offset);
        $offset = $key_end + 1;

        my $value = substr($tag_data, $offset, $len);
        $offset += $len;

        # Skip binary data
        next if $flags & 0x00000001;

        # Decode UTF-8 if flag is not set (APEv2 text is UTF-8)
        $tags{$key} = $value;
    }

    close $fh;
    return \%tags;
}

#==========================
# Map tags using %tagMapping
#==========================
sub doTagMapping {
    my ($class, $tags, $no_overwrite) = @_;

    while (my ($old, $new) = each %tagMapping) {
        if (exists $tags->{$old}) {
            $tags->{$new} = delete $tags->{$old};
        }
    }
}

*getCoverArt = \&Slim::Formats::APE::getCoverArt;

1;

