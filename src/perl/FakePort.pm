#!/usr/bin/perl -w
use strict;

package FakePort;

sub new {
    my $class = shift;

    my $self  = {};

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

  #print "got write: ", join( ":", @values ),"\n";
  sleep(0);
}


{
  my $read_offset = 0;

  my @data_map =
    (
     { 3 => 44 },
     { 3 => 55 },
     { 4 => 50 },
     { 4 => 99 },
    );

  sub read {
    my $self = shift;
    my $size = shift;

    my $map  = $data_map[ $read_offset++ % @data_map ];
    my @data = map { exists $$map{$_} ? $$map{$_} : 0 } 0..16;

    #print "sending read: ", join( ":", @data ),"\n";

    my $read = pack("C*", @data );

    return ( length($read), $read );
  }

}
