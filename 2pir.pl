#!/usr/bin/perl -w

$| = 1;

use strict;
use Getopt::Long;
use Device::SerialPort;
use Time::HiRes qw (time usleep);
use Config::Inifiles;
use FakePort;

my %verbosity = (
    1 => 'ERROR',
    2 => 'INFO',
    3 => 'DEBUG',
);

my %OPTIONS;
my %CONFIG;

GetOptions(\%OPTIONS,
    'fake=s',
    'logfile=s',
    'high_threshold=s',
    'low_threshold=s',
    'min_firing_time=s',
    'fakeport=s',
    'config=s',
);

$OPTIONS{'config'} ||= '2pir.ini';

my $ini = Config::IniFiles->new( -file => "2pir.ini" );

$CONFIG{'high_threshold'}  = $ini->val('2pir','high_threshold');
$CONFIG{'low_threshold'}   = $ini->val('2pir','low_threshold');
$CONFIG{'min_firing_time'} = $ini->val('2pir','min_firing_time');
$CONFIG{'logfile'}         = $ini->val('2pir','logfile');

foreach my $OPTION ( keys %OPTIONS ) {
    if ($CONFIG{$OPTION}) {
        debug("Overriding $OPTION: $CONFIG{$OPTION}");
    }
    $CONFIG{$OPTION} = $OPTIONS{$OPTION};
}

map { info("CONFIG: $_ = $CONFIG{$_}") } ( sort keys %CONFIG );
  
my $if0;
if( $CONFIG{'fake'} ) {
    $if0 = new FakePort("./test-io.out");
} else {
    $if0 = new Device::SerialPort('/dev/ttyUSB0', 0); #Change to /dev/ttyS0 for direct serial
}

unless( $if0 ) {
    error("Could not initiate serial port connection");
    exit(1);
}

$if0->baudrate(19200);
$if0->parity("odd");
$if0->databits(8);
$if0->stopbits(2);
$if0->handshake('none');

unless( $if0->write_settings ) {
    error("Could not write settings: $!");
    exit(1);
}

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

my $i = 0;

# turn everything off.
info("2pir: turning off all effects on startup");
foreach my $effect (keys %effect_addresses) {
  $effect_state{$effect} ||= 'off';
  burninate_motherfuckers_omg($effect, 'off');
}

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
	debug("********** write: " . join(',', @to_write) );
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
	
	foreach my $read ($raw_read1) {
	    foreach my $value (unpack('C*', $read)) {
		my $curr;
		if($first1) {
                    debug("Discarding first value");
		    undef $first1;
		    next;
		}
		
		$curr = shift(@read_sensors1);

		push @{$timed{$curr}}, { val => $value, time => time() };
		
		# trim @timed
		if(scalar(@{$timed{$curr}}) > 35) {
		    shift(@{$timed{$curr}});
		} else {
		    next;
		}

		# if the value is high enough for low effect, we can assume it's correct.
		if($value >= $CONFIG{'high_threshold'}) {
		    # high effect start firing
		    debug("high start $curr, val $value, tdif " . (time() - $_->{time}));
		    debug("values: " . join(', ', map { $_->{val} } @{$timed{$curr}}));
		    burninate_motherfuckers_omg($curr, 'high');
                }
				
		# if the value is high enough for low effect, we can assume it's correct.
		elsif($value >= $CONFIG{'low_threshold'} + 8) {
		    # low effect start firing (hysteresis)

		    debug("low start $curr, val $value, tdif " . (time() - $_->{time}));
		    debug("values: " . join(', ', map { $_->{val} } @{$timed{$curr}}));
		    burninate_motherfuckers_omg($curr, 'low');
		    next;
		}
		
		# effect was already on
		elsif(($value >= $CONFIG{'low_threshold'}) && $effect_state{$curr} == 'low') {
		    # low effect continue firing
		    debug("low cont  $curr, val $value, tdif " . (time() - $_->{time}));
		    debug("values: " . join(', ', map { $_->{val} } @{$timed{$curr}}));
		    burninate_motherfuckers_omg($curr, 'low');
		    next;
		}
		
                else {
		    burninate_motherfuckers_omg($curr, 'off');
                    debug("values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) );
                }
	    }
	}
    }
}

sub burninate_motherfuckers_omg {
    my($effect, $state) = @_;

    # effect array offsets:
    # 0 - high off
    # 1 - high on
    # 2 - low off
    # 3 - low on

    debug(sprintf('Attempting to set Effect %s from %s to %s',$effect,$effect_state{$effect},$state));

    if($effect_state{$effect} eq 'off') {
	if($state eq 'low') {
          push @to_write, getEffectAddresses( $effect, 3 );
          $last_fired{$effect} = time();
          info("Turning on $effect");
	} elsif($state eq 'high') {
          push @to_write, getEffectAddresses( $effect, 1 );
          $last_fired{$effect} = time();
          info("Turning on $effect");
	} elsif($state eq 'off') {
          if($i%100 == 0) {
            # this clause makes sure to turn stuff off if it should be.
            push @to_write, getEffectAddresses( $effect, 2, 0, 0, 2 );
            info("Turning off $effect");
	  } else {
            info("$effect is already off");
          }
        }
    } elsif($effect_state{$effect} eq 'low') {
	# low effect is on.
	if($state eq 'low') {
          info("$effect is already low");
	} elsif($state eq 'high') {
          push @to_write, getEffectAddresses( $effect, 2, 1 );
          $last_fired{$effect} = time();
          info("Increasing intensity of $effect");
	} elsif(($last_fired{$effect} + $CONFIG{'min_firing_time'}) <= time()) {
          # don't shut off unless the effect was fired more than 40ms ago.
          #print "off from low\n";
          push @to_write, getEffectAddresses( $effect, 2, 0, 0, 2 );
          info("Shutting off $effect");
	} else {
          info("Not enough time has elapsed to shut down $effect, skipping");
	  return;
        }
    } elsif($effect_state{$effect} eq 'high') {
	# high effect is on.
	if($state eq 'low') {
          push @to_write, getEffectAddresses( $effect, 0, 0 );
          $last_fired{$effect} = time();
          info("Decreasing intensity of $effect");
	} elsif($state eq 'high') {
	  info("$effect is already high");
	} elsif(($last_fired{$effect} + $CONFIG{'min_firing_time'}) <= time()) {
          #print "off from high\n";
          push @to_write, getEffectAddresses( $effect, 0, 2, 0, 2 );
          info("Shutting off $effect");
	} else {
          info("Not enough time has elapsed to shut down $effect, skipping");
          return;
        }
    }

    $effect_state{$effect} = $state;
}

sub error {
    my $line = shift;
    logit($line,1)
}

sub info {
    my $line = shift;
    logit($line,2);
}

sub debug {
    my $line = shift;
    logit($line,3);
}

sub logit {
    my $line  = shift;
    my $level = shift;

    my ($sec,$min,$hour,$day,$mon,$year,undef,undef,undef)=localtime(time);
    my $timestamp = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$day,$hour,$min,$sec);
    my $message = sprintf("[%s] %s: %s\n", $timestamp, $verbosity{$level}, $line);

    if( $CONFIG{'logfile'} ) {
        if( $level < 3 ) {
            print $message;
        }

        open(LOG, ">>$CONFIG{'logfile'}") or die "Could not open $CONFIG{'logfile'}: $!";
        printf LOG $message;
        close(LOG);
    } else {
        print $message;
    }    
}

sub getEffectAddresses {
  my $effect = shift;
  return map {  $effect_addresses{$effect}->[$_] } @_;
}

sub DESTROY {
  info("Turning off all effects on shutdown");
  foreach my $effect (keys %effect_addresses) {
    burninate_motherfuckers_omg($effect, 'off');
  }
}

