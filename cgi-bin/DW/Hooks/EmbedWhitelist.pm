#!/usr/bin/perl
#
# This code was based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and expanded
# by Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
#
# DW::Hooks::EmbedWhitelist
#
# Keep a whitelist of trusted sites which we trust for certain kinds of embeds
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.

package DW::Hooks::EmbedWhitelist;

use strict;
use LJ::Hooks;
use URI;

# for internal use only
# this is used when sites may offer embeds from multiple subdomain
# e.g., www, www1, etc
sub match_subdomain {
    my $want_domain = $_[0];
    my $domain_from_uri = $_[1];

    return $domain_from_uri =~ /^(?:[\w.-]*\.)?\Q$want_domain\E$/;
}

sub match_full_path {
    my $want_path = $_[0];
    my $path_from_uri = $_[1];

    return $path_from_uri =~ /^$want_path$/;
}

my %host_path_match = (
                                # regex, whether this supports https or not
    "8tracks.com"           => [ qr!^/mixes/!, 0 ],
    "bandcamp.com"          => [ qr!^/EmbeddedPlayer/!, 1 ],
    "blip.tv"               => [ qr!^/play/!, 1 ],

    "www.dailymotion.com"   => [ qr!^/embed/video/!, 1 ],
    "dotsub.com"            => [ qr!^/media/!, 1 ],

    "www.goodreads.com"     => [ qr!^/widgets/!, 1 ],

    "maps.google.com"       => [ qr!^/maps!, 1 ],
    "www.google.com"        => [ qr!^/calendar/!, 1 ],
    # drawings do not need to be whitelisted as they are images.
    # forms arent being allowed for security concerns.
    "docs.google.com"       => [ qr!^/(document|spreadsheet|presentation)/!, 1 ],

    "www.kickstarter.com"   => [ qr!/widget/[a-zA-Z]+\.html$!, 1 ],

    "ext.nicovideo.jp"      => [ qr!^/thumb/!, 0 ],

    "www.sbs.com.au"        => [ qr!/player/embed/!, 0 ],  # best guess; language parameter before /player may vary
    "www.scribd.com"        => [ qr!^/embeds/!, 1 ],
    "www.slideshare.net"    => [ qr!^/slideshow/embed_code/!, 1 ],
    "w.soundcloud.com"      => [ qr!^/player/!, 1 ],
    "embed.spotify.com"     => [ qr!^/$!, 1 ],

    "www.twitvid.com"       => [ qr!^/embed.php$!, 0 ],

    "player.vimeo.com"      => [ qr!^/video/\d+$!, 1 ],

    "www.plurk.com"         => [ qr!^/getWidget$!, 1 ],

    "instagram.com"         => [ qr!^/p/.*/embed/$!, 1 ],

    "www.criticalcommons.org" => [ qr!/embed_view$!, 0 ],

    "embed.ted.com"         => [ qr!^/talks/!, 1 ],

    "archive.org"           => [ qr!^/embed/!, 1 ],

    "video.yandex.ru"       => [ qr!^/iframe/[\-\w]+/[a-z0-9]+\.\d{4}/?$!, 1 ], #don't think the last part can include caps; amend if necessary

    "episodecalendar.com"   => [ qr!^/icalendar/!, 0 ],

    "www.flickr.com"        => [ qr!/player/$!, 1 ],

    "www.npr.org"           => [ qr!^/templates/event/embeddedVideo\.php!, 1 ],

    "imgur.com"             => [ qr!^/a/.+?/embed!, 1 ],

);

LJ::Hooks::register_hook( 'allow_iframe_embeds', sub {
    my ( $embed_url, %opts ) = @_;

    return 0 unless $embed_url;

    # the URI module hates network-relative URIs, eg '//youtube.com'
    if ( substr($embed_url, 0,2) eq '//' ) {
        $embed_url = 'http:' . $embed_url;
    }

    my $parsed_uri = URI->new( $embed_url );

    my $uri_scheme = $parsed_uri->scheme;
    return 0 unless $uri_scheme eq "http" || $uri_scheme eq "https";

    my $uri_host = $parsed_uri->host;
    my $uri_path = $parsed_uri->path;   # not including query

    my $host_details = $host_path_match{$uri_host};
    my $path_regex = $host_details->[0];

    return ( 1, $host_details->[1] ) if $path_regex && ( $uri_path =~ $path_regex);

    ## YouTube (http://apiblog.youtube.com/2010/07/new-way-to-embed-youtube-videos.html)
    if ( match_subdomain( "youtube.com", $uri_host ) || match_subdomain( "youtube-nocookie.com", $uri_host ) ) {
        return ( 1, 1 ) if match_full_path( qr!/embed/[-_a-zA-Z0-9]{11,}!, $uri_path );
    }

    if ( $uri_host eq "commons.wikimedia.org" ) {
        return ( 1, 1 ) if $uri_path =~ m!^/wiki/File:! && $parsed_uri->query =~ m/embedplayer=yes/;
    }

    return 0;

} );

1;
