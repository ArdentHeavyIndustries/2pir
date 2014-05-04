#!/usr/bin/perl -w

use strict;
use Device::SerialPort;
use Time::HiRes qw (time usleep);
#use FakePort;

my $if0 = new Device::SerialPort('/dev/ttyUSB0', 0);
#my $if0 = new FakePort("./test-io.out");

$if0->baudrate(19200);
$if0->parity("odd");
$if0->databits(8);
$if0->stopbits(2);
$if0->handshake('none');

die "$!" unless $if0->write_settings;

# sensor reading blocky things.
my @sensors1 = (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,1);

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


my %effect_addresses = (
		     1  => [32,33,34,35],
		     2  => [36,37,38,39],
		     3  => [40,41,42,43],
		     4  => [44,45,46,47],
		     5  => [48,49,50,51],
		     6  => [52,53,54,55],
		     7  => [56,57,58,59],
		     16 => [60,61,62,63],
		     9  => [64,65,66,67],
		     10 => [68,69,70,71],
		     11 => [72,73,74,75],
		     12 => [76,77,78,79],
		     13 => [80,81,82,83],
		     14 => [84,85,86,87],
		     15 => [88,89,90,91],
		     8  => [92,93,94,95],
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

# turn everything off.
foreach my $effect (keys %effect_addresses) {
  print "2pir: turning off $effect on startup\n";
  fire_the_fucking_flamethrowers_oh_my_god($effect, 'off');
}

my $i = 0;

my $last_time = time();
my %timed;
my $exit = 0;
my @to_write;
my $last_batch = 'b';
while(!$exit) {
    # my @read_sensors0;
    my @read_sensors1 = @sensors1;

    $i++;

    # translate sensor ids into sensor addresses.
    my @write_sensors1 = map { $sensor_addresses{$_} } @read_sensors1;

    # write whatever needs it between read cycles
    if(@to_write) {
	#print "********** write: " . join(',', @to_write) . "\n";
	$if0->write(pack('C*', @to_write));
	$if0->read(255);
	undef @to_write;
    }

    # send the reads.
    $if0->write(pack('C*', @write_sensors1));

    #remove that last discarded value.
    pop @read_sensors1;

    my $first1 = 1;

    while(@read_sensors1) {

	my ($count1, $raw_read1) = $if0->read(255);
	
	next unless ($count1);
	
	# jankity...
	my $pick = 1;
	foreach my $read ($raw_read1) {
	    foreach my $value (unpack('C*', $read)) {
		my $curr;
		if($first1) {
		    undef $first1;
		    next;
		}
		
		$curr = shift(@read_sensors1);

		push @{$timed{$curr}}, { val => $value, time => time() };
#		print "$value\n" if $curr == 8;
		
		# trim @timed
		if(scalar(@{$timed{$curr}}) > 35) {
		    shift(@{$timed{$curr}});
		} else {
		    next;
		}

		# if the value is high enough for low effect, we can assume it's correct.
		if($value >= $high_threshold) {
		    # high effect start firing
		    #print "high start $curr, val $value, tdif " . (time() - $_->{time}) . "\n";
		    #print "values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) . "\n";
		    fire_the_fucking_flamethrowers_oh_my_god($curr, 'high');
                }
				
		# if the value is high enough for low effect, we can assume it's correct.
		elsif($value >= $low_threshold + 8) {
		    # low effect start firing (hysteresis)
		    #print "low start $curr, val $value, tdif " . (time() - $_->{time}) . "\n";
		    #print "values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) . "\n";
		    fire_the_fucking_flamethrowers_oh_my_god($curr, 'low');
		    next;
		}
		
		# effect was already on
		elsif(($value >= $low_threshold) && $effect_state{$curr} == 'low') {
		    # low effect continue firing
		    #print "low cont  $curr, val $value, tdif " . (time() - $_->{time}) . "\n";
		    #print "values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) . "\n";
		    fire_the_fucking_flamethrowers_oh_my_god($curr, 'low');
		    next;
		}
		
                else {
		fire_the_fucking_flamethrowers_oh_my_god($curr, 'off');
#                print "off       $curr, val $_->{val}, tdif " . (time() - $_->{time}) . ", bl $baseline{$curr}, time $time_baseline{$curr}\n";
#                print "values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) . "\n";
              }

	    }
	}
    }
}

sub fire_the_fucking_flamethrowers_oh_my_god {
    my($effect, $state) = @_;

    # effect array offsets:
    # 0 - high off
    # 1 - high on
    # 2 - low off
    # 3 - low on


    if($effect_state{$effect} eq 'off') {
	if($state eq 'low') {
          push @to_write, getEffectAddresses( $effect, 3 );
          $last_fired{$effect} = time();
          #print "fire: $effect, $state\n";
	} elsif($state eq 'high') {
          push @to_write, getEffectAddresses( $effect, 1 );
          $last_fired{$effect} = time();
          #print "fire: $effect, $state\n";
	} elsif($state eq 'off' && $i%100 == 0) {
          # this clause makes sure to turn stuff off if it should be.
          push @to_write, getEffectAddresses( $effect, 2, 0, 0, 2 );
          #print "fire: $effect, $state (anyway)\n";
          # already off.
          #print "off from off\n";
	}
    } elsif($effect_state{$effect} eq 'low') {
	# low effect is on.
	if($state eq 'low') {
          # do nothing.
	} elsif($state eq 'high') {
          push @to_write, getEffectAddresses( $effect, 2, 1 );
          $last_fired{$effect} = time();
          #print "fire: $effect, $state\n";
	} elsif(($last_fired{$effect} + $min_firing_time) <= time()) {
          # don't shut off unless the effect was fired more than 40ms ago.
          #print "off from low\n";
          push @to_write, getEffectAddresses( $effect, 2, 0, 0, 2 );
          #print "fire: $effect, $state\n";
	} else {
	  return;
        }
    } elsif($effect_state{$effect} eq 'high') {
	# high effect is on.
	if($state eq 'low') {
          push @to_write, getEffectAddresses( $effect, 0, 0 );
          $last_fired{$effect} = time();
          print "fire: $effect, $state\n";
	} elsif($state eq 'high') {
	    # do nothing.
	} elsif(($last_fired{$effect} + $min_firing_time) <= time()) {
          #print "off from high\n";
          push @to_write, getEffectAddresses( $effect, 0, 2, 0, 2 );
          #print "fire: $effect, $state\n";
	} else {
	  return;
        }
    }

    $effect_state{$effect} = $state;
}


sub getEffectAddresses {
  my $effect = shift;
  return map {  $effect_addresses{$effect}->[$_] } @_;
}

sub DESTROY {
  warn "Attempting to turn off fire before exiting...\n";
  foreach my $effect (keys %effect_addresses) {
    fire_the_fucking_flamethrowers_oh_my_god($effect, 'off');
  }
}
