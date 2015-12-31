package ares_vote;
use strict;
use warnings;

use lib("./lib");
use ares_core;

use lib("../../lib");
use stard_lib;
use stard_log;


our (@ISA, @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ares_votes ares_vote_tally ares_vote_win ares_vote_for);



## ares_votes
# Get a hash of all the votes players have cast
# OUTPUT: Hash of votes in format of %HASH{playerName} = map
sub ares_votes {
	my %votes = ();
	open(my $vote_fh, "<", "$ares_core::ares_state/vote") or return \%votes;
	my @tmp = <$vote_fh>;
	close($vote_fh);

	foreach my $vote (@tmp) {
		my ($player, $map) = split("\t", $vote);
		$votes{$player} = $map;
	}
	return \%votes;
}

## ares_vote_tally
# return hash of the votes for each map
# OUTPUT: Hash of votes in format of %HASH{map} = # of votes
sub ares_vote_tally {
	my %votes = %{ares_votes()};

	my %vote_tally = ();
	foreach my $player (keys %votes) {
		$vote_tally{$votes{$player}}++;
	}
	return \%vote_tally;
}

## ares_vote_win
# Determine the outcome of the vote
# OUTPUT: map name
sub ares_vote_win {
	my $map;
	my %vote_tally = %{ares_vote_tally()};
	my @winners = ();
	Map: foreach my $map (keys %vote_tally) {
		foreach my $map2 (keys %vote_tally) {
			if ($vote_tally{$map} < $vote_tally{$map2}) {
				next $map;
			}
		}
		push(@winners, $map);
	}
	if (@winners) {
		my $winner = int(rand($#winners));
		return $winners[$winner];
	}
	return $ares_core::ares_config{General}{default_map};
}

## ares_vote_for 
# Have a player votefor a specific map to play next round
# INPUT1: player voting
# INPUT2: thing to vote for
sub ares_vote_for {
	my $player = $_[0];
	my $map = $_[1];

	my %votes;

	system("touch '$ares_core::ares_state/vote'");
	open(my $vote_r_fh, "<", "$ares_core::ares_state/vote") or die "Failed to open '$ares_core::ares_state/vote': $!\n";
	flock($vote_r_fh, 2);
	%votes = %{ares_votes()};
	
	open(my $vote_fh, ">", "$ares_core::ares_state/vote") or die "Failed to open '$ares_core::ares_state/vote': $!\n";
	$votes{$player} = $map;

	foreach my $player (keys %votes) {
		print $vote_fh "$player\t$votes{$player}\n";
	}
	close($vote_fh);
	close($vote_r_fh);
};


1;
