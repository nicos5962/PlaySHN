package Plugins::PlaySHN::Formats::Shorten;

# Shorten (SHN) files have no embedded tags and are not supported by
# Audio::Scan. The tags are read from a companion APEv2 .tag file (as written
# by foobar2000), the audio properties come from the technical values stored
# in that file or, when missing, from ffprobe. An external album id is set from
# the Discogs release id so that different releases of the same album / artist
# are not merged into one album.

use strict;
use warnings;
use base qw(Slim::Formats);

use Encode qw(decode);
use File::Basename qw(dirname);
use JSON::XS qw(decode_json);

use Slim::Formats::APE;
use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('plugin.playshn');

# Applied on top of the core APE mapping (Slim::Formats::APE::doTagMapping).
# A mapping never overwrites a value that is already present.
my %tagMapping = (
    'ALBUM_ARTIST'      => 'ALBUMARTIST',
    'ALBUM ARTIST SORT' => 'ALBUMARTISTSORT',
    'ALBUMARTIST_SORT'  => 'ALBUMARTISTSORT',
    'UNSYNCEDLYRICS'    => 'LYRICS',
    'UNSYNCED LYRICS'   => 'LYRICS',
    'RELEASEDATE'       => 'YEAR',
);

# Normalized names (upper case, letters and digits only) of the tags holding
# the Discogs release id, in order of preference.
my @extIdNames = qw(DISCOGSRELEASEID DISCOGSID DISCOGSRELEASE LMSRELEASEID);

# Bit depth by ffprobe sample format.
my %sampleSize = (
    u8  => 8,  s16  => 16, s32  => 32, flt  => 32, dbl  => 64,
    u8p => 8,  s16p => 16, s32p => 32, fltp => 32, dblp => 64,
    s64 => 64, s64p => 64,
);

sub getTag {
    my ($class, $file, $anchor) = @_;
    return {} unless $file;

    my $tags = {};

    if (my $tagFile = _findTagFile($file)) {
        $tags = _readTagFile($tagFile);
    }
    else {
        main::DEBUGLOG && $log->is_debug && $log->debug("PlaySHN: no .tag file found for $file");
    }

    _foobarProperties($tags);

    unless ($tags->{RATE} && $tags->{CHANNELS} && $tags->{SECS}) {
        _probeProperties($file, $tags);
    }

    unless ($tags->{RATE} && $tags->{SECS}) {
        $log->warn("PlaySHN: no audio properties found for $file");
        return;
    }

    my $size = -s $file;

    $tags->{SIZE}         = $size;
    $tags->{OFFSET}       = 0;
    $tags->{LOSSLESS}     = 1;
    $tags->{CONTENT_TYPE} = 'shn';
    $tags->{SAMPLESIZE} ||= 16;
    $tags->{BITRATE}    ||= int($size * 8 / $tags->{SECS});

    $class->_mapDisc($tags);
    Slim::Formats::APE->doTagMapping($tags);

    $class->_mapExtraTags($tags);
    $class->_setExtId($tags);

    main::DEBUGLOG && $log->is_debug && $log->debug(sprintf(
        'PlaySHN: %s - %s Hz / %s bit / %s ch / %s sec',
        $file, $tags->{RATE}, $tags->{SAMPLESIZE}, $tags->{CHANNELS} // '?', $tags->{SECS},
    ));

    return $tags;
}

# SHN has no embedded artwork. Folder artwork is found by the server itself.
sub getCoverArt { return }

sub canSeek { 1 }

# The tag file has the name of the audio file with a .tag extension. A single
# .tag file is also accepted for a folder holding one single .shn file.
sub _findTagFile {
    my ($file) = @_;

    (my $base = $file) =~ s/\.[^.\/]+$//;

    for my $candidate ("$base.tag", "$file.tag") {
        return $candidate if -f $candidate;
    }

    my $dir = dirname($file);

    opendir my $dh, $dir or return;
    my @files = readdir $dh;
    closedir $dh;

    my @shn = grep { /\.shn$/i } @files;
    my @tag = grep { /\.tag$/i } @files;

    return "$dir/$tag[0]" if @shn == 1 && @tag == 1;

    return;
}

# Returns the items of the APEv2 tag, with upper case names. A name with
# several values (separated by a null byte) gets an array of values.
sub _readTagFile {
    my ($file) = @_;

    open my $fh, '<:raw', $file or do {
        $log->warn("PlaySHN: cannot open tag file $file: $!");
        return {};
    };

    my $data = do { local $/; <$fh> };

    close $fh;

    my $pos = index($data, 'APETAGEX');

    return {} if $pos < 0 || length($data) - $pos < 32;

    # magic, version, size, item count, flags
    my (undef, undef, $size, $count, $flags) = unpack('a8 V V V V', substr($data, $pos, 24));

    # the size covers the items and the footer, but not the header
    my $start  = ($flags & (1 << 29)) ? $pos + 32 : $pos + 32 - $size;
    my $length = $size - 32;

    return {} if $length <= 0 || $start < 0 || $start + $length > length($data);

    my $items = substr($data, $start, $length);
    my %tags;
    my $offset = 0;

    while ($count-- > 0 && $offset + 8 <= length($items)) {
        my ($valueLength, $itemFlags) = unpack('V V', substr($items, $offset, 8));
        $offset += 8;

        my $keyEnd = index($items, "\x00", $offset);
        last if $keyEnd < 0;

        my $key = substr($items, $offset, $keyEnd - $offset);
        $offset = $keyEnd + 1;

        my $value = substr($items, $offset, $valueLength);
        $offset += $valueLength;

        # text items only
        next if (($itemFlags >> 1) & 3) != 0 || !length $key;

        my @values = grep { length } map { decode('UTF-8', $_) } split /\x00/, $value;

        next unless @values;

        $tags{ uc $key } = @values > 1 ? \@values : $values[0];
    }

    return \%tags;
}

# foobar2000 stores the audio properties in the tag file.
sub _foobarProperties {
    my ($tags) = @_;

    my %fb = map { $_ => _first(delete $tags->{"FOOBAR_$_"}) }
        qw(SAMPLERATE CHANNELS BITPERSAMPLE BITRATE DURATION);

    my $encoding = _first(delete $tags->{FOOBAR_ENCODING});

    return unless $fb{SAMPLERATE};

    $tags->{RATE}       = int($fb{SAMPLERATE});
    $tags->{CHANNELS}   = int($fb{CHANNELS})        if $fb{CHANNELS};
    $tags->{SAMPLESIZE} = int($fb{BITPERSAMPLE})    if $fb{BITPERSAMPLE};
    $tags->{BITRATE}    = int($fb{BITRATE} * 1000)  if $fb{BITRATE};

    # 5:55 or 1:05:55
    if (defined $fb{DURATION} && $fb{DURATION} =~ /^(?:(\d+):)?(\d+):(\d+(?:\.\d+)?)$/) {
        $tags->{SECS} = ($1 // 0) * 3600 + $2 * 60 + $3;
    }
}

sub _first {
    my ($value) = @_;

    $value = $value->[0] if ref $value eq 'ARRAY';

    return $value;
}

sub _probeProperties {
    my ($file, $tags) = @_;

    my $ffprobe = Slim::Utils::Misc::findbin('ffprobe') || 'ffprobe';

    my @cmd = (
        $ffprobe, qw(-v quiet -print_format json -show_format -show_streams -select_streams a), $file,
    );

    unshift @cmd, '/usr/bin/timeout', '15' if -x '/usr/bin/timeout';

    open my $ph, '-|', @cmd or do {
        $log->warn("PlaySHN: could not run ffprobe for $file: $!");
        return;
    };

    my $json = do { local $/; <$ph> };

    close $ph;

    unless (defined $json && length $json) {
        $log->warn("PlaySHN: ffprobe returned nothing for $file");
        return;
    }

    my $probe = eval { decode_json($json) };

    unless ($probe) {
        $log->warn("PlaySHN: failed to decode ffprobe output for $file: $@");
        return;
    }

    my $format = $probe->{format} || {};
    my $stream = $probe->{streams} && $probe->{streams}->[0] or return;

    my $bits = $stream->{bits_per_raw_sample} || $stream->{bits_per_sample}
        || $sampleSize{ $stream->{sample_fmt} // '' };

    $tags->{SECS}       ||= ($format->{duration} || $stream->{duration} || 0) + 0;
    $tags->{RATE}       ||= ($stream->{sample_rate} || 0) + 0;
    $tags->{CHANNELS}   ||= ($stream->{channels} || 0) + 0;
    $tags->{SAMPLESIZE} ||= $bits + 0 if $bits;
    $tags->{BITRATE}    ||= int($stream->{bit_rate} || $format->{bit_rate} || 0);
}

# Names under which taggers store the disc number, the number of discs and the
# disc title, in order of preference. Core only knows DISCNUMBER and DISCSUBTITLE.
my @discNumberKeys = ('DISCNUMBER', 'DISC', 'DISC NUMBER', 'DISC_NUMBER');
my @discTotalKeys  = ('DISCTOTAL', 'TOTALDISCS', 'DISC_TOTAL', 'DISC TOTAL', 'DISCC');
my @discTitleKeys  = (
    'DISCSUBTITLE', 'DISC SUBTITLE', 'DISC_SUBTITLE',
    'DISCTITLE', 'DISC TITLE', 'DISC_TITLE', 'SETSUBTITLE', 'SET SUBTITLE',
);

# Sets DISC, DISCC and DISCSUBTITLE the way the server expects them: plain
# numbers (core drops anything else, and disc 0), first value only.
sub _mapDisc {
    my ($class, $tags) = @_;

    my $disc  = _takeFirst($tags, @discNumberKeys);
    my $discc = _takeFirst($tags, @discTotalKeys);
    my $title = _takeFirst($tags, @discTitleKeys);

    if (defined $disc) {
        # 1/2, 1-2, 1 of 2: a number of discs in its own tag wins
        if ($disc =~ m{(\d+)\s*(?:/|-|of)\s*(\d+)}i) {
            ($disc, $discc) = ($1, $discc // $2);
        }
        # Disc 2, 02
        elsif ($disc =~ /(\d+)/) {
            $disc = $1;
        }
        else {
            undef $disc;
        }
    }

    $discc = $1 if defined $discc && $discc =~ /(\d+)/;

    $tags->{DISC}         = $disc + 0  if $disc;
    $tags->{DISCC}        = $discc + 0 if $discc;
    $tags->{DISCSUBTITLE} = $title     if defined $title;
}

# Removes the tags and returns the first value that is not empty.
sub _takeFirst {
    my ($tags, @keys) = @_;

    my $found;

    for my $key (@keys) {
        next unless exists $tags->{$key};

        my $values = delete $tags->{$key};

        for my $value (ref $values eq 'ARRAY' ? @$values : $values) {
            next if !defined $value || ref $value;

            (my $trimmed = $value) =~ s/^\s+|\s+$//g;

            $found //= $trimmed if length $trimmed;
        }
    }

    return $found;
}

sub _mapExtraTags {
    my ($class, $tags) = @_;

    while (my ($old, $new) = each %tagMapping) {
        next unless exists $tags->{$old};

        my $value = delete $tags->{$old};
        $tags->{$new} = $value unless defined $tags->{$new};
    }

    # TRACK=01/7
    if (defined $tags->{TRACKNUM} && !ref $tags->{TRACKNUM} && $tags->{TRACKNUM} =~ m{^\s*(\d+)}) {
        $tags->{TRACKNUM} = $1 + 0;
    }
}

sub _setExtId {
    my ($class, $tags) = @_;

    return if $tags->{ALBUM_EXTID};

    my %byName;

    for my $key (keys %$tags) {
        (my $name = uc $key) =~ s/[^A-Z0-9]//g;

        $byName{$name} //= $tags->{$key};
    }

    for my $name (@extIdNames) {
        my $value = $byName{$name};
        $value = $value->[0] if ref $value eq 'ARRAY';

        next if !defined $value || ref $value;

        $value =~ s/^\s+|\s+$//g;

        if (length $value) {
            $tags->{ALBUM_EXTID} = $value;
            return;
        }
    }
}

1;
