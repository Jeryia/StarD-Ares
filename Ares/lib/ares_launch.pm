#!perl
package ares_launch;
use strict;

use File::Copy;
use Carp;

use lib("./lib");
use ares_core;
use ares_map;
use ares_game;
use ares_object;
use ares_player;

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

my $ares_home = '.';
my $ares_maps = "$ares_home/Maps";
my $ares_state = "$ares_home/State";
my $ares_state_faction = "$ares_state/Factions";
my $ares_state_player = "$ares_state/Players";

my $timestamp = `date +%s`;
$timestamp =~s/\s//g;

our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_start_new_game ares_setup_factions ares_setup_map assign_remaining_players);

## main
sub ares_start_new_game {
	my $map = shift(@_);

	starmade_broadcast("Setting up new game");
	starmade_broadcast("Please Standby...");
	stdout_log("Starting new game", 6);

	if (!$map && ares_get_config_field('default_map')) {
		$map = ares_get_config_field('default_map');
	}

	if (!$map) {
		starmade_broadcast("Error, no default map set, and no default map selected. Could not start.");
		print starmade_last_output();
		stdout_log("No default map found and no map requested. Cannot start a new game!", 0);
		return 0;
	}

	# wipe out the current setup
	ares_clean_all();

	ares_setup_game_env();
	# prep new map config
	if(!ares_set_cur_map($map)) {
		starmade_broadcast("Error Loading map: $map");
		starmade_broadcast("Check logs for more details: $map");
		stdout_log("Failed to load map '$map'", 0);
		return 0;
	}

	my %ares_map_config = %{ares_get_raw_map_config("$ares_maps/$map.map")};

	if (! keys %ares_map_config) {
		starmade_broadcast("Error Loading map: $map");
		stdout_log("Error Loading map: '$map'", 0);
	}

	ares_set_game_state("complete");

	ares_setup_factions();

	ares_setup_map(\%ares_map_config);

	assign_remaining_players();
	ares_set_game_state("");
	starmade_broadcast("Game Setup Complete!");
}

## ares_setup_factions
# Setup the factions needed to play the game.
sub ares_setup_factions {
	my @team_names;
	stdout_log("Setting Up Factions", 5);
	if (-r "$ares_home/data/team_names") {
		open(my $teams_fh, "<", "$ares_home/team_names");
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


	for (my $teamNum = 1; $teamNum <= ares_get_config_field('team_number'); $teamNum++) {
		my $team_name = $team_names[$teamNum-1];
		my $faction_id = ares_team_to_faction($teamNum);
		my $npc_faction_id = ares_get_faction_npc($faction_id);
		my $npc_name = "$team_name NPC";

		if (
			!$faction_id ||
			!$faction_list{$faction_id}
		) {
			stdout_log("Creating faction $team_name", 5);
			if(!starmade_faction_create($team_name, '')) {
				starmade_broadcast("Failed to start game...");
				print starmade_last_output();
				stdout_log("Failed to create faction $team_name. Aborting start game", 1);
				return 0;
			}
			my %faction_nlist=%{starmade_faction_list_bname()};
			$faction_id = $faction_nlist{$team_name}{id};

			mkdir("$ares_state_faction");
			mkdir("$ares_state_faction/$faction_id");
			ares_set_team_faction($teamNum, $faction_id);
			ares_set_faction_name($faction_id, $team_name);
		}

		
		if (
			!$npc_faction_id ||
			!$faction_list{$npc_faction_id}
		) {
			stdout_log("Creating faction $npc_name", 5);
			if (!starmade_faction_create($npc_name, '')) {
				starmade_broadcast("Failed to start game...");
				print starmade_last_output();
				stdout_log("Failed to create faction $npc_name. Aborting start game", 1);
				return 0;
			}
			my %faction_nlist=%{starmade_faction_list_bname()};
			$npc_faction_id = $faction_nlist{$npc_name}{id};
			ares_set_faction_npc($faction_id, $npc_faction_id);
		}

		ares_set_faction_state($faction_id, "Active");
		stdout_log("Faction '$team_name' is setup", 6);
	};

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

	my @main_factions = @{ares_get_player_factions()};
	my @factions = @{ares_get_all_factions()};
	foreach my $faction_id (@main_factions) {
		if ($faction_id > 0) {
			my $npc_faction_id = ares_get_faction_npc($faction_id);
				
			Faction2: foreach my $faction_id2 (@factions) {
				if ($faction_id2 == 0) {
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
};

## ares_setup_map
# Create whatever objects are needed by the given map
sub ares_setup_map {
	stdout_log("Setting up objects on the map", 5);
	mkdir "$ares_state/Objects";
	my %ares_map_config = %{$_[0]};
	Object: foreach my $object (keys %ares_map_config) {
		if ($object eq "General") {
			next Object;
		}
		stdout_log("Creating: $object", 6);
		$ares_map_config{$object}{sector} = starmade_location_add($ares_map_config{$object}{sector}, ares_get_config_field('map_center'));
		my $sector = $ares_map_config{$object}{sector};
		my $blueprint = $ares_map_config{$object}{blueprint};
		$ares_map_config{$object}{owner} = ares_team_to_faction($ares_map_config{$object}{owner});
		my $owner = $ares_map_config{$object}{owner};
		my $entity = "$object\_$timestamp";
		my $npc;
	
	
		stdout_log("Cleaning '$sector' of stuff (to ensure we don't spawn on top of things)", 6);
		starmade_cmd("/load_sector_range $sector $sector");
		# Clean out what's already in the system (pirate stations, trade outputs, and hoolagens)
		if (!starmade_despawn_sector("", "all", "0", $sector)) {
			starmade_boardcast("Error Despawning Sector $sector.\n");
			print starmade_last_output();
			stdout_log("Error Despawning Sector $sector... Aborting game start", 1);
			return 0;
		}
	
		if ($ares_map_config{General}{starting_credits}) {
			ares_set_starting_credits($ares_map_config{General}{starting_credits});
		}
		elsif(ares_get_config_field('starting_credits')) {
			ares_set_starting_credits(ares_get_config_field('starting_credits'));
		}
		else {
			ares_set_starting_credits('5000000');
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
};

sub assign_remaining_players {
	my %player_data = %{starmade_player_list()};
	mkdir "$ares_state_player";
	
	for my $player (keys %player_data) {
		ares_player_lock($player);
		ares_new_player($player);
		ares_player_unlock($player);
	};
}

