#!/usr/bin/perl -w

$| = 1;

use strict;
use Getopt::Long;
use Device::SerialPort;
use Time::HiRes qw (time usleep);
use Config::IniFiles;
use List::Flatten

my %verbosity = (
    0 => 'ERROR',
    1 => 'INFO',
    2 => 'DEBUG',
);

my %OPTIONS;
my %CONFIG;

GetOptions(\%OPTIONS,
    'logfile=s',
    'high_threshold=s',
    'low_threshold=s',
    'min_firing_time=s',
    'port=s',
    'config=s',
    'verbose=i',
);

$OPTIONS{'config'} ||= '/etc/2pir.ini';

#my $ini = Config::IniFiles->new( -file => "$OPTIONS{'config'}" );
my $ini = Config::IniFiles->new( -file => "/etc/2pir.ini" );

$CONFIG{'high_threshold'}  = $ini->val('2pir','high_threshold');
$CONFIG{'low_threshold'}   = $ini->val('2pir','low_threshold');
$CONFIG{'min_firing_time'} = $ini->val('2pir','min_firing_time');
$CONFIG{'logfile'}         = $ini->val('2pir','logfile');
$CONFIG{'port'}            = $ini->val('2pir','port');
$CONFIG{'verbose'}         = $ini->val('2pir','verbose');

# Over-ride options from the ini file w/anything passed in via the CLI
foreach my $OPTION ( keys %OPTIONS ) {
    if ($CONFIG{$OPTION}) {
        debug("Overriding $OPTION: $CONFIG{$OPTION}");
    }
    $CONFIG{$OPTION} = $OPTIONS{$OPTION};
}

# Set default values if necessary
$CONFIG{'high_threshold'}  ||= 80;
$CONFIG{'low_threshold'}   ||= 200;
$CONFIG{'min_firing_time'} ||= 0.2; # 200ms
$CONFIG{'port'} ||= '/dev/ttyUSB0';

map { info("CONFIG: $_ = $CONFIG{$_}") } ( sort keys %CONFIG );

my $if0 = new Device::SerialPort($CONFIG{'port'}, 0); #Change to /dev/ttyS0 for direct serial

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
my @points_to_read = (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16);

# there are 16 points. each has one effect and two sensors that trigger it.
my %point_addresses = (
    1 => [0,1],
    2 => [2,3],
    3 => [4,5],
    4 => [6,7],
    5 => [8,9],
    6 => [10,11],
    7 => [12,13],
    8 => [14,15],
    9 => [16,17],
    10 => [18,19],
    11 => [20,21],
    12 => [22,23],
    13 => [24,25],
    14 => [26,27],
    15 => [29,29],
    16 => [30,31],
);

my %sensor_to_point;

# build a reverse mapping.
foreach my $effect (keys %point_addresses) {
    sensor_to_point{$point_addresses[0]} = $effect;
    sensor_to_point{$point_addresses[1]} = $effect;
}

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
    $i++;

    # translate sensor ids into sensor addresses.
    my @addresses_to_read = flat(map { $point_addresses{$_} } @points_to_read);

    # throw on a bullshit value that will be discarded.
    push(@addresses_to_read, 0);

    # write whatever needs it between read cycles
    if(@to_write) {
	debug("********** write: " . join(',', @to_write) );
	$if0->write(pack('C*', @to_write));
	$if0->read(255);
	undef @to_write;
    }

    # send the reads.
    $if0->write(pack('C*', @addresses_to_read));

    my $first1 = 1;

    while(@addresses_to_read) {

    	my ($count1, $raw_read1) = $if0->read(255);

    	next unless ($count1);

    	foreach my $read ($raw_read1) {
    	    foreach my $value (unpack('C*', $read)) {
        		my $curr, $sensor;

        		if($first1) {
                    debug("Discarding first value");
        		    undef $first1;
        		    next;
        		}

        		$sensor = shift(@addresses_to_read);
                $curr = $sensor_to_point{$sensor};

        		push @{$timed{$curr}}, { val => $value, time => time() };

        		# trim @timed
        		if(scalar(@{$timed{$curr}}) > 35) {
        		    shift(@{$timed{$curr}});
        		} else {
        		    next;
        		}

                # store the current sensor value
                $sensor_current{$sensor} = $value;

        		# if the value is high enough for low effect, we can assume it's correct.
        		if($value >= $CONFIG{'high_threshold'}) {
        		    # high effect start firing
        		    #debug("high start $curr, val $value, tdif " . (time() - $_->{time}));
        		    debug("values: " . join(', ', map { $_->{val} } @{$timed{$curr}}));
        		    burninate_motherfuckers_omg($curr, 'high');
                } elsif($value >= $CONFIG{'low_threshold'} + 8) {
                    # if the value is high enough for low effect, we can assume it's correct.

        		    # low effect start firing (hysteresis)

        		    debug("low start $curr, val $value, tdif " . (time() - $_->{time}));
        		    debug("values: " . join(', ', map { $_->{val} } @{$timed{$curr}}));
        		    burninate_motherfuckers_omg($curr, 'low');
        		    next;
        		} elsif(($value >= $CONFIG{'low_threshold'}) && $effect_state{$curr} == 'low') {
                    # effect was already on

        		    # low effect continue firing
        		    debug("low cont  $curr, val $value, tdif " . (time() - $_->{time}));
        		    debug("values: " . join(', ', map { $_->{val} } @{$timed{$curr}}));
        		    burninate_motherfuckers_omg($curr, 'low');
        		    next;
        		} else {
                    # check this value and the other value too.
                    my $current_values = map { $sensor_current{$_} } $point_addresses{$curr};
                    if($current_values[0] < $CONFIG{'low_threshold'} && $current_values[1] < $CONFIG{'low_threshold'}) {
                      burninate_motherfuckers_omg($curr, 'off');
                      debug("values: " . join(', ', map { $_->{val} } @{$timed{$curr}}) );
                    }
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
                debug("$effect is already off");
            }
        }
    } elsif($effect_state{$effect} eq 'low') {
	    # low effect is on.
    	if($state eq 'low') {
            debug("$effect is already low");
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
    	    debug("$effect is already high");
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
    logit($line,0)
}

sub info {
    my $line = shift;
    logit($line,1);
}

sub debug {
    my $line = shift;
    logit($line,2);
}

sub logit {
    my $line  = shift;
    my $level = shift;

    return unless $level >= $CONFIG{'verbose'};

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

