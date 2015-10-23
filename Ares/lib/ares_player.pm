package ares_player;
use lib("./lib");
use ares_core;
use ares_faction;
use ares_game;
use ares_player;

use lib("../../lib");
use stard_lib;
use stard_log;


our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_new_player ares_new_player_setup ares_set_player_credits ares_add_account ares_check_account ares_player_lock ares_player_unlock);



## ares_new_player
# Deal with a new player
# INPUT1: name of new player
sub ares_new_player {
	my $player = $_[0];

	my $faction_id = ares_get_player_faction($player);
	
	if (stard_is_admin($player)) {
		return;
	};
	my $game_state = ares_get_game_state();
	if ($game_state eq "completed" || $game_state eq "" ) {
		return;
	};

	if (!$faction_id) {
		my @faction_ids = @{ares_get_factions()};
		my %player_list = %{stard_player_list()};
		my %faction_members;
		foreach my $faction_id (@faction_ids) {
			my @members = @{ares_get_faction_members($faction_id)};
			foreach my $player (@members) {
				if ($player_list{$player}) {
					$faction_members{$faction_id}++;
				}
			}
		}
		Faction: foreach my $faction_id1 (@faction_ids) {
			foreach my $faction_id2 (@faction_ids) {
				if (
					$faction_members{$faction_id1} >= $faction_members{$faction_id2} &&
					$faction_id1 != $faction_id2
				) {
					next Faction;
				}
			}
			ares_new_player_setup($player, $faction_id1);
			return;
		}
		my $rand_faction = int(rand(@faction_ids));
		ares_new_player_setup($player, $faction_ids[$rand_faction]);
	}
	else {
		stard_faction_add_member($player, $faction_id);
	}
}

## ares_new_player_setup 
# Set the player to new game state (remove everything they have, then give them the starting stuff)
# INPUT1: player name
# INPUT2: faction id they are to be in
sub ares_new_player_setup {
	my $player = $_[0];
	my $faction_id = $_[1];


	my %player_info = %{stard_player_info($player)};

	stdout_log("Setting up new player '$player'", 6);
	stard_give_all_items($player, -1000000);
	if ($player_info{smname}) {
		if (ares_check_account($player_info{smname}) && $player_info{smname} ne 'null') {
			stdout_log("'$player' detected using multiple accounts. Setting credits to nothing...", 5);
			stard_broadcast("Anti-cheat: multiple players under same account detected '$player'. Player gets no starting rescources...");
			ares_set_player_credits($player, 0);
			
			stard_give_item($player, "Ship Core", 1);
			stard_give_item($player, "Power Reactor", 1);
			stard_give_item($player, "Thruster", 4);
			ares_add_faction_member($player, $faction_id);
			my $home = ares_get_faction_home($faction_id);
			stard_change_sector_for($player, $home);
			stard_set_spawn_player($player);
	
			my $faction_name = ares_get_faction_name($faction_id);
			stard_broadcast("$player has been assigned to $faction_name!");
			return 1;
		}
		else {
			ares_add_account($player_info{smname});
		}
	}
	
	if(!ares_set_player_credits($player, $ares_core::ares_config{General}{starting_credits})) {
		my %player_info = stard_player_info($player);
		# if player is not online anymore stop trying, we'll get them next time
		if (!(keys %player_info)) {
			return 0;
		}
		sleep 1;
		if (!ares_set_player_credits($player, $ares_core::ares_config{General}{starting_credits})) {
			stard_broadcast("Error setting up environment for $player.");
			stard_broadcast("Reccommend $player try relogging.");
		};
	};

	stard_give_item($player, "Ship Core", 1);
	stard_give_item($player, "Power Reactor", 1);
	stard_give_item($player, "Thruster", 4);

	ares_add_faction_member($player, $faction_id);
	my $home = ares_get_faction_home($faction_id);
	stard_change_sector_for($player, $home);
	stard_set_spawn_player($player);

	my $faction_name = ares_get_faction_name($faction_id);
	stard_broadcast("$player has been assigned to $faction_name!");
}

## ares_set_player_credits
# Set a player's credits to a specific amount
# INPUT1: player name
# INPUT2: credit amount
sub ares_set_player_credits {
	my $player = $_[0];
	my $credits = $_[1];

	stdout_log("Setting '$player''s credits to $credits", 6);
	my %player_data = %{stard_player_info($player)};
	my $current_credits = $player_data{credits};
	my $credit_diff = $credits - $current_credits;

	if ($credit_diff) {
		stard_give_credits($player, $credit_diff);
	}

	%player_data = %{stard_player_info($player)};
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
	my $faction_id = $_[1];

	if ( -w "$ares_core::ares_state/Accounts") {
		$account ="\n$account";
	}
	open(my $account_fh, ">>", "$ares_core::ares_state/Accounts") or stard_broadcast("can't open file '$ares_state/Accounts': $!");
	flock($account_fh, 2);
	print $account_fh $account;
	close($account_fh);
}

## ares_check_account
# Check if player has already logged in with this account.
# INPUT1: Account name
sub ares_check_account {
	my $account = $_[0];
	my $faction_id = $_[1];

	
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
	close($player_fh);
}


1;
