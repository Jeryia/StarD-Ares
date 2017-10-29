package ares_player;
use strict;
use warnings;

use Carp qw(cluck);

use lib("./lib");
use ares_core;

use lib("../../lib/perl");
use Starmade::Message;
use Starmade::Player;
use Starmade::Faction;
use Stard::Log;


our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_new_player ares_new_player_setup ares_set_player_credits ares_add_account ares_check_account ares_player_lock ares_player_unlock ares_player_faction_valid ares_get_player_factions ares_get_all_factions ares_get_faction_name ares_set_faction_name ares_set_team_faction ares_team_to_faction ares_get_faction_state ares_set_faction_state ares_get_faction_home ares_set_faction_home ares_set_faction_npc ares_get_faction_npc ares_get_faction_members ares_add_faction_member ares_get_player_faction ares_unfaction_player ares_fix_faction ares_get_faction_sizes ares_notify_faction ares_get_faction_spawn_pos ares_set_faction_spawn_pos ares_get_starting_credits ares_set_starting_credits fix_players_factions);



## ares_new_player
# Deal with a new player
# INPUT1: name of new player
sub ares_new_player {
	my $player = $_[0];

	if (!$player) {
		cluck("ares_new_player: player argument not given!");
		return 0;
	}


	my $faction_id = ares_get_player_faction($player);

	if (starmade_is_admin($player)) {
		return;
	};

	if (!$faction_id) {
		my %faction_sizes = %{ares_get_faction_sizes()};
		Faction: foreach my $faction_id1 (keys %faction_sizes) {
			foreach my $faction_id2 (keys %faction_sizes) {
				if (
					$faction_sizes{$faction_id1} >= $faction_sizes{$faction_id2} &&
					$faction_id1 != $faction_id2
				) {
					next Faction;
				}
			}
			ares_new_player_setup($player, $faction_id1);
			return;
		}
		my @faction_ids = keys %faction_sizes;
		my $rand_faction = rand(@faction_ids) % @faction_ids;
		ares_new_player_setup($player, $faction_ids[$rand_faction]);
	}
	else {
		starmade_faction_add_member($player, $faction_id);
	}
}

## ares_new_player_setup 
# Set the player to new game state (remove everything they have, then give them the starting stuff)
# INPUT1: player name
# INPUT2: faction id they are to be in
sub ares_new_player_setup {
	my $player = $_[0];
	my $faction_id = $_[1];

	if (!$player) {
		cluck("ares_new_player_setup: player name not given.");
		return 0;
	}
	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_new_player_setup: invalid faction given '$faction_id'.");
		return 0;
	}


	my %player_info = %{starmade_player_info($player)};

	stdout_log("Setting up new player '$player'", 6);
	starmade_give_all_items($player, -1000000);
	if ($player_info{smname}) {
		if (ares_check_account($player_info{smname}) && $player_info{smname} ne 'null') {
			stdout_log("'$player' detected using multiple accounts. Setting credits to nothing...", 5);
			starmade_broadcast("Anti-cheat: multiple players under same account detected '$player'. Player gets no starting rescources...");
			ares_set_player_credits($player, 0);
			
			starmade_give_item($player, "Ship Core", 1);
			starmade_give_item($player, "Power Reactor", 1);
			starmade_give_item($player, "Thruster", 4);
			ares_add_faction_member($player, $faction_id);
			my $home = ares_get_faction_home($faction_id);
			starmade_change_sector_for($player, $home);
			starmade_teleport_to($player, ares_get_faction_spawn_pos($faction_id));
			starmade_set_spawn_player($player);
	
			print "faction_id = $faction_id\n";
			my $faction_name = ares_get_faction_name($faction_id);
			starmade_broadcast("$player has been assigned to $faction_name!");
			return 1;
		}
		else {
			ares_add_account($player_info{smname});
		}
	}
	
	if(!ares_set_player_credits($player, ares_get_starting_credits())) {
		my %player_info = %{starmade_player_info($player)};
		# if player is not online anymore stop trying, we'll get them next time
		if (!(keys %player_info)) {
			return 0;
		}
		sleep 1;
		if (!ares_set_player_credits($player, ares_get_starting_credits())) {
			starmade_broadcast("Error setting up environment for $player.");
			starmade_broadcast("Reccommend $player try relogging.");
		};
	};

	starmade_give_item($player, "Ship Core", 1);
	starmade_give_item($player, "Power Reactor", 1);
	starmade_give_item($player, "Thruster", 4);

	ares_add_faction_member($player, $faction_id);
	my $home = ares_get_faction_home($faction_id);
	starmade_change_sector_for($player, $home);
	starmade_teleport_to($player, ares_get_faction_spawn_pos($faction_id));
	starmade_set_spawn_player($player);

	my $faction_name = ares_get_faction_name($faction_id);
	starmade_broadcast("$player has been assigned to $faction_name!");
}


## ares_set_player_credits
# Set a player's credits to a specific amount
# INPUT1: player name
# INPUT2: credit amount
sub ares_set_player_credits {
	my $player = $_[0];
	my $credits = $_[1];

	if (!$player) {
		cluck("ares_set_player_credits: player name must be given as first argument.");
		return 0;
	}
	if ($credits=~/\D/) {
		cluck("ares_set_player_credits: given invalid credits value '$credits'.");
		return 0;
		
	}

	stdout_log("Setting '$player''s credits to $credits", 6);
	my %player_data = %{starmade_player_info($player)};
	my $current_credits = $player_data{credits};
	my $credit_diff = $credits - $current_credits;

	if ($credit_diff) {
		starmade_give_credits($player, $credit_diff);
	}

	%player_data = %{starmade_player_info($player)};
	if ($player_data{credits} != $credits) {
		stdout_log("Failed setting '$player''s credits to $credits", 4);
		return 0;
	
	}
	return 1;
}

## ares_add_account
# Make a player a member of the given faction
# INPUT1: Account name
sub ares_add_account {
	my $account = $_[0];

	if (!$account) {
		cluck("ares_add_account: account name must be provided.");
		return 0;
	}

	if ( -w "$ares_core::ares_state/Accounts") {
		$account ="\n$account";
	}
	open(my $account_fh, ">>", "$ares_core::ares_state/Accounts") or starmade_broadcast("can't open file '$ares_core::ares_state/Accounts': $!");
	flock($account_fh, 2);
	print $account_fh $account;
	close($account_fh);
}

## ares_check_account
# Check if player has already logged in with this account.
# INPUT1: Account name
sub ares_check_account {
	my $account = $_[0];

	if (!$account) {
		cluck("ares_check_account: account name must be provided.");
		return 0;
	}
	
	open(my $account_fh, "<", "$ares_core::ares_state/Accounts") or return 0;
	flock($account_fh, 2);
	my @accounts = <$account_fh>;
	foreach my $sav_account (@accounts) {
		if ($account eq $sav_account) {
			close($account_fh);
			return 1;
		}
	}
	close($account_fh);
	return 0;
}

## ares_player_lock
# lock player for changes
# INPUT1: player name
# OUTPUT: success if you got the lock, failure if you didn't
sub ares_player_lock {
	my $player = $_[0];

	if (!$player) {
		cluck("ares_player_lock: player name must be provided");
		return 0;
	}

	mkdir($ares_core::ares_state_player);
	open(my $fh, ">", "$ares_core::ares_state_player/$player.lock") || return 0;
	flock($fh, 2) || return 0;
	return $fh;
}

## ares_player_unlock
# unlock player for changes
# INPUT1: player name
sub ares_player_unlock {
	my $player_fh = $_[0];
	if (!$player_fh) {
		cluck("$player_fh: invalid file handle provided.");
	}
	close($player_fh);
}

#############################
####### FACTION CALLS #######
#############################


## ares_player_faction_valid 
# Check if faction is a valid player faction
# INPUT1: faction_id
# OUTPUT: 1 if faction is valid, otherwise 0
sub ares_player_faction_valid {
	my $faction_id = $_[0];

	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_player_faction_valid: faction id is not valid: '$faction_id'");
		return 0;
	}

	if ( $faction_id && -d "$ares_core::ares_state_faction/$faction_id") {
		return 1;
	}

	return 0;
}

## ares_get_player_factions
# Get a list of the ares factions
# OUTPUT: array of the main factions
sub ares_get_player_factions {
	my @factions;
	for (my $teamNum = 1; $teamNum <= $ares_core::ares_config{General}{team_number}; $teamNum++) {
		push(@factions, ares_team_to_faction($teamNum));
	}
	return \@factions;
}

## ares_get_all_factions
# Get a list of the ares factions including the npc factions
# OUTPUT: array of all the factions
sub ares_get_all_factions {
	my @main_factions = @{ares_get_player_factions()};
	my @factions = @main_factions;
	foreach my $faction_id (@main_factions) {
		push(@factions,ares_get_faction_npc($faction_id));
	}
	return \@factions;
}

## ares_get_faction_name
# Get the name of the faction from it's id
# INPUT1: faction id
# OUTPUT: faction name
sub ares_get_faction_name {
	my $id = $_[0];
	if (!($id=~/^-?\d+$/)) {
		cluck("ares_get_faction_name: invalid faction id given '$id'");
		return 0;
	}
	if ($id <= 0) {
		return "";
	}
	open(my $faction_fh, "<", "$ares_core::ares_state_faction/$id/name") or return;
	my $name = <$faction_fh>;
	close($faction_fh);
	return $name;
}

## ares_set_faction_name
# Set the Faction name of a faction in the ares database
# INPUT1: faction id
# INPUT2: faction name
sub ares_set_faction_name {
	my $id = $_[0];
	my $name = $_[1];
	if (!($id=~/^-?\d+$/)) {
		cluck("ares_set_faction_name: invalid faction id given '$id'");
		return 0;
	}
	if (!$name) {
		cluck("ares_set_faction_name: faction name must be specified");
		return 0;

	}
	if ($id <= 0) {
		return "";
	}

	mkdir("$ares_core::ares_state_faction/$id");
	open(my $faction_fh, ">", "$ares_core::ares_state_faction/$id/name") or return;
	print $faction_fh $name;
	close($faction_fh);
}

## ares_set_team_faction
# Get the faction id for a given team (map terminology)
# INPUT1: team number
# OUTPUT: faction id
sub ares_set_team_faction {
	my $teamNum = $_[0] -1;
	my $faction_id = $_[1];

	if (!($teamNum=~/^-?\d+$/)) {
		cluck("ares_set_team_faction: invalid team number given '$teamNum'");
		return 0;
	}
	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_set_team_faction: invalid faction_id given '$faction_id'");
		return 0;
	}

	open(my $team_fh, ">", "$ares_core::ares_data/team$teamNum");
	print $team_fh $faction_id;
	close($team_fh);
}

## ares_team_to_faction
# Get the faction id for a given team (map terminology)
# INPUT1: team number
# OUTPUT: faction id
sub ares_team_to_faction {
	my $teamNum = $_[0];

	if (!($teamNum=~/^-?\d+$/)) {
		cluck("ares_team_to_faction: invalid team number given '$teamNum'");
		return 0;
	}

	if ($teamNum > 0) {
		my $faction_id;
		$teamNum -= 1;
		open(my $team_fh, "<", "$ares_core::ares_data/team$teamNum") or return 0;
		$faction_id = join('', <$team_fh>);
		close($team_fh);
		return $faction_id;
	}
	return $teamNum;
}

## ares_get_faction_state
# Get the current state of a faction (defeated or not defeated)
# INPUT1: faction id
# OUTPUT: state of faction (basically defeated or not)
sub ares_get_faction_state {
	my $id = $_[0];
	if (!($id=~/^-?\d+$/)) {
		cluck("ares_get_faction_state: invalid faction id given '$id'");
		return 0;
	}
	if ($id <= 0) {
		return "";
	}
	open(my $faction_fh, "<", "$ares_core::ares_state_faction/$id/State") or return;
	my $state = join("", <$faction_fh>);
	close($faction_fh);
	return $state;
}

## ares_set_faction_state
# Set the Current state for the given faction
# INPUT1: faction id
# INPUT2: state to set the faction to
sub ares_set_faction_state {
	my $id = $_[0];
	my $state = $_[1];

	if (!($id=~/^-?\d+$/)) {
		cluck("ares_set_faction_state: invalid faction id given '$id'");
		return 0;
	}
	if (!$state) {
		cluck("ares_set_faction_state: a state must be given.");
		return 0;
	}

	stdout_log("Setting faction '$id' to '$state'", 5);
	if ($id <= 0) {
		return "";
	}
	mkdir("$ares_core::ares_state_faction/$id");
	open(my $faction_fh, ">", "$ares_core::ares_state_faction/$id/State") or return;
	print $faction_fh $state;
	close($faction_fh);
}

## ares_get_faction_home
# Get the faction home location of a faction
# INPUT1: faction id
# OUTPUT: location of faction home (space delimited string)
sub ares_get_faction_home {
	my $faction_id = $_[0];

	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_get_faction_home: invalid faction id given '$faction_id'");
		return 0;
	}

	open(my $home_fh, "<", "$ares_core::ares_state_faction/$faction_id/Home") or return;
	my $home = join("", <$home_fh>);
	close($home_fh);
	return $home;
}

## ares_set_faction_home
# set the faction home of a faction
# INPUT1: faction id
# INPUT2: location to make home (space delimited list)
sub ares_set_faction_home {
	my $faction_id = $_[0];
	my $home = $_[1];

	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_set_faction_home: invalid faction id given '$faction_id'");
		return 0;
	}
	if (!$home) {
		cluck("ares_set_faction_home: requires home location to be set");
		return 0;
	}

	stdout_log("Setting sector '$home' as faction $faction_id\'s home", 6);
	mkdir("$ares_core::ares_state_faction/$faction_id");
	open(my $home_fh, ">", "$ares_core::ares_state_faction/$faction_id/Home") or return;
	print $home_fh $home;
	close($home_fh);
}

## ares_get_faction_spawn_pos
# Get the faction spawning position
# INPUT1: faction id
# OUTPUT: position to spawn players (space delimited string)
sub ares_get_faction_spawn_pos {
	my $faction_id = $_[0];

	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_get_faction_spawn_pos: invalid faction id given '$faction_id'");
		return 0;
	}

	open(my $home_fh, "<", "$ares_core::ares_state_faction/$faction_id/Spawn") or return;
	my $home = join("", <$home_fh>);
	close($home_fh);
	return $home;
}

## ares_set_faction_spawn_pos
# set the faction spawning position
# INPUT1: faction id
# INPUT2: postition to have players spawn
sub ares_set_faction_spawn_pos {
	my $faction_id = $_[0];
	my $pos = $_[1];

	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_set_faction_spawn_pos: invalid faction id given '$faction_id'");
		return 0;
	}
	if (!$pos) {
		cluck("ares_set_faction_spawn_pos: requires spawn pos to be set");
		return 0;
	}

	stdout_log("Setting sector '$pos' as faction $faction_id\'s home", 6);
	stdout_log("Setting sector '$pos' as faction $faction_id\'s home", 6);
	mkdir("$ares_core::ares_state_faction/$faction_id");
	open(my $home_fh, ">", "$ares_core::ares_state_faction/$faction_id/Spawn") or return;
	print $home_fh $pos;
	close($home_fh);
}

## ares_set_faction_npc
# Each main faction gets an npc faction to have 
# as support that cannot be controlle directly. 
# This sets the faction id of that faction.
# INPUT1: main faction id
# INPUT2: npc faction id
sub ares_set_faction_npc {
	my $faction_id = $_[0];
	my $npc_faction_id = $_[1];

	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_set_faction_npc: invalid faction id given '$faction_id'");
		return 0;
	}
	if (!($npc_faction_id=~/^-?\d+$/)) {
		cluck("ares_set_faction_npc: invalid faction id given '$npc_faction_id'");
		return 0;
	}

	mkdir("$ares_core::ares_state_faction/$faction_id");
	open(my $npc_fh, ">", "$ares_core::ares_state_faction/$faction_id/NPC") or return;
	print $npc_fh $npc_faction_id;
	close($npc_fh);
}

## ares_get_faction_npc
# Each main faction gets an npc faction to have 
# as support that cannot be controlle directly. 
# This gets the faction id of that faction 
# given the main faction's id.
# INPUT1: main faction id
# OUTPUT: npc faction id
sub ares_get_faction_npc {
	my $faction_id = $_[0];

	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_get_faction_npc: invalid faction id given '$faction_id'");
		return 0;
	}

	open(my $npc_fh, "<", "$ares_core::ares_state_faction/$faction_id/NPC") or return $faction_id;
	my $npc_faction_id = join('', <$npc_fh>);
	close($npc_fh);
	return $npc_faction_id;
}

## ares_get_faction_members
# Get a list of faction members for the given faction
# INPUT1: faction id
# OUTPUT: list of faction members
sub ares_get_faction_members {
	my $id = $_[0];

	if (!($id=~/^-?\d+$/)) {
		cluck("ares_get_faction_members: invalid faction id given '$id'");
		return 0;
	}

	my @tmp = ();
	my @members = ();
	open(my $faction_fh, "<", "$ares_core::ares_state_faction/$id/Players") or return \@members;
	flock($faction_fh, 1);
	@tmp = <$faction_fh>;
	close($faction_fh);
	foreach my $member (@tmp) {
		$member=~s/\s//ig;
		if ($member =~/\S/) {
			push(@members, $member);
		};
	};

	return \@members;
}

## ares_add_faction_member
# Make a player a member of the given faction
# INPUT1: player name
# INPUT2: faction id
sub ares_add_faction_member {
	my $player = $_[0];
	my $faction_id = $_[1];

	if (!$player) {
		cluck("ares_add_faction_member: must provide player name");
		return 0;
	}
	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_add_faction_member: invalid faction id given '$faction_id'");
		return 0;
	}

	stdout_log("Setting '$player' faction to '$faction_id'", 5);
	my $old_faction_id = ares_get_player_faction($player);
	while ($old_faction_id) {
		my @members = @{ares_get_faction_members($old_faction_id)};
		
		open(my $members_fh, ">", "$ares_core::ares_state_faction/$old_faction_id/Players");
		flock($members_fh, 2);
		foreach my $member (@members) {
			if ($member ne $player) {
				print $members_fh "$member\n";
			}
		}
		close($members_fh);
		$old_faction_id = ares_get_player_faction($player);
	}

	if ( -w "$ares_core::ares_state_faction/$faction_id/Players") {
		$player ="\n$player";
	}
	open(my $member_fh, ">>", "$ares_core::ares_state_faction/$faction_id/Players") 
		or starmade_broadcast("can't open file '$ares_core::ares_state_faction/$faction_id/Players': $!");
	flock($member_fh, 2);
	print $member_fh $player;
	close($member_fh);
	starmade_faction_add_member($player, $faction_id);
}

## ares_get_player_faction
# Get the faction id of a player
# INPUT1: player name
# OUTPUT: faction id of player's faction
sub ares_get_player_faction {
	my $player = $_[0];

	if (!$player) {
		cluck("ares_get_player_faction: must provide player name");
		return 0;
	}

	my @faction_ids = @{ares_get_player_factions()};
	foreach my $faction_id (@faction_ids) {
		my @members = @{ares_get_faction_members($faction_id)};
		foreach my $member (@members) {
			if ( $player eq $member ) {
				return $faction_id;
			};
		};
		
	}
	stdout_log("Failed to get faction for '$player'", 5);
	return;
}

## ares_unfaction_player
# Remove player from any faction
# INPUT1: player name
sub ares_unfaction_player {
	my $player = $_[0];
	
	if (!$player) {
		cluck("ares_unfaction_player: must provide player name");
		return 0;
	}

	stdout_log("Removing '$player' from all factions", 6);
	my $faction_id = ares_get_player_faction($player);
	while ($faction_id) {
		my @members = @{ares_get_faction_members($faction_id)};
		starmade_faction_del_member($player, $faction_id);
		
		open(my $members_fh, ">", "$ares_core::ares_state_faction/$faction_id/Players");
		flock($members_fh, 2);
		foreach my $member (@members) {
			if ($member ne $player) {
				print $members_fh "$member\n";
			}
		}
		close($members_fh);
		$faction_id = ares_get_player_faction($player);
	}
	return;
}

## ares_fix_faction
# Put player back in the faction they should be in.
# INPUT1: player name
sub ares_fix_faction {
	my $player = $_[0];

	if (!$player) {
		cluck("ares_fix_faction: must provide player name");
		return 0;
	}

	stdout_log("Fixing Faction membership for '$player'", 6);
        my %player_info = %{starmade_player_info($player)};
        my $cur_faction = $player_info{faction};
        my $correct_faction = ares_get_player_faction($player);

        if ($cur_faction && $correct_faction && $correct_faction == $cur_faction) {
                return;
        }
	if ($correct_faction) {
		ares_add_faction_member($player, $correct_faction);
	}
	else {
		ares_new_player($player);
	};
}

## ares_get_faction_sizes
# Get the numeric sizes of all factions in hash form
# OUTPUT: hash of faction sizes in format of %HASH{faction_id} = size
sub ares_get_faction_sizes {
	my @faction_ids = @{ares_get_player_factions()};
	my %player_list = %{starmade_player_list()};
	my %faction_sizes;
	foreach my $faction_id (@faction_ids) {
		my @members = @{ares_get_faction_members($faction_id)};
		$faction_sizes{$faction_id} = 0;
		foreach my $player (@members) {
			if ($player_list{$player}) {
				$faction_sizes{$faction_id}++;
			}
		}
	}
	return \%faction_sizes;
}

## ares_notify_faction
# sent a message to all players in a givenn faction
# INPUT1: faction id
sub ares_notify_faction {
	my $faction_id = $_[0];
	my $message = $_[1];

	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_notify_faction: invalid faction id given '$faction_id'");
		return 0;
	}
	if (!$message) {
		cluck("ares_notify_faction: must provide a message to send");
	}

	my @members = @{ares_get_faction_members($faction_id)};
	for my $player (@members) {
		starmade_pm($player, $message);
	}
}

## ares_get_starting_credits
# Get the credits players are to start with.
# OUTPUT: credits players are to start with
sub ares_get_starting_credits {
	open(my $credits_fh, "<", "$ares_core::ares_state/starting_credits") or return;
	my $credits = <$credits_fh>;
	close($credits_fh);
	return $credits;
}

## ares_set_starting_credits
# Set the credits players are to start with.
# INPUT: credits players are to start with
sub ares_set_starting_credits {
	my $credits = $_[0];

	if ($credits=~/\D/) {
		cluck("ares_set_starting_credits: invalid number given: $credits");
		return 0;
	}
	open(my $credits_fh, ">", "$ares_core::ares_state/starting_credits") or return;
	print $credits_fh $credits;
	close($credits_fh);
}

## fix_players_factions
# make sure all players are factioned correctly
# INPUT1: player list hash
sub fix_players_factions {
	my %player_list = %{$_[0]};

	Player: foreach my $player (keys %player_list) {
		if (starmade_is_admin($player)) {
			next Player;
		}
		if (!(defined $player_list{$player}{control})) {
			next Player;
		}
		my $lock_fh = ares_player_lock($player);
		ares_fix_faction($player);
		ares_player_unlock($lock_fh);
	}
}


1;
