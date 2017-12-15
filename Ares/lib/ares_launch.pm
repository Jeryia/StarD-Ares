#!perl
package ares_launch;
use strict;

use File::Copy;
use File::Path;
use Carp qw(cluck);

use lib("./lib");
use ares_core;
use ares_map;
use ares_object;
use ares_player;
use ares_vote;

use lib("../../lib/perl");
use Starmade::Base;
use Starmade::Map;
use Starmade::Message;
use Starmade::Misc;
use Starmade::Sector;
use Starmade::Player;
use Starmade::Faction;
use Stard::Base;
use Stard::Log;


our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_setup_new_game ares_setup_factions ares_setup_map assign_remaining_players ares_clean_all ares_setup_game_env);


sub ares_setup_new_game {

	my $map;
	starmade_broadcast("Setting up new game");
	starmade_broadcast("Please Standby...");
	stdout_log("Starting new game", 6);

	if (ares_get_next_map()) {
		$map = ares_get_next_map();
		ares_set_next_map();
	}
	elsif (ares_vote_win()) {
		$map = ares_vote_win();
		ares_reset_votes();
	}
	else {
		my @maps = @{ares_get_map_list()};
		my $rand = int(rand($#maps + .9999));
		$map = $maps[$rand];
	}

	if (!$map) {
		starmade_broadcast("Error, could not find any maps to use. Could not start.");
		print starmade_last_output();
		stdout_log("No default map found and no map requested. Cannot start a new game!", 0);
		return 0;
	}
	starmade_broadcast("Loading Map: $map\n");
	stdout_log("Using Map: $map", 6);


	# wipe out the current setup
	if (!ares_clean_all()) {
		stdout_log("Clean failed. Cannot start a game!", 0);
		return 0;
	}

	# prep new map config
	if(!ares_set_cur_map($map)) {
		starmade_broadcast("Error Loading map: $map");
		starmade_broadcast("Check logs for more details: $map");
		stdout_log("Failed to load map '$map'", 0);
		return 0;
	}




	ares_setup_factions() or return 0;
	my %ares_map_config = %{ares_get_map_config($map)};
	if (!%ares_map_config) {
		starmade_broadcast("Error Loading map: $map");
		stdout_log("Error Loading map: '$map'", 0);
	}

	ares_setup_map(\%ares_map_config) or return 0;

	assign_remaining_players();

	starmade_cmd('/force_save');
	sleep 5;
	starmade_broadcast("Game Setup Complete!");
}

## ares_setup_factions
# Setup the factions needed to play the game.
sub ares_setup_factions {
	my $game_mode = ares_game::ares_get_game_mode();
	my @team_names;
	stdout_log("Setting Up Factions", 5);
	if (-r "$ares_core::ares_home/data/team_names") {
		open(my $teams_fh, "<", "$ares_core::ares_home/team_names");
		@team_names = <$teams_fh>;
		close($teams_fh);
		foreach my $team (@team_names) {
			$team=~s/^\s+//;
			$team=~s/\s+$//;
		}
	}
	else {
		@team_names = ("Alpha Squadron", "Beta Squadron", "Gamma Squadron", "Delta Squaldron");
	};

	my %faction_list = %{starmade_faction_list_bid()};
	my %faction_nlist;
	if (!$faction_list{-1}) {
		if (!starmade_faction_create('Pirates', '', -1)) {
			starmade_broadcast("Failed to start game...");
			print starmade_last_output();
			stdout_log("Failed to create faction 'Pirates'. Aborting start game", 1);
			return 0;
		}
	}
	if (!$faction_list{-10}) {
		if (!starmade_faction_create('Void Reincarnations', '', -10)) {
			starmade_broadcast("Failed to start game...");
			print starmade_last_output();
			stdout_log("Failed to create faction 'Void Reincarnations'. Aborting start game", 1);
			return 0;
		}
	}
	if (!$faction_list{-2}) {
		if (!starmade_faction_create('Trading Guild', '', -2)) {
			starmade_broadcast("Failed to start game...");
			print starmade_last_output();
			stdout_log("Failed to create faction 'Trading Guild'. Aborting start game", 1);
			return 0;
		}
	}
	if (!$faction_list{-3}) {
		if (!starmade_faction_create('Doodads', '', -3)) {
			starmade_broadcast("Failed to start game...");
			print starmade_last_output();
			stdout_log("Failed to create faction 'Doodads'. Aborting start game", 1);
			return 0;
		}
	}

	stdout_log("Setting relations between '-1' and '-2' to ally.", 6);
	if(!starmade_faction_mod_relations(-1, -2, 'ally')) {
		print starmade_last_output();
		stdout_log("Failed setting relations between -1 and '-2' to ally.", 1);
	};

	stdout_log("Setting relations between '-1' and '-3' to ally.", 6);
	if(!starmade_faction_mod_relations(-1, -3, 'ally')) {
		print starmade_last_output();
		stdout_log("Failed setting relations between -1 and '-3' to ally.", 1);
	};


	
	## Create main factions
	if ($game_mode ne 'Survival') {
		my $num_teams = ares_game::ares_get_team_num();
		for (my $teamNum = 1; $teamNum <= $num_teams; $teamNum++) {
			if (!ares_create_team($team_names[$teamNum-1], \%faction_list, $teamNum)) {
				return 0;
			}
		};
	}
	my @main_factions = @{ares_get_player_factions()};
	my @factions = @{ares_get_all_factions()};

	## Set relations...
	foreach my $faction_id (@main_factions) {
		if ($faction_id > 0) {
			my $npc_faction_id = ares_get_faction_npc($faction_id);
				
			Faction2: foreach my $faction_id2 (@factions) {
				if ($faction_id2 == 0 or $faction_id == $faction_id2) {
					next Faction2;
				}
				if ($faction_id2 == $npc_faction_id) {
					stdout_log("Setting relations between '$faction_id' and '$faction_id2' to ally.", 6);
					if (!starmade_faction_mod_relations($faction_id, $faction_id2, 'ally')) {
						print starmade_last_output();
						stdout_log("Failed to set relations between '$faction_id' and '$faction_id2' to ally. Aborting start game...", 1);
						return 0;
					}
				}
				else {
					stdout_log("Setting relations between '$faction_id' and '$faction_id2' to enemy.", 6);
					if (!starmade_faction_mod_relations($faction_id, $faction_id2, 'enemy')) {
						print starmade_last_output();
						stdout_log("Failed to set relations between '$faction_id' and '$faction_id2' to enemy. Aborting start game...", 1);
						return 0;
					}
				}
			}
			stdout_log("Setting relations between '$faction_id' and '-2' to neutral.", 6);
			if(!starmade_faction_mod_relations($faction_id, -2, 'neutral')) {
				print starmade_last_output();
				stdout_log("Failed setting relations between '$faction_id' and '-2' to neutral.", 1);
			};
			stdout_log("Setting relations between '$faction_id' and '-1' to enemy.", 6);
			if(!starmade_faction_mod_relations($faction_id, -1, 'enemy')) {
				print starmade_last_output();
				stdout_log("Failed setting relations between '$faction_id' and '-1' to enemy.", 1);
			};
		};
	};
	return 1;
};

## ares_setup_map
# Create whatever objects are needed by the given map
sub ares_setup_map {
	stdout_log("Setting up objects on the map", 5);
	mkdir "$ares_core::ares_state/Objects";
	my %ares_map_config = %{$_[0]};
	starmade_setup_map(\%ares_map_config);
	if ($ares_map_config{General}{starting_credits}) {
		ares_set_starting_credits($ares_map_config{General}{starting_credits});
	}
	else {
		ares_set_starting_credits(ares_get_config_field('starting_credits'));
	}
	my $timestamp = `date +%s`;
	$timestamp =~s/\s//g;

	Object: foreach my $object (keys %ares_map_config) {
		if ($object eq "General") {
			next Object;
		}
		stdout_log("Creating: $object", 6);
		my $sector = $ares_map_config{$object}{sector};
		my $blueprint = $ares_map_config{$object}{blueprint};
		my $owner = $ares_map_config{$object}{owner};
		my $entity = "$object\_$timestamp";
		my $npc;
	
	
		stdout_log("Cleaning '$sector' of stuff (to ensure we don't spawn on top of things)", 6);
		#starmade_cmd("/load_sector_range $sector $sector");
		# Clean out what's already in the system (pirate stations, trade outputs, and hoolagens)
		if (!starmade_despawn_sector("", "all", "0", $sector)) {
			starmade_broadcast("Error Despawning Sector $sector.\n");
			print starmade_last_output();
			stdout_log("Error Despawning Sector $sector... Aborting game start", 1);
			return 0;
		}
	

		stdout_log("Deleting all entities that start with '$object' just to be sure of no naming collisions", 6);
		# Get rid of anything that already has the name (as names need to be unique).
		if (!starmade_despawn_all($object, "all", "0")) {
			starmade_broadcast("Error despawning all.\n");
			print starmade_last_output();
			stdout_log("Error despawning all... Aborting game start", 1);
			return 0;
		}
		ares_write_object_status($object, $owner);

		if (!ares_place_object($object, $ares_map_config{$object})) {
			return 0;
		}

		if ($ares_map_config{$object}{home}) {
			stdout_log("Setting $object as a home base", 6);
			ares_set_faction_home($owner, $sector);
			if (!starmade_sector_chmod($sector, "add", "noexit")) {
				if (!starmade_sector_chmod($sector, "add", "noexit")) {
					starmade_broadcast("Error setting noexit on $sector.\n");
					print starmade_last_output();
					stdout_log("Error setting noexit on $sector... Aborting game start", 1);
					return 0;
				}
			}
					
			if (! starmade_sector_chmod($sector, "add", "protected")) {
				if (!starmade_sector_chmod($sector, "add", "protected")) {
					starmade_broadcast("Error setting protected on $sector.\n");
					print starmade_last_output();
					stdout_log("Error setting protected on $sector... Aborting game start", 1);
					return 0;
				}
			}
			if ($ares_map_config{$object}{spawn}) {
				ares_set_faction_spawn_pos($owner, $ares_map_config{$object}{spawn});
			}
			else {
				ares_set_faction_spawn_pos($owner, '0 0 0');
			}
		};

		stdout_log("spawning additional mobs for sector $sector", 6);
		if ($owner != -2 && $ares_map_config{$object}{defenders}) {
			my @defenders = split(",", $ares_map_config{$object}{defenders});
			my @pos = (); 

			if ($ares_map_config{$object}{defender_pos}) {
				@pos = split(",", $ares_map_config{$object}{defender_pos});
			};
			ares_spawn_defenders($ares_map_config{$object}, \@defenders, \@pos);
		}

		if ($ares_map_config{$object}{pirates}) {
			my @pirates = split(",", $ares_map_config{$object}{pirates});
			my $pirate_faction = -1;
			my @pos = (); 

			if ($ares_map_config{$object}{pirate_pos}) {
				@pos = split(",", $ares_map_config{$object}{pirate_pos});
			};
			starmade_spawn_mobs_bulk(\@pirates, \@pos, $pirate_faction, $sector, 1);
		}

		if ($ares_map_config{$object}{doodads}) {
			my @doodads = split(",", $ares_map_config{$object}{doodads});
			my @pos = ();
			my $doodad_faction = -3;

			if ($ares_map_config{$object}{doodad_pos}) {
				@pos = split(",", $ares_map_config{$object}{doodad_pos});
			};
			starmade_spawn_mobs_bulk(\@doodads, \@pos, $doodad_faction, $sector, 0);
		};
	};
	return 1;
};

## ares_clean_all
# Clean up the game (generally clean up a game that's complete so a new one can start)
sub ares_clean_all {
	stdout_log("Cleaning up everything from the last game, and a little more", 5);
	ares_setup_game_env();

	my @factions = @{ares_get_player_factions()};

	foreach my $faction_id (@factions) {
		if ($faction_id > 0) {
			stdout_log("Clearing faction '$faction_id'", 6);
			unlink("$ares_core::ares_state_faction/$faction_id/State");
			unlink("$ares_core::ares_state_faction/$faction_id/Players");
			unlink("$ares_core::ares_state_faction/$faction_id/Home");
			unlink("$ares_core::ares_state_faction/$faction_id/Spawn");
			rmdir("$ares_core::ares_state_faction/$faction_id");
			starmade_faction_delete($faction_id);
			starmade_faction_create(ares_get_faction_name($faction_id), '', $faction_id);
		};
	};
	system('rm', '-rf', $ares_core::ares_state_faction);
	my @players = keys %{starmade_player_list()};

	foreach my $player (@players) {
		stdout_log("Cleaning $player", 6);
		starmade_give_all_items($player, -1000000);
		starmade_give_credits($player, -2000000000);
		starmade_change_sector_for($player, '2 2 2');
		starmade_teleport_to($player, '0 0 0');
	}

	stdout_log("Deleting everything", 6);
	if (!starmade_despawn_all("", "all", "0")) {
		starmade_pm("Error Despawning Everything.");
		print starmade_last_output();
		stdout_log("Error Despawning Sector Everything", 0);
		return 0;
	};

	my %map_config = %{ares_get_map_config()};
	starmade_clean_map_area(\%map_config, 'full');
	if (keys %map_config) {
		foreach my $entity (keys %map_config) {
			unlink("$ares_core::ares_state/Objects/$entity");
			unlink("$ares_core::ares_state/Objects/$entity.entity");
		};
		unlink("$ares_core::ares_state/map");
		unlink("$ares_core::ares_state/cur.map");
		unlink("$ares_core::ares_state/Accounts");
		unlink("$ares_core::ares_state/vote");
	}
	ares_set_cur_map();


	stdout_log("Despawning Sector '2 2 2'", 6);
	if (!starmade_despawn_sector("", "all", "0", "2 2 2")) {
		starmade_broadcast("Error Despawning Sector 2 2 2.");
		print starmade_last_output();
		stdout_log("Error Despawning Sector 2 2 2.", 0);
		return 0;
	};
	
	if (
		$ares_core::ares_home =~/\S/ &&
		! ($ares_core::ares_state =~/\.\.$/) &&
		! ($ares_core::ares_state =~/\.\.\/$/)
	) {
		stdout_log("Cleaning State Directory", 6);
		rmtree("$ares_core::ares_state/Objects");
		rmtree("$ares_core::ares_state/Players");
	}
	else {
		stdout_log("didn't clean up state dir $ares_core::ares_state\n\n", 2);
	}
	ares_setup_game_env();
	starmade_cmd('/force_save');
	sleep 5;
	stdout_log("Cleaning Complete", 5);
	return 1;
}

sub assign_remaining_players {
	my %player_data = %{starmade_player_list()};
	mkdir "$ares_core::ares_state_player";
	
	for my $player (keys %player_data) {
		my $lock = ares_player_lock($player);
		ares_new_player($player);
		ares_player_unlock($lock);
	};
	return 1;
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
