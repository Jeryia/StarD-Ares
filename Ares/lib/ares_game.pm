package ares_game;
use strict;
use warnings;

use Carp qw(cluck);
use File::Path;

use lib("./lib");
use ares_core;
use ares_player;
use ares_map;
use ares_object;
use ares_launch;

use lib("../../lib/perl");
use Starmade::Base;
use Starmade::Map;
use Starmade::Message;
use Starmade::Player;
use Starmade::Faction;
use Starmade::Sector;
use Stard::Base;
use Stard::Log;


our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_start_new_game ares_defeat ares_game_status_string ares_clean_all ares_objectives_owned ares_get_credit_scaling ares_set_game_state ares_get_game_state time_in_state ares_get_game_mode ares_void_spawn);

my $DATABASE_HANDLE;

sub ares_start_new_game {
	my $map = shift(@_);
	ares_set_game_state('complete');
	if ($map) {
		ares_set_next_map($map);
	}
	return ares_set_game_state('waiting_for_players');
}

## ares_defeat
# Set the given faction to defeated. Check if 
# there is a winner. If there is a winner, 
# set the game to complete.
# INPUT1: faction id
sub ares_defeat {
	my $faction = $_[0];

	if (!($faction=~/^-?\d+$/)) {
		cluck("ares_defeat: invalid faction id given '$faction'");
		return 0;
	}

	my @faction_ids = @{ares_get_player_factions()};
	my $faction_name = ares_get_faction_name($faction);

	stdout_log("Faction '$faction' has been defeated", 5);
	open(my $faction_fh, ">", "$ares_core::ares_state_faction/$faction/State");
	print $faction_fh "Defeated";
	close($faction_fh);
	starmade_broadcast("$faction_name has been DEFEATED!");
	my $game_mode = ares_get_game_mode();
	if ($game_mode eq "Survival") {

	}
	
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
		starmade_broadcast("$faction_name is VICTORIOUS!");
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

	if ($faction && !($faction=~/^-?\d+$/)) {
		cluck("ares_game_status_string: invalid faction id given '$faction'");
		return 0;
	}
	if (!(
		!$type ||
		$type eq 'base' ||
		$type eq 'control'
	)) {
		cluck("ares_game_status_string: invalid type given: '$type'");
		return 0;
	}



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
			if ($map_config{$object}{objective} and not $map_config{$object}{can_capture}) {
				my $o_status = ares_read_object_status($object);
				$output .= sprintf("%-25s     %-10s\n", "$object($map_config{$object}{sector})", ares_object_status_to_string($o_status, $faction));
			}
		}
		$output .= "-\n";
	}

	if (!$type || $type eq 'control') {
		$output .= "##### Control Point Status #####\n";
		$output .= "(You want to capture these)\n";
		$output .= "    Name(location)            Owner\n";
		$output .= "    --------------                      -----\n";
		foreach my $object (@objects) {
			if ($map_config{$object}{can_capture}) {
				my $o_status = ares_read_object_status($object);
				$output .= sprintf("%-25s     %-10s\n", "$object($map_config{$object}{sector})", ares_object_status_to_string($o_status, $faction));
			}
		}
		$output .= "-\n";
	}
	return $output;
};


## ares_objectives_owned
# Get the number of objectives a faction currently owns
# INPUT1: faction id of faction to get objective info about
# OUTPUT: Number of objectives currently owned.
sub ares_objectives_owned {
	my $faction_id = $_[0];

	if (!($faction_id=~/^-?\d+$/)) {
		cluck("ares_objectives_owned: invalid faction id given '$faction_id'");
		return 0;
	}
	print "checking objectives for: $faction_id\n";
	my $objectives = 0;
	my %ares_map_config = %{ares_get_map_config()};
	Entity: foreach my $object (keys %ares_map_config) {
		if (!$ares_map_config{$object}{objective}) {
			next Entity;
		};
		print "object '$object': " . int(ares_read_object_status($object)) . " ==  $faction_id\n";
		if (int(ares_read_object_status($object)) == $faction_id) {
			$objectives++;
		};
	};
	return $objectives;
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



## ares_set_game_state
# Set the current game state
# INPUT1: state to set the game in (waiting_for_players, waiting_start, in_progress, or complete)
sub ares_set_game_state {
	my $state = $_[0];

	my $things_ok = 1;
	_setup_db();
	ares_setup_game_env();

	my $old_state = ares_get_game_state();
	my $state_fh;
	if (!open($state_fh, ">", "$ares_core::ares_state/Status")) {
		stdout_log("Failed to open '$ares_core::ares_state/Status': $!\n", 0);
		return 0;
	}
	flock($state_fh, 2);

	starmade_countdown(0 , "Resetting...");
	if ($state eq 'waiting_for_players') {
		$things_ok = _switch_to_waiting_for_players($old_state);
	}
	elsif ($state eq 'waiting_start') {
		$things_ok = _switch_to_waiting_start($old_state);
	}
	elsif ($state eq 'in_progress') {
		$things_ok = _switch_to_in_progress($old_state);
	}
	elsif ($state eq 'complete') {
		$things_ok = _switch_to_complete($old_state);
	}
	else {
		cluck("ares_set_game_state: invalid state given: $state\n");
		$things_ok = 0;
	}

	if ($things_ok) {
		stdout_log("Setting game state to '$state'", 5);
		print $state_fh $state;
		_update_database_game_state($state);
	}
	else {
		stdout_log("Failed to set game state to '$state'! falling back to '$old_state'...", 1);
		print $state_fh $old_state;
	}
	close($state_fh);

	starmade_broadcast("You can view the progress of the game at any time with the !status command.");
	starmade_broadcast("To see how to play type !ares_help");
	if ($things_ok) {
		return 1;
	}
	return 0;
}

## ares_get_game_state
# Get the current game state
# OUTPUT: state of the game (waiting_for_players, waiting_start, in_progress, or complete)
sub ares_get_game_state {
	open(my $state_fh, "<", "$ares_core::ares_state/Status") or return;
	flock($state_fh, 1) or return;
	my $state =  join("",<$state_fh>);
	close($state_fh);
	if (
		$state ne 'waiting_for_players' and
		$state ne 'waiting_start' and
		$state ne 'in_progress' and
		$state ne 'complete'
	) {
		stdout_log("Invalid state '$state' detected... assuming not set.", 1);
		return '';
	}

	return $state;
}

## _switch_to_waiting_for_players
# Perform actions needed to have the game in state 'waiting_for_players'
# INPUT1: old state 
# OUTPUT: (boolean) 1 if success, 0 if failure
sub _switch_to_waiting_for_players {
	my $old_state = shift(@_);
	if (
		(!$old_state) or
		$old_state eq 'complete' or
		$old_state eq 'in_progress'
	) {
		ares_setup_new_game() or return 0;
	}
	return 1;
}

## _switch_to_waiting_start
# Perform actions needed to have the game in state 'waiting_start'
# INPUT1: old state 
# OUTPUT: (boolean) 1 if success, 0 if failure
sub _switch_to_waiting_start {
	my $old_state = shift(@_);

	if (
		(!$old_state) or
		$old_state eq 'complete' or
		$old_state eq 'in_progress'
	) {
		ares_setup_new_game() or return 0;
	}
	my $prep_time = ares_get_config_field('player_prep_time');
	
	starmade_broadcast("Notice: Game Starting in $prep_time minutes.");
	starmade_broadcast("Please Take this time to upload any ships you need, and spawn them.");
	starmade_countdown($prep_time , "Game starting in:");
	return 1;
}

## _switch_to_in_progress
# Perform actions needed to have the game in state 'in_progress'
# INPUT1: old state 
# OUTPUT: (boolean) 1 if success, 0 if failure
sub _switch_to_in_progress {
	my %player_list = %{starmade_player_list()};
	my $old_state = shift(@_);
	my @factions = @{ares_get_player_factions()};
	foreach my $faction (@factions) {
		my $home = ares_get_faction_home($faction);

		fix_players_factions(\%player_list);

		stdout_log("Removing noexit from sector '$home'.", 6);
		if (!starmade_sector_chmod($home, "remove", "noexit")) {
			starmade_broadcast("Error removing noexit on $home.\n");
			starmade_broadcast("Failed to start game. Please inform an admin!\n");
			print starmade_last_output();
			stdout_log("Failed to remove noexit from sector '$home'.", 2);
			stdout_log("Could not start game. Will try again next loop", 2);
			return;
		}
		
		stdout_log("Setting '$home' to unprotected.", 6);
		if (!starmade_sector_chmod($home, "remove", "protected")) {
			starmade_broadcast("Error removing protection on $home.\n");
			starmade_broadcast("Failed to start game. Please inform an admin!\n");
			print starmade_last_output();
			stdout_log("Failed to set sector '$home' as unprotected.", 2);
			stdout_log("Could not start game. Will try again next loop", 2);
			return;
		}
	}
	stdout_log("Game has started", 5);
	starmade_broadcast("Notice: Game Has Started.");
	starmade_broadcast("You are now free to attack your opponents.");
	return 1;
}

## _switch_to_complete
# Perform actions needed to have the game in state 'complete'
# INPUT1: old state 
# OUTPUT: (boolean) 1 if success, 0 if failure
sub _switch_to_complete {
	my $old_state = shift(@_);

	starmade_broadcast("Game is Complete. A new game will start in 60 seconds.\nYou may vote for the next map with the !ares_vote command.", 30);
	starmade_countdown(60 , "Reset in:");
	return 1;
}

sub _setup_db {
	if (ares_get_config_field('use_mysql') && !$DATABASE_HANDLE) {
		my $database = ares_get_config_field('database');
		my $host = ares_get_config_field('db_host');
		my $user = ares_get_config_field('db_user');
		my $passwd = ares_get_config_field('db_passwd');

		if (!$database) {
			warn "Database to connect to not specified but 'use_mysql' is set in ares.cfg!\n";
			warn "'database' must be set in ares.cfg if 'use_mysql' or database connection won't work!\n";
			return;
		}
		if (!$host) {
			$host = 'localhost';
		}
		if (!$user) {
			warn "User to connect to database not specified but 'use_mysql' is set in ares.cfg!\n";
			warn "'db_user' must be set in ares.cfg if 'use_mysql' or database connection won't work!\n";
			return;
		}
		if (!$passwd) {
			warn "Password to connect with database not specified but 'use_mysql' is set in ares.cfg!\n";
			warn "'db_passwd' must be set in ares.cfg if 'use_mysql' or database connection won't work!\n";
			return;
		}

		require DBI;
		$DATABASE_HANDLE = DBI->connect("DBI:mysql:database=$database;host=$host",
			$user, $passwd,
			{'RaiseError' => 1}
		);
	}
}

## _update_database_game_state
# Update the database with the current game state (if configured)
# INPUT1: state
sub _update_database_game_state {
	my $state = shift(@_);

	if (!$state) {
		cluck();
		return;
	}

	if (!$DATABASE_HANDLE) {
		return;
	}
	my $sth = $DATABASE_HANDLE->prepare("INSERT IGNORE INTO state (name, value) VALUES( ?, ? );");
	eval($sth->execute('game_state', $state));
}

## time_in_state
# Give the amount of time we've spent in the current game state.
# OUTPUT: time (in seconds) we'vebeen in the current state
sub time_in_state {
	my @stat = stat("$ares_core::ares_state/Status");
	my $game_start = $stat[9];
	
	return time() - $game_start;
}

## ares_get_game_mode
# Get the game mode of the current map
# OUTPUT: Game mode
sub ares_get_game_mode {
	my %map = %{ares_get_map_config()};

	if ($map{General} and $map{General}{game_mode}) {
		return $map{General}{game_mode};
	}
	return 'Conquest';
}

## ares_get_team_num
# Get the numer of teams in the game
# OUTPUT: Game mode
sub ares_get_team_num {
	my %map = %{ares_get_map_config()};
	my $game_mode = ares_get_game_mode();
	if ($game_mode eq 'Survival') {
		return 0;
	}

	if ($map{General} and $map{General}{teams}) {
		return $map{General}{teams};
	}
	return 2;
}

## ares_void_spawn
# 
sub ares_void_spawn {
	my %player_list = %{shift(@_)};

	my %sectors = ();
	Player: foreach my $player (keys %player_list) {
		if (starmade_is_admin($player)) {
			next Player;
		}
		if ($player_list{$player}{sector}) {
			$sectors{$player_list{$player}{sector}} = 1;
		}
	}
	foreach my $sector (keys %sectors) {
		starmade_sector_chmod($sector, 'add', 'noexit');
	}
	starmade_broadcast("The Void has opened! Enemies emerge from the void! Sectors locked!");
	my %waves = %{stard_read_config('./waves.cfg')};

	my $wave_num = ares_get_wave_number();

	my $wave_to_use = int($wave_num + rand(3) - 1);
	while (!$waves{$wave_to_use} && $wave_to_use < 40) {
		$wave_to_use++;
	}
	foreach my $key (sort(keys %waves)) {
		print "[$key]\n";
		foreach my $key2 (keys%{$waves{$key}}) {
			print "$key2 = $waves{$key}{$key2}\n";
		}
	}
	print "selected wave: $wave_to_use\n";
	foreach my $player (keys %player_list) {
		my @mobs = split(',', $waves{$wave_to_use}{mobs});
		my @pos = ();
		if ($player_list{$player}{sector}) {
			starmade_spawn_mobs_bulk(\@mobs, \@pos, -1, $player_list{$player}{sector}, 1);
		}
		else {
			print "Error player $player has no sector!\n";
		}
	}


	starmade_countdown(30, "Void closes. (You can leave the sector again)");
	sleep 30;
	foreach my $sector (keys %sectors) {
		starmade_sector_chmod($sector, 'remove', 'noexit');
	}
	starmade_broadcast("The Void has closed! (You are free to move about again)");
	ares_set_wave_number($wave_num + .25);
	return 1;
}

sub ares_set_wave_number {
	my $wave_num = shift(@_);

	my $wave_fh;
	if (!open($wave_fh, ">", "$ares_core::ares_state/Wave")) {
		stdout_log("Failed to open '$ares_core::ares_state/Wave': $!\n", 0);
		return 0;
	}
	flock($wave_fh, 2);
	print $wave_fh $wave_num;
	close($wave_fh);
}

sub ares_get_wave_number {
	my $wave_num;

	my $wave_fh;
	if (!open($wave_fh, "<", "$ares_core::ares_state/Wave")) {
		stdout_log("Failed to open '$ares_core::ares_state/Wave': $!\n", 0);
		return 0;
	}
	flock($wave_fh, 2);
	$wave_num = join("\n", <$wave_fh>);
	close($wave_fh);
	return $wave_num
}

1;
