package ares_object;
use lib("./lib");
use ares_core;
use ares_faction;

use lib("../../lib");
use stard_lib;
use stard_log;


our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_object_to_entity ares_set_object_entity ares_write_object_status ares_read_object_status ares_object_status_to_string ares_place_object ares_spawn_mobs ares_spawn_defenders);



## ares_object_to_entity
# Convert map object to starmade entity name
# INPUT: object name
# OUTPUT: entity name
sub ares_object_to_entity {
	my $object = $_[0];
	open(my $obj_fh, "<", "$ares_core::ares_state_objects/$object.entity");
	my $entity = join('', <$obj_fh>);
	close($obj_fh);
	return $entity;
}

## ares_set_object_entity
# Associate the object file with a starmade entity
# INPUT1: object to assiciate with starmade entity
# INPUT2: starmade entity name
sub ares_set_object_entity {
	my $object = $_[0];
	my $entity = $_[1];

	stdout_log("Associating object '$object' with entity '$entity'", 5);
	open(my $obj_fh, ">", "$ares_core::ares_state_objects/$object.entity") or
		stdout_log("Failed: writing to file '$ares_core::ares_state_objects/$object.entity': $!", 3);
	print $obj_fh $entity;
	close($obj_fh);
}

## ares_write_object_status
# change the status of a map object
# INPUT1: map object
# INPUT2: state to set object to (this should be a faction id for it's ownership)
sub ares_write_object_status {
	my $object = $_[0];
	my $state = $_[1];

	stdout_log("Setting state of '$object' to $state", 5);
	open(my $station_fh, ">", "$ares_core::ares_state_objects/$object") or
		stdout_log("Failed: writing to file '$ares_core::ares_state_objects/$object': $!", 3);
	print $station_fh $state;
	close($station_fh);
}

## ares_read_object_status
# Get the current status of an object
# INPUT1: map object name
# OUTPUT: object status (this should be a faction id for it's ownership)
sub ares_read_object_status {
	my $object = $_[0];
	open(my $station_fh, "<", "$ares_core::ares_state_objects/$object");
	my $state = join('',<$station_fh>);
	close($station_fh);
	return $state;
}

## ares_object_status_to_string
# Get an object status and convert it to something more human readable :)
# INPUT1: status
# INPUT2: faction to determine relationship
sub ares_object_status_to_string {
	my $status = $_[0];
	my $faction = $_[1];
	
	if ($status > 0) {
		if ($faction) {
			if ($status == $faction) {
				return "(You)";
			}
			else {
				return  "(Enemy)";
			}
		}
		else {
			return ares_get_faction_name($status);
		}
	}
	elsif ( $status == -1) {
		return "Pirates(Enemy)";
	}
	else {
		return "Unowned";
	};
}

## ares_place_object
# Spawns an object in the given sector.
# INPUT1: object name
# INPUT1: Object Hash
# OUTPUT: 1 if success 0 if failure
sub ares_place_object {
	my $name = $_[0];
	my %object = %{$_[1]};

	stdout_log("Creating: $name", 6);
	my $sector = $object{sector};
	my $blueprint = $object{blueprint};
	my $type = $object{type};
	my $owner = $object{owner};
	my $entity = "$name\_" . time();
	
	my %sector_info = %{stard_sector_info($sector)};
	my %entities = %{$sector_info{entity}};

	# Remove Stations in the sector
	stard_cmd("/load_sector_range $sector $sector");
	foreach my $entity (keys %entities) {
		if ($entity =~s/ENTITY_SPACESTATION_//) {
			if (!stard_despawn_sector($entity, "all", "0", $sector)) {
				stard_boardcast("Error Despawning Sector $sector.\n");
				print stard_last_output();
				stdout_log("Error Despawning Sector $sector... Aborting game start", 1);
				return 0;
			}
		}
	}

	stdout_log("Setting owner of '$name' to $owner", 5);

	# Objectives must be owned by an npc faction as otherwise they can 
	# become home bases, and that would break the game
	if ($object{objective}) {
		my $pos = '0 0 0';
		my $npc = ares_get_faction_npc($owner);
		stdout_log("Spawning '$name' in sector '$sector' with owner '$npc'", 6);
		if (!stard_spawn_entity_pos($blueprint, $entity, $sector, $pos, $npc, 0)) {
			stard_broadcast("Error Spawning $name at $sector.\n");
			print stard_last_output();
			stdout_log("Error Spawning $name at $sector... Aborting game start", 1);
			return 0;
		}
	}
	else {
		my $pos = '0 0 0';
		stdout_log("Spawning '$name' in sector '$sector' with owner '$owner'", 6);
		if (!stard_spawn_entity_pos($blueprint, $entity, $sector, $pos, $owner, 0)) {
			stard_broadcast("Error Spawning $name at $sector.\n");
			print stard_last_output();
			stdout_log("Error Spawning $name at $sector... Aborting game start", 1);
			return 0;
		}
	}
	ares_set_object_entity($name, $entity);
	return 1;
}

## ares_spawn_mobs
# Spawn a group of entities, or die
# INPUT1: List of blueprints
# INPUT2: List of positions to spawn them at
# INPUT3: Faction to spawn them as
# INPUT4: Sector to spawn them in
# INPUT5: enable ai (true or false)
sub ares_spawn_mobs {
	my @ships = @{$_[0]};
	my @ship_pos = @{$_[1]};
	my $faction = $_[2];
	my $sector = $_[3];
	my $ai = $_[4];

	my $i;
	for ($i = 0; $i <= $#ships; $i++) {
		my $ship = $ships[$i];

		my $name = "$ship-$sector" . time() . "_$i";
		if (@ship_pos) {
			my $pos = $ship_pos[$i];
			if (!stard_spawn_entity_pos($ship, $name, $sector, $pos, $faction, 'true')) {
				print stard_last_output();
				stdout_log("Error spawning ship '$ship' with '$name'...", 1);
			};
		}
		else {
			if (!stard_spawn_entity($ship, $name, $sector, $faction, 'true')) {
				print stard_last_output();
				stdout_log("Error spawning ship '$ship' with '$name'...", 1);
			};
		};
	};
}

## ares_spawn_defenders
# Spawns the given defenders for an object
# INPUT1: Object hash
# INPUT2: array of blueprints to spawn defenders as
# INPUT3: Positions to spawn mobs (relative to the input2)
sub ares_spawn_defenders {
	my %object = %{$_[0]};
	my @defenders = @{$_[1]};
	my @pos = @{$_[2]};

	my $sector = $object{sector};
	my $npc = ares_get_faction_npc($object{owner});

	
	my $defender_faction = $object{owner};
	if ($object{owner} == -2) {
		$defender_faction = -1;
	}
	if ($npc) {
		$defender_faction=$npc;
	}
	ares_spawn_mobs(\@defenders, \@pos, $defender_faction, $sector, 1);
}


1;
