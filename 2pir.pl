#!/usr/bin/perl -w

# This script requires the libdevice-serialport-perl package.

use strict;
use Device::SerialPort;
use Time::HiRes qw (time usleep);
use Getopt::Long;
use Data::Dumper;

my $verbose;
GetOptions(
    'v|verbose' => \$verbose,
);

my $if = new Device::SerialPort('/dev/ttyUSB0', 0) or die "Cannot open /dev/ttyUSB0: $!";

if( $verbose ) {
    $if->debug(1);
}
$if->baudrate(19200);
$if->parity("odd");
$if->databits(8);
$if->stopbits(2);
$if->handshake('none');

die "$!" unless $if->write_settings;

# sensor reading blocky things.
my @sensors = (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,1);

my %sensor_addresses = (
			1 => 0,
			2 => 1,
			3 => 2,
			4 => 3,
			5 => 4,
			6 => 5,
			7 => 6,
			8 => 7,
			9 => 8,
			10 => 9,
			11 => 10,
			12 => 11,
			13 => 12,
			14 => 13,
			15 => 14,
			16 => 15,
);

my %sensor_groups = (
		     1 => [1,17,18],
		     2 => [2,19,20],
		     3 => [3,21,22],
		     4 => [4,23,24],
		     5 => [5,25,26],
		     6 => [6,27,28],
		     7 => [7,29,30],
		     8 => [8,31,32],
		     9 => [9,41,42],
		     10 => [10,35,36],
		     11 => [11,37,38],
		     12 => [12,39,40],
		     13 => [13,33,34],
		     14 => [14,43,44],
		     15 => [15,45,46],
		     16 => [16,47,48],
		     );

# invert the sensor_groups hash for quick lookups.
my %sensor_group_map = map { 
    my $group = $_;
    map { ($_ => $group); } @{$sensor_groups{$group}};
} sort keys %sensor_groups;

my %effect_addresses = (
		     1 => [32,33,34,35],
		     2 => [36,37,38,39],
		     3 => [40,41,42,43],
		     4 => [44,45,46,47],
		     5 => [48,49,50,51],
		     6 => [52,53,54,55],
		     7 => [56,57,58,59],
                     16 => [60,61,62,63],
		     9 => [64,65,66,67],
		     10 => [68,69,70,71],
		     11 => [72,73,74,75],
		     12 => [76,77,78,79],
		     13 => [80,81,82,83],
		     14 => [84,85,86,87],
		     15 => [88,89,90,91],
		     8 => [92,93,94,95],
		     );

# for storing the current state of each effect.
my %effect_state;

# for storing the last fire time for each effect.
my %last_fired;

# store the sensor's current value.
my %sensor_current;

# how high to fire?
my $high_threshold = 80;
my $low_threshold = 200;  #for now, this is so high that the low effect never happens.
my $min_firing_time = .200;  #100ms

my $i = 0;

# turn everything off.
foreach my $effect (keys %effect_addresses) {
  print "2pir: turning off $effect on startup\n";
  burninate_motherfuckers($effect, 'off');
}

my $last_time = time();
my %timed;
my $exit = 0;
my @to_write;
my $last_batch = 'b';
while(!$exit) {
    my @read_sensors = @sensors;

    $i++;
    
    # translate sensor ids into sensor addresses.
    my @write_sensors = map { $sensor_addresses{$_} } @read_sensors;
    
    # write whatever needs it between read cycles
    if(@to_write) {
	if( $verbose ) {
            print "********** write: " . join(',', @to_write) . "\n";
        }
	$if->write(pack('C*', @to_write));
	$if->read(255);
	undef @to_write;
    }
    
    # send the reads.
    $if->write(pack('C*', @write_sensors));
    
    #remove that last discarded value.
    pop @read_sensors;
    
    my $first = 1;

    while(@read_sensors) {
	my ($count, $raw_read) = $if->read(255);
	
	unless ($count) {
            next;
        }
	
	foreach my $read ($raw_read) {
	    foreach my $value (unpack('C*', $read)) {
		my $curr;
		if($first) {
		    undef $first;
		    next;
		}
		
		$curr = shift(@read_sensors);

		push @{$timed{$curr}}, { val => $value, time => time() };
		
		# trim @timed
		if(scalar(@{$timed{$curr}}) > 35) {
		    shift(@{$timed{$curr}});
		} else {
		    next;
		}

		# if the value is high enough for low effect, we can assume it's correct.
		if($value >= $high_threshold) {
		    # high effect start firing
		    if( $verbose ) {
                        print "high start $curr, val $value, tdif " . (time() - $_->{time}) . "\n";
		        print "values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) . "\n";
                    }
		    burninate_motherfuckers($curr, 'high');
		    next;
		}
				
		# if the value is high enough for low effect, we can assume it's correct.
		if($value >= $low_threshold + 8) {
		    # low effect start firing (hysteresis)
		    if( $verbose ) {
                        print "low start $curr, val $value, tdif " . (time() - $_->{time}) . "\n";
		        print "values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) . "\n";
                    }
		    burninate_motherfuckers($curr, 'low');
		    next;
		}
		
		# effect was already on
		if(($value >= $low_threshold) && $effect_state{$curr} == 'low') {
		    # low effect continue firing
                    if( $verbose ) {
		        print "low cont  $curr, val $value, tdif " . (time() - $_->{time}) . "\n";
		        print "values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) . "\n";
                    } 
		    burninate_motherfuckers($curr, 'low');
		    next;
		}
		
		burninate_motherfuckers($curr, 'off');
                if( $verbose ) {
                    #print "off       $curr, val $_->{val}, tdif " . (time() - $_->{time}) . ", bl $baseline{$curr}, time $time_baseline{$curr}\n";
                    print "values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) . "\n";
                }
	    }
	}
    }
}

sub burninate_motherfuckers {
    my($effect, $state) = @_;
    
    # effect array offsets:
    # 0 - high off
    # 1 - high on
    # 2 - low off
    # 3 - low on

    $effect_state{$effect} ||= 'off';

    if($effect_state{$effect} eq 'off') {
	if($state eq 'low') {
	    push @to_write, $effect_addresses{$effect}->[3];
	    $last_fired{$effect} = time();
	} elsif($state eq 'high') {
	    push @to_write, $effect_addresses{$effect}->[1];
	    $last_fired{$effect} = time();
	} elsif($state eq 'off' && $i%100 == 0) {
	    # this clause makes sure to turn stuff off if it should be.
	    push @to_write, $effect_addresses{$effect}->[2];
	    push @to_write, $effect_addresses{$effect}->[0];
	    push @to_write, $effect_addresses{$effect}->[0];
	    push @to_write, $effect_addresses{$effect}->[2];
	}
    } elsif($effect_state{$effect} eq 'low') {
	# low effect is on.
	if($state eq 'low') {
	    # do nothing.
	} elsif($state eq 'high') {
	    push @to_write, $effect_addresses{$effect}->[2];
	    push @to_write, $effect_addresses{$effect}->[1];
	    $last_fired{$effect} = time();
	} elsif(($last_fired{$effect} + $min_firing_time) <= time()) {
	    # don't shut off unless the effect was fired more than 40ms ago.
	    print "off from low\n";
	    push @to_write, $effect_addresses{$effect}->[2];
	    push @to_write, $effect_addresses{$effect}->[0];
	    push @to_write, $effect_addresses{$effect}->[0];
	    push @to_write, $effect_addresses{$effect}->[2];
	} else {
	    return;
        }
    } elsif($effect_state{$effect} eq 'high') {
	# high effect is on.
	if($state eq 'low') {
	    push @to_write, $effect_addresses{$effect}->[0];
	    push @to_write, $effect_addresses{$effect}->[3];
	    $last_fired{$effect} = time();
	} elsif($state eq 'high') {
	    # do nothing.
	} elsif(($last_fired{$effect} + $min_firing_time) <= time()) {
	    #print "off from high\n";
	    push @to_write, $effect_addresses{$effect}->[0];
	    push @to_write, $effect_addresses{$effect}->[2];
	    push @to_write, $effect_addresses{$effect}->[0];
	    push @to_write, $effect_addresses{$effect}->[2];
	} else {
	    return;
        }
    }
    if( $verbose ) {
        print "fire: $effect, $state\n";
    }
    $effect_state{$effect} = $state;
}

sub DESTROY {
  warn "Attempting to turn off fire before exiting...\n";
  foreach my $effect (keys %effect_addresses) {
    burninate_motherfuckers($effect, 'off');
  }
}
