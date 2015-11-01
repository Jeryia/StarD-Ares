package ares_game;
use lib("./lib");
use ares_core;
use ares_faction;
use ares_map;
use ares_object;

use lib("../../lib");
use stard_lib;
use stard_log;


our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_set_game_state ares_get_game_state ares_defeat ares_game_status_string ares_clean_all ares_objectives_owned ares_get_credit_scaling ares_setup_game_env);


## ares_set_game_state
# Set the current game state
# INPUT1: state to set the game in (waiting_for_players, waiting_start, in_progress, or completed)
sub ares_set_game_state {
	my $state = $_[0];

	stdout_log("Setting game state to '$state'", 5);
	open(my $state_fh, ">", "$ares_core::ares_state/Status") or return;
	print $state_fh $state;
	close($state_fh);
}

## ares_get_game_state
# Get the current game state
# OUTPUT: state of the game (waiting_for_players, waiting_start, in_progress, or completed)
sub ares_get_game_state {
	open(my $state_fh, "<", "$ares_core::ares_state/Status") or return;
	my $state =  join("",<$state_fh>);
	close($state_fh);
	return $state;
}

## ares_defeat
# Set the given faction to defeated. Check if 
# there is a winner. If there is a winner, 
# set the game to complete.
# INPUT1: faction id
sub ares_defeat {
	my $faction = $_[0];
	my @faction_ids = @{ares_get_factions()};
	my $faction_name = ares_get_faction_name($faction);

	print "ares_defeated: $faction\n";
	stdout_log("Faction '$faction' has been defeated", 5);
	open(my $faction_fh, ">", "$ares_core::ares_state_faction/$faction/State");
	print $faction_fh "Defeated";
	close($faction_fh);
	stard_broadcast("$faction_name has been DEFEATED!");
	
	my @surviving;
	foreach my $id (@faction_ids) {
		
		open(my $faction_fh, "<", "$ares_core::ares_state_faction/$id/State");
		my $state = join("", <$faction_fh>);
		close($faction_fh);
		if ($state eq 'Active') {
			push(@surviving, $id);
		}
	}
	
	
	if (@surviving == 1) {
		my $faction_name = ares_get_faction_name($surviving[0]);
		stard_broadcast("$faction_name is VICTORIOUS!");
		stdout_log("Faction '$faction_name' is victorious", 5);
		ares_set_game_state("complete");
	}
}

## ares_game_status_string
# Get a full game status string (generally just broadcasted out.
# INPUT1: faction id (gives data from the perspective of a faction)
# INPUT2: type of output to give
# OUTPUT: status string
sub ares_game_status_string {
	my $faction = $_[0];
	my $type = $_[1];



	my %map_config = %{ares_get_map_config()};
	my $output = "";
	if (!%map_config) {
		return "An error occurred getting map data\n";
	}
	if ($type && $type ne 'base' && $type ne 'control') {
		return "$type is not a valid type to give"
	}

	my @objects = sort(keys %map_config);
	$output .= "Game Status: " . ares_get_game_state() . "\n";

	if (!$type || $type eq 'base') {

		$output .= "##### Base Status #####\n";
		$output .= "(You want to destroy any owned by your enemy)\n";
		$output .= "    Name(location)            Owner\n";
		$output .= "    --------------                      -----\n";
		foreach my $object (@objects) {
			if ($map_config{$object}{objective}) {
				my $o_status = ares_read_object_status($object);
				$output .= sprintf("%-25s     %-10s\n", "$object($map_config{$object}{sector})", ares_object_status_to_string($o_status, $faction));
			}
		}
	}

	if (!$type || $type eq 'control') {
		$output .= "##### Control Point Status #####\n";
		$output .= "(You want to capture these)\n";
		$output .= "    Name(location)            Owner\n";
		$output .= "    --------------                      -----\n";
		foreach my $object (@objects) {
			if (!$map_config{$object}{objective} && $map_config{$object}{can_capture}) {
				my $o_status = ares_read_object_status($object);
				$output .= sprintf("%-25s     %-10s\n", "$object($map_config{$object}{sector})", ares_object_status_to_string($o_status, $faction));
			}
		}
	}
	return $output;
};

## ares_clean_all
# Clean up the game (generally clean up a game that's completed so a new one can start)
sub ares_clean_all {
	ares_set_game_state("completed");
	stdout_log("Cleaning up everything from the last game, and a little more", 5);

	my @factions = @{ares_get_factions()};

	foreach my $faction_id (@factions) {
		if ($faction_id > 0) {
			my @members = @{ares_get_faction_members($faction_id)};
			foreach my $member (@members) {
				ares_unfaction_player($member);
			}
			stdout_log("Clearing faction '$faction_id'", 6);
			unlink("$ares_core::ares_state_faction/$faction_id/State");
			unlink("$ares_core::ares_state_faction/$faction_id/Players");
			unlink("$ares_core::ares_state_faction/$faction_id/Home");
		};
	};

	my @players = keys %{stard_player_list()};

	foreach my $player (@players) {
		stdout_log("Cleaning $player", 6);
		stard_give_all_items($player, -1000000);
		stard_give_credits($player, -2000000000);
	}

	stdout_log("Deleting everything", 6);
	if (!stard_despawn_all("", "all", "0")) {
		stard_pm("Error Despawning Everything.");
		print stard_last_output();
		stdout_log("Error Despawning Sector Everything", 1);
		exit 0;
	};

	my %map_config = %{ares_get_map_config()};
	if (keys %map_config) {
		foreach my $entity (keys %map_config) {
			my $sector = $map_config{$entity}{sector};
		
			stdout_log("Deleting sector '$sector'", 6);
			stard_cmd("/load_sector_range $sector $sector");
			if (!stard_despawn_sector("", "all", "0", $sector)) {
				stard_broadcast("Error Despawning Sector $sector.");
				print stard_last_output();
				stdout_log("Error Despawning Sector '$sector'", 1);
				exit 0;
			};
			stdout_log("Deleting all '$entity'", 6);
			if (!stard_despawn_all("$entity", "all", "0")) {
				stard_broadcast("Error Despawning All '$entity'");
				print stard_last_output();
				stdout_log("Error Despawning All '$entity'", 1);
				exit 0;
			};
			unlink("$ares_core::ares_state/Objects/$entity");
			unlink("$ares_core::ares_state/Objects/$entity.entity");
		};

		unlink("$ares_core::ares_state/map");
		unlink("$ares_core::ares_state/cur.map");
		unlink("$ares_core::ares_state/Accounts");
		unlink("$ares_core::ares_state/vote");
	}


	stdout_log("Despawning Sector '2 2 2'", 6);
	if (!stard_despawn_sector("", "all", "0", "2 2 2")) {
		stard_broadcast("Error Despawning Sector 2 2 2.");
		print stard_last_output();
		stdout_log("Error Despawning Sector 2 2 2.", 1);
		exit 0;
	};
	
	if (
		$ares_core::ares_home =~/\S\S+/ &&
		! ($ares_core::ares_state =~/\.\.$/) &&
		! ($ares_core::ares_state =~/\.\.\/$/)
	) {
		stdout_log("Cleaning State Directory", 6);
		rmtree("$ares_core::ares_state/Objects");
		rmtree("$ares_core::ares_state/Players");
	}
	else {
		print "didn't clean up state dir $ares_core::ares_state\n\n";
	}
	stdout_log("Cleaning Complete", 5);
}

## ares_objectives_owned
# Get the number of objectives a faction currently owns
# INPUT1: faction id of faction to get objective info about
# OUTPUT: Number of objectives currently owned.
sub ares_objectives_owned {
	my $faction_id = $_[0];

	my $objectives;
	my %ares_map_config = %{ares_get_map_config()};
	Entity: foreach my $object (keys %ares_map_config) {
		if (!$ares_map_config{$object}{objective}) {
			next Entity;
		};
		if (int(ares_read_object_status($object)) == $faction_id) {
			$objectives++;
		};
	};
};


## ares_get_credit_scaling
# Get the current credit scaling amount
# OUTPUT: amount that the credit allowance to players is multiplied by (based on time in game)
sub ares_get_credit_scaling {
	my @stat = stat("$ares_core::ares_state/Status");
	my $game_start = $stat[9];
	my $game_time = time() - $game_start;

	# How much to increase the credit amount given to factions every 5 minutes.
	my $increase_rate = $ares_core::ares_config{General}{credit_scaling};

	# 300 is 5 minutes in seconds
	return 1 + ($increase_rate/300 * $game_time);
}

## ares_setup_game_env
# Sets up everything needed to setup a new game
sub ares_setup_game_env {
	mkdir($ares_core::ares_state);
	mkdir($ares_core::ares_state_faction);
	mkdir($ares_core::ares_state_player);
	mkdir($ares_core::ares_state_objects);
	mkdir($ares_core::ares_data);
}


1;
