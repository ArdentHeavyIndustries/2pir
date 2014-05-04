#!/usr/bin/perl -w
use strict;


package FakePort;
use Time::HiRes qw (time usleep);

use constant SLEEP_TIME => 10*1000;

sub new {
    my $class = shift;
    my $file  = shift;

    open( DATA, $file ) or
      die "could not opend test file $file becoue $!";

    my $self  = { file => \*DATA, 'print' => 0 };

    bless $self, $class;
    return $self;
}


# dumby methouds to maintain interface
sub baudrate  {}
sub parity    {}
sub databits  {}
sub stopbits  {}
sub handshake {}

sub write_settings {
  return 1;
}


sub write {
  my $self   = shift;
  my $packed = shift;

  my @values = unpack( "C*", $packed );

  my $got = "got write: ". join( ":", @values )."\n";

  if ( $self->{'print'} ) {
    warn $got;
  }

  else {
    my $expected = $self->getLine();

    die "did not get expetced line\nG  $got\nE  $expected\n"
      if ( $got ne $expected );
  }

  usleep(SLEEP_TIME);
}

sub getLine {
  my $self = shift;

  my $file = $self->{file};
  my $line = <$file>;

  if ( not defined $line ) {
    print "run done.\n";
    exit(0);
  }

  return $line;
}


sub read {
  my $self = shift;
  my $size = shift;

  my @data;

  if ( $self->{'print'} ) {
    @data = map { int(rand(51)) } 0..16;
    warn "sending read: ", join( ":", @data ),"\n";
  }

  else {
    my $line = $self->getLine();

    $line =~ /sending read: ([\d:]+)/ or
      die "could not parce read line:\n  $line";

    @data = split /:/, $1;

  }

  my $read = pack("C*", @data );

  usleep(SLEEP_TIME);

  return ( length($read), $read );
}


1;
