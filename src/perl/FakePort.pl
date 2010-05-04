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

  print "got write: ", join( ", ", map {"'$_'"} @values ),"\n";
}


{
  my $read_offset = 0;

  my @data =
    (
     [ map {0  } 0..255 ],
     [ map {100} 0..255 ],
    );

  sub read {
    my $self = shift;
    my $size = shift;

    my $read = pack("C*", @@data[$read_offset++]);

    return ( $read, length($read) );
  }

}
