package ares_core;

use lib("../../lib");
use stard_lib;
use stard_log;

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
	my $stard_home = "$ares_home/../..";
	$ares_state = "$ares_home/State";
	$ares_state_faction = "$ares_state/Factions";
	$ares_state_player = "$ares_state/Players";
	$ares_state_objects = "$ares_state/Objects";
	$ares_data = "$ares_home/data";
	$ares_maps = "$ares_home/Maps";

	stard_setup_run_env($stard_home);
	stdout_log("Setting up Run environment with '$ares_home' as ares_home", 6);

	%ares_config = %{stard_read_config("$ares_home/ares.cfg")};
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
