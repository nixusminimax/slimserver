# Rescan.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
# Timer functions added by Kevin Deane-Freeman (kevindf@shaw.ca) June 2004
# $Id$

# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::Rescan;

use strict;
use Slim::Control::Command;
use Time::HiRes;

our $interval = 1; # check every x seconds
our @browseMenuChoices;
our %menuSelection;
our %searchCursor;
our %functions;

sub getDisplayName {
	return 'PLUGIN_RESCAN_MUSIC_LIBRARY';
}

sub initPlugin {

	%functions = (
		'up' => sub  {
			my $client = shift;
			my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMenuChoices + 1), $menuSelection{$client});

			$menuSelection{$client} =$newposition;
			$client->update();
		},

		'down' => sub  {
			my $client = shift;
			my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMenuChoices + 1), $menuSelection{$client});

			$menuSelection{$client} =$newposition;
			$client->update();
		},

		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},

		'right' => sub  {
			my $client = shift;
			my @oldlines = Slim::Display::Display::curLines($client);

			if ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_RESCAN_TIMER_SET')) {
				
				my %params = (
					'header' => $client->string('PLUGIN_RESCAN_TIMER_SET'),
					'valueRef' => Slim::Utils::Prefs::get("rescan-time"),
					'cursorPos' => 1,
					'callback' => \&settingsExitHandler
				);
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);

			} elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_RESCAN_TIMER_OFF')) {

				Slim::Utils::Prefs::set("rescan-scheduled", 1);
				$browseMenuChoices[$menuSelection{$client}] = $client->string('PLUGIN_RESCAN_TIMER_ON');
				$client->showBriefly($client->string('PLUGIN_RESCAN_TIMER_TURNING_ON'),'');
				setTimer($client);

			} elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_RESCAN_TIMER_ON')) {

				Slim::Utils::Prefs::set("rescan-scheduled", 0);
				$browseMenuChoices[$menuSelection{$client}] = $client->string('PLUGIN_RESCAN_TIMER_OFF');
				$client->showBriefly($client->string('PLUGIN_RESCAN_TIMER_TURNING_OFF'),'');
				setTimer($client);
			}
		},

		'play' => sub {
			my $client = shift;

			if ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_RESCAN_PRESS_PLAY')) {

				my @pargs=('rescan');
				my ($line1, $line2) = ($client->string('PLUGIN_RESCAN_MUSIC_LIBRARY'), $client->string('PLUGIN_RESCAN_RESCANNING'));
				Slim::Control::Command::execute($client, \@pargs, undef, undef);
				$client->showBriefly( $line1, $line2);

			} else {

				$client->bumpRight();
			}
		}
	);

	Slim::Buttons::Common::addMode('scantimer', getFunctions(), \&Plugins::Rescan::setMode);
	setTimer();
}

sub setMode {
	my $client = shift;

	@browseMenuChoices = (
		$client->string('PLUGIN_RESCAN_TIMER_SET'),
		$client->string('PLUGIN_RESCAN_TIMER_OFF'),
		$client->string('PLUGIN_RESCAN_PRESS_PLAY'),
	);

	unless (defined($menuSelection{$client})) {
		$menuSelection{$client} = 0;
	}

	$client->lines(\&lines);

	# get previous alarm time or set a default
	unless (defined Slim::Utils::Prefs::get("rescan-time")) {

		Slim::Utils::Prefs::set("rescan-time", 9 * 60 * 60 );
	}
}

sub lines {
	my $client = shift;

	my $timeFormat = Slim::Utils::Prefs::get("timeFormat");

	my $line1 = $client->string('PLUGIN_RESCAN_MUSIC_LIBRARY');

	if (Slim::Utils::Prefs::get("rescan-scheduled") && 
		$browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_RESCAN_TIMER_OFF')) {

		$browseMenuChoices[$menuSelection{$client}] = $client->string('PLUGIN_RESCAN_TIMER_ON');
	}

	my $line2 = $browseMenuChoices[$menuSelection{$client}] || '';

	return ($line1, $line2, undef, Slim::Display::Display::symbol('rightarrow'));
}

sub settingsExitHandler {
	my ($client,$exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Utils::Prefs::set("rescan-time",$client->param('valueRef'));
		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		$client->bumpRight();

	} else {
		return;
	}
}

sub getFunctions() {
	return \%functions;
}

sub setTimer {
	# timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $interval, \&checkScanTimer);
}

sub checkScanTimer {

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	my $time = $hour * 60 * 60 + $min * 60;

	if ($sec == 0) { # once we've reached the beginning of a minute, only check every 60s
		$interval = 60;
	}

	if ($sec >= 50) { # if we end up falling behind, go back to checking each second
		$interval = 1;
	}

	if (Slim::Utils::Prefs::get("rescan-scheduled")) {

		my $scantime =  Slim::Utils::Prefs::get("rescan-time");

		if ($scantime) {

			# alarm is done, so reset to find the beginning of a minute
			if ($time == $scantime + 60) {
				$interval = 1;
			}

			if ($time == $scantime && !Slim::Music::Import::stillScanning()) {
				Slim::Music::Import::startScan();
			}
		}
	}

	setTimer();
}

sub setupGroup {

	my %group = (
		PrefOrder => ['rescan-scheduled','rescan-time'],
		PrefsInTable => 1,
		GroupHead => Slim::Utils::Strings::string('PLUGIN_RESCAN_MUSIC_LIBRARY'),
		GroupDesc => Slim::Utils::Strings::string('PLUGIN_RESCAN_TIMER_DESC'),
		GroupLine => 1,
		GroupSub => 1,
		Suppress_PrefSub => 1,
		Suppress_PrefLine => 1,
		Suppress_PrefHead => 1
	);
	
	my %prefs = (
		'rescan-scheduled' => {
			'validate' => \&Slim::Web::Setup::validateTrueFalse,
			'PrefChoose' => Slim::Utils::Strings::string('PLUGIN_RESCAN_TIMER_NAME'),
			'changeIntro' => Slim::Utils::Strings::string('PLUGIN_RESCAN_TIMER_NAME'),
			'options' => {
				'1' => 'ON',
				'0' => 'OFF',
			},
		},

		'rescan-time' => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll,
			'validateArgs' => [0,undef],
			'PrefChoose' => Slim::Utils::Strings::string('PLUGIN_RESCAN_TIMER_SET'),
			'changeIntro' => Slim::Utils::Strings::string('PLUGIN_RESCAN_TIMER_SET'),

			'currentValue' => sub {
				my $client = shift;
				my $time = Slim::Utils::Prefs::get("rescan-time");
				my ($h0, $h1, $m0, $m1, $p) = Slim::Buttons::Input::Time::timeDigits($client,$time);
				my $timestring = ((defined($p) && $h0 == 0) ? ' ' : $h0) . $h1 . ":" . $m0 . $m1 . " " . (defined($p) ? $p : '');
				return $timestring;
			},

			'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				my $time = $changeref->{'rescan-time'}{'new'};
				my $newtime = 0;
				$time =~ s{
					^(0?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$
				}{
					if (defined $3) {
						$newtime = ($1 == 12?0:$1 * 60 * 60) + ($2 * 60) + ($3 =~ /P/?12 * 60 * 60:0);
					} else {
						$newtime = ($1 * 60 * 60) + ($2 * 60);
					}
				}iegsx;
				Slim::Utils::Prefs::set('rescan-time',$newtime);
			},
		},
	);

	return (\%group,\%prefs);
};

sub strings {
	local $/ = undef;
	my $strings = <DATA>;
	close DATA;
	return $strings;
}

1;

__DATA__

PLUGIN_RESCAN_MUSIC_LIBRARY
	DE	Musikverzeichnis erneut durchsuchen
	EN	Rescan Music Library
	FR	Répertorier musique
	
PLUGIN_RESCAN_RESCANNING
	DE	Server durchsucht Verzeichnisse...
	EN	Server now rescanning...
	FR	En cours...

PLUGIN_RESCAN_PRESS_PLAY
	DE	Drücke Play, um Durchsuchen zu starten
	EN	Press PLAY to rescan now.

PLUGIN_RESCAN_TIMER_NAME
	DE	Automatisches Durchsuchen 
	EN	Rescan Timer

PLUGIN_RESCAN_TIMER_SET
	DE	Startzeit für erneutes Durchsuchen
	EN	Set Rescan Time

PLUGIN_RESCAN_TIMER_TURNING_OFF
	DE	Automatisches Durchsuchen deaktivieren...
	EN	Turning rescan timer off...

PLUGIN_RESCAN_TIMER_TURNING_ON
	DE	Automatisches Durchsuchen aktivieren...
	EN	Turning rescan timer on...

PLUGIN_RESCAN_TIMER_ON
	DE	Automatisches Durchsuchen EIN
	EN	Rescan Timer ON

PLUGIN_RESCAN_TIMER_DESC
	DE	Sie können ihre Musiksammlung automatisch alle 24h durchsuchen lassen. Setzen Sie den Zeitpunkt, und schalten Sie die Automatik ein oder aus.
	EN	You can choose to allow a scheduled rescan of your music library every 24 hours.  Set the time, and set the Rescan Timer to ON to use this feature.

PLUGIN_RESCAN_TIMER_OFF
	DE	Automatisches Durchsuchen AUS
	EN	Rescan Timer OFF

