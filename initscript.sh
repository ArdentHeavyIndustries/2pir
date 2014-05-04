#!/bin/bash

## Fill in name of program here.
PROG="2pir.pl"
PROG_PATH="/var/projects/2pir" ## Not need, but sometimes helpful (if $PROG resides in /opt for example).
PROG_ARGS="" 
PID_PATH="/var/run/"

start() {
    if [ -e "$PID_PATH/$PROG.pid" ]; then
        ## Program is running, exit with error.
        echo "Error! $PROG is currently running!" 1>&2
        exit 1
    else
        ## Change from /dev/null to something like /var/log/$PROG if you want to save output.
			mv /var/log/$PROG.log.0 /var/log/$PROG.log.1 2>&1 > /dev/null
			mv /var/log/$PROG.log /var/log/$PROG.log.0 2>&1 > /dev/null
            $PROG_PATH/$PROG $PROG_ARGS > /var/log/some.log 2>&1 > /dev/null &
        echo "$PROG started"
        touch "$PID_PATH/$PROG.pid"
    fi
}

stop() {
    if [ -e "$PID_PATH/$PROG.pid" ]; then
        ## Program is running, so stop it
        killall $PROG

        rm "$PID_PATH/$PROG.pid"
        
        echo "$PROG stopped"
    else
        ## Program is not running, exit with error.
        echo "Error! $PROG not started!" 1>&2
        exit 1
    fi
}

## Check to see if we are running as root first.
## Found at http://www.cyberciti.biz/tips/shell-root-user-check-script.html
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

case "$1" in
    start)
        start
        exit 0
    ;;
    stop)
        stop
        exit 0
    ;;
    reload|restart|force-reload)
        stop
        start
        exit 0
    ;;
    **)
        echo "Usage: $0 {start|stop|reload}" 1>&2
        exit 1
    ;;
esac