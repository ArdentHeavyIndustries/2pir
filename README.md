2pir
====

The "brains" of 2pir's 16 flamethrowers.

CLI Usage: 2pir.pl [--config (foo.ini)] [--high_threshold (integer)] [--low_threshold (integer)] [--min_firing_time (float)] [ [--fake] 

--config
	Location of .ini file containing default configuration variables. Default value is 2pir.ini.

--high_threshold
	Threshold to trigger a high flame effect. Default is 80.

--low_threshold
	Threshold to trigger a low flame effect. Default is 200 ( NOT CURRENTLY IN USE )

--min_firing_time
	Minimum amount of time to maintain a given flame effect. Default is 0.2 (200ms).

--logfile
	Where to log application output.
	There is no default; if left unspecified, all output will go to STDOUT. INFO and ERROR messages will go to STDOUT regardless.

--fake
	Use fake serial port; useful for testing, but this functionality is not entirely finished at this time.

Requires Device-SerialPort-1.04
Required package: libdevice-serialport-perl
