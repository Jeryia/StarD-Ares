package ares_map;
use File::Copy;

use lib("./lib");
use ares_core;
use ares_player;


use lib("../../lib");
use stard_lib;
use stard_log;


our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_get_map_config ares_get_raw_map_config ares_ck_map_config ares_get_cur_map ares_set_cur_map ares_get_map_list);



## ares_get_map_config
# Get the current ares map config, and set it's relavant variables to the actual in game ones
# OUTPUT: 2d hash of the map config
sub ares_get_map_config {
	my %ares_map_config = %{ares_get_raw_map_config("$ares_core::ares_state/cur.map")};

	foreach my $entity (keys %ares_map_config) {
		$ares_map_config{$entity}{sector} = stard_location_add($ares_core::ares_config{General}{map_center}, $ares_map_config{$entity}{sector});
		
		$ares_map_config{$entity}{owner} = ares_team_to_faction($ares_map_config{$entity}{owner});
	};
	return \%ares_map_config;
}

## ares_get_raw_map_config
# Get the ares map config, and set it's relavant variables to the actual in game ones
# INPUT1: Name of the map to load
# OUTPUT: 2d hash of the map config
sub ares_get_raw_map_config {
	my $map = $_[0];

	my %ares_map_config = %{stard_read_config($map)};
	if (ares_ck_map_config(\%ares_map_config)) {
		return \%ares_map_config;
	};
	return \%blank_hash;

	if(open(my $map_fh, "<", $map)) {
		my @lines = <$map_fh>;
		my $object = "";
		my $line_num =0;
		foreach my $line (@lines) {
			$line_num++;
			if ($line=~/^#/ || !($line=~/\S/)) {
			}
			elsif ($line=~/^\[(.*)\]/) {
				$object = $1;
			}
			elsif (
				$line=~/^\s*(\S+)\s*=\s*"(.*)"/ ||
				$line=~/^\s*(\S+)\s*=\s*'(.*)'/ ||
				$line=~/^\s*(\S+)\s*=\s*(.*)/

			) {
				$ares_map_config{$object}{$1} = $2;
			}
			else {
				print "Line $line_num not understood\n";
				return \%blank_hash;
			};
		};
		if (ares_ck_map_config(\%ares_map_config)) {
			return \%ares_map_config;
		};
	};
	return \%blank_hash;
}

## ares_ck_map_config
# check the map configuration to see if it looks valid.
# INPUT1: hash pointer to the config hash of the map file
# OUTPUT: 1 if looks ok, 0 if not
sub ares_ck_map_config {
	my %map_config = %{$_[0]};

	my %home = ();
		

	Object: foreach my $object (keys %map_config) {
		if ($object eq "General") {
			next Object;
		}
		if (!($map_config{$object}{sector})) {
			stard_broadcast("Requested Map missing sector for '$object'");
			stdout_log("Error loading map: Requested Map missing sector for '$object'", 3);
			return 0;
		}
		else {
			if (!($map_config{$object}{sector}=~/^-?\d+ -?\d+ -?\d+/)) {
				stard_broadcast("Error malformed sector '$map_config{$object}{sector}' for '$object'");
				stdout_log("Error loading map: Error malformed sector '$map_config{$object}{sector}' for '$object'", 3);
				return 0;
			}
		}
		if ( defined $map_config{$object}{owner} ) {
			if (!($map_config{$object}{owner} =~/^-?\d+$/)) {
				stard_broadcast("Error malformed owner '$map_config{$object}{owner}' for '$object'");
				stdout_log("Error loading map: Error malformed owner '$map_config{$object}{owner}' for '$object'", 3);
				return 0;
			}
		}
		else {
			stard_broadcast("Requested Map missing owner for '$object'");
			stdout_log("Error loading map: Requested Map missing owner for '$object'", 3);
			return 0;
		}
		if ($map_config{$object}{home}) {
			$home{$map_config{$object}{owner}} = 1;
		}
	}

	my @players = keys %home;
	if (@players < 2) {
		stard_broadcast("Requested has less than 2 home bases!");
		stdout_log("Error loading map: Requested has less than 2 home bases", 3);
		return 0;
	}
	return 1;
}

## ares_get_cur_map
# Get the current running map
# OUTPUT: name of the map currently being played (if available)
sub ares_get_cur_map {
	open(my $map_fh, "<", "$ares_core::ares_state/map") or return;
	my $map = join("",<$map_fh>);
	close($map_fh);
	return $map;
}

## ares_set_cur_map
# Set the current map. 
# INPUT1: Name of map
sub ares_set_cur_map {
	my $map = $_[0];

	stdout_log("Setting current map to '$map'", 6);
	open(my $map_fh, ">", "$ares_core::ares_state/map") or
		stdout_log("Failed: writing to file '$ares_core::ares_state/map': $!", 3);
	print $map_fh $map;
	close($map_fh);
	if(!copy("$ares_core::ares_maps/$map.map", "$ares_core::ares_state/cur.map")) {
		warn "Failed to copy '$ares_core::ares_maps/$map.map' to '$ares_core::ares_state/cur.map'\n";
		stdout_log("Failed: copying file '$ares_core::ares_maps/$map.map' to '$ares_core::ares_state/cur.map': $!", 3);
		return 0;
	}
	return 1;
}


## ares_get_map_list
# Get a list of the available maps
# OUTPUT: array of map names
sub ares_get_map_list {
	my @maps;
	if (opendir(my $map_dh, "$ares_core::ares_maps")) {
		my @tmp = readdir($map_dh);
		foreach my $file (@tmp) {
			if ($file=~/\.map$/) {
				$file=~s/.map$//;
				push(@maps, $file);
			}
		}
	}
	return \@maps;
}


1;
