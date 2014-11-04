# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
package DW::Controller::RPC::MiscLegacy;

use strict;
use DW::Routing;
use DW::RPC;
use LJ::CreatePage;

# do not put any endpoints that do not have the "forked from LJ" header in this file
DW::Routing->register_rpc( "changerelation", \&change_relation_handler, format => 'json' );
DW::Routing->register_rpc( "checkforusername", \&check_username_handler, format => 'json' );
DW::Routing->register_rpc( "controlstrip", \&control_strip_handler, format => 'json' );
DW::Routing->register_rpc( "getsecurityoptions", \&get_security_options_handler, format => 'json' );
DW::Routing->register_rpc( "gettags", \&get_tags_handler, format => 'json' );
DW::Routing->register_rpc( "userpicselect", \&get_userpics_handler, format => 'json' );

sub change_relation_handler {
    my $r = DW::Request->get;
    my $post = $r->post_args;

    # get user
    my $remote = LJ::get_remote();
    return DW::RPC->err( "Sorry, you must be logged in to use this feature." )
        unless $remote;

    return DW::RPC->err( "Invalid auth token" )
        unless $remote->check_ajax_auth_token( '/__rpc_changerelation', %$post );

    my ( $target, $action );
    $target = $post->{target} or return DW::RPC->err( "No target specified" );
    $action = $post->{action} or return DW::RPC->err( "No action specified" );

    # Prevent XSS attacks
    $target = LJ::ehtml( $target );
    $action = LJ::ehtml( $action );

    my $targetu = LJ::load_user( $target );
    return DW::RPC->err( "Invalid user $target" )
        unless $targetu;

    my $success = 0;
    my %ret = ();

    if ( $action eq 'addTrust' ) {
        my $error;
        return DW::RPC->err( $error )
            unless $remote->can_trust( $targetu, errref => \$error );

        $success = $remote->add_edge( $targetu, trust => {} );
    } elsif ( $action eq 'addWatch' ) {
        my $error;
        return DW::RPC->err( $error )
            unless $remote->can_watch( $targetu, errref => \$error );

        $success = $remote->add_edge( $targetu, watch => {} );

        $success &&= $remote->add_to_default_filters( $targetu );
    } elsif ( $action eq 'removeTrust' ) {
        $success = $remote->remove_edge( $targetu, trust => {} );
    } elsif ( $action eq 'removeWatch' ) {
        $success = $remote->remove_edge( $targetu, watch => {} );
    } elsif ( $action eq 'join' ) {
        my $error;
        if ( $remote->can_join( $targetu, errref => \$error ) ) {
            $success = $remote->join_community( $targetu );
        } else {
            if ( $error eq LJ::Lang::ml( 'edges.join.error.targetnotopen' ) && $targetu->is_moderated_membership ) {
                $targetu->comm_join_request( $remote );
                $ret{note} = LJ::Lang::ml( '/community/join.bml.reqsubmitted.body' );
            } else {
                return DW::RPC->err( $error );
            }
        }
    } elsif ( $action eq 'leave' ) {
        my $error;
        return DW::RPC->err( $error )
            unless $remote->can_leave( $targetu, errref => \$error );

        $success = $remote->leave_community( $targetu );
    } elsif ( $action eq 'setBan' ) {
        my $list_of_banned = LJ::load_rel_user( $remote, 'B' ) || [];

        return DW::RPC->err( "Exceeded limit maximum of banned users" )
            if @$list_of_banned >= ( $LJ::MAX_BANS || 5000 );

        my $ban_user = LJ::load_user($target);
        $success = $remote->ban_user($ban_user);
        LJ::Hooks::run_hooks('ban_set', $remote, $ban_user);
    } elsif ( $action eq 'setUnban' ) {
        my $unban_user = LJ::load_user($target);
        $success = $remote->unban_user_multi( $unban_user->{userid} );
    } else {
        return DW::RPC->err( "Invalid action $action" );
    }

    return DW::RPC->out(
        success     => $success,
        is_trusting => $remote->trusts( $targetu ),
        is_watching => $remote->watches( $targetu ),
        is_member   => $remote->member_of( $targetu ),
        is_banned   => $remote->has_banned( $targetu ),
        %ret,
    );
}

sub check_username_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;
    my $error = LJ::CreatePage->verify_username( $args->{user} );

    return DW::RPC->err( $error );
}

sub control_strip_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my $control_strip;
    my $user = $args->{user};
    if (defined $user) {
        unless (defined LJ::get_active_journal()) {
            LJ::set_active_journal(LJ::load_user($user));
        }
        $control_strip = LJ::control_strip( user => $user, host => $args->{host}, uri => $args->{uri}, args => $args->{args}, view => $args->{view} );
    }

    return DW::RPC->out( control_strip => $control_strip );
}

sub get_security_options_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my $remote = LJ::get_remote();
    my $user = $args->{user};
    my $u = LJ::load_user($user);

    return DW::RPC->out
        unless $u;

    my %ret = (
        is_comm => $u->is_comm ? 1 : 0,
        can_manage =>  $remote && $remote->can_manage( $u ) ? 1 : 0,
    );

    return DW::RPC->out( ret => \%ret )
        unless $remote && $remote->can_post_to($u);

    unless ( $ret{is_comm} ) {
        my $friend_groups = $u->trust_groups;
        $ret{friend_groups_exist} = keys %$friend_groups ? 1 : 0;
    }

    $ret{minsecurity} = $u->newpost_minsecurity;

    return DW::RPC->out( ret => \%ret );
}

sub get_tags_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;

    my $remote = LJ::get_remote();
    my $user = $args->{user};
    my $u = LJ::load_user($user);
    my $tags = $u ? $u->tags : {};

    return DW::RPC->alert( "You cannot view this journal's tags." ) unless $remote && $remote->can_post_to($u);
    return DW::RPC->alert( "You cannot use this journal's tags." ) unless $remote->can_add_tags_to($u);

    my @tag_names;
    if (keys %$tags) {
        @tag_names = map { $_->{name} } values %$tags;
        @tag_names = sort { lc $a cmp lc $b } @tag_names;
    }

    return DW::RPC->out( tags => \@tag_names );
}

sub get_userpics_handler {
    my $r = DW::Request->get;
    my $get = $r->get_args;

    my $remote = LJ::get_remote();

    my $alt_u;
    $alt_u = LJ::load_user( $get->{user} )
        if $get->{user} && $remote->has_priv( "supporthelp" );

    # get user
    my $u = ( $alt_u || $remote );
    return DW::RPC->alert( "Sorry, you must be logged in to use this feature." )
        unless $u;

    # get userpics
    my @userpics = LJ::Userpic->load_user_userpics( $u );

    my %upics = (); # info to return
    $upics{pics} = {}; # upicid -> hashref of metadata

    foreach my $upic (@userpics) {
        next if $upic->inactive;

        my $id = $upic->id;
        $upics{pics}{$id} = {
            url => $upic->url,
            state => $upic->state,
            width => $upic->width,
            height => $upic->height,

            # we don't want the full version of alttext here, because the keywords, etc
            # will already likely be displayed by the icon

            # We don't want to use ehtml, because we want the JSON converter
            # handle escaping ", ', etc. We just escape the < and > ourselves
            alt => LJ::etags( $upic->description ),

            comment => LJ::strip_html( $upic->comment ),

            id => $id,
            keywords => [ map { LJ::strip_html( $_ ) } $upic->keywords],
        };
    }

    $upics{ids} = [sort { $a <=> $b } keys %{$upics{pics}}];

    return DW::RPC->out( %upics );
}

1;
