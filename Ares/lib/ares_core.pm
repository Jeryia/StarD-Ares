package ares_core;

use strict;
use warnings;

use Carp qw(cluck);

use lib("../../lib/perl");
use Starmade::Base;
use Stard::Base;
use Stard::Log;

## global settings (should only be set once, and never changed again)
our $ares_home;
our $ares_state;
our $ares_data;
our $ares_state_faction;
our $ares_state_player;
our $ares_state_objects;
our $ares_maps;
our %ares_config;

my %blank_hash = ();


our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_setup_run_env ares_get_config_field);


## ares_setup_run_env
# Give the ares lib the current location of the ares plugin. With this the library is configured to function.
# INPUT1: location of ares plugin
sub ares_setup_run_env {
	$ares_home = $_[0];

	if (!(
		-d $ares_home ||
		-d "$ares_home/ares.cfg"
	)) {
		cluck("ares_setup_run_env: invalid ares home dir given: '$ares_home'");
		return 0;
	}

	my $stard_home = "$ares_home/../..";
	$ares_state = "$ares_home/State";
	$ares_state_faction = "$ares_state/Factions";
	$ares_state_player = "$ares_state/Players";
	$ares_state_objects = "$ares_state/Objects";
	$ares_data = "$ares_home/data";
	$ares_maps = "$ares_home/Maps";

	starmade_setup_lib_env($stard_home);
	stdout_log("Setting up Run environment with '$ares_home' as ares_home", 6);

	%ares_config = %{stard_read_config("$ares_home/ares.cfg")};

	# set default config settings (if not already set)
	$ares_config{General}{autostart} //= 1;
	$ares_config{General}{team_number} //= 2;
	$ares_config{General}{credit_multiplier} //= 8000;
	$ares_config{General}{player_prep_time} //= 3;
	$ares_config{General}{starting_credits} //= 5000000;
	$ares_config{General}{credit_scaling} //= 0.05;
	$ares_config{General}{loglevel} //= 6;

	set_loglevel($ares_config{General}{loglevel});
}

## ares_get_config_field
# Get a option from the ares config
# INPUT1: field
# OUTPUT: value of field
sub ares_get_config_field {
	my $field = $_[0];
	return $ares_core::ares_config{General}{$field};
}

1;
