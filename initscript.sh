#!/bin/bash

## Fill in name of program here.
PROG="2pir.pl"
PROG_PATH="/var/projects/2pir" ## Not need, but sometimes helpful (if $PROG resides in /opt for example).
PID_PATH="/var/run/"
LOG_PATH="/var/log/2pir"
PROG_ARGS="--log $LOG_PATH/app.log"

start() {
    if [ -e "$PID_PATH/$PROG.pid" ]; then
        ## Program is running, exit with error.
        echo "Error! $PROG is currently running!" 1>&2
        exit 1
    fi

    if [ ! -e $LOG_PATH ]; then
        echo "Error! $LOG_PATH is missing" 1>&2
        exit 1
    fi

    CURRENT_DAEMON_LOG = "$LOG_PATH/daemon.log"

    if [ -e $CURRENT_DAEMON_LOG ]; then
        ARCHIVED_LOG = `date +$LOG_PATH/daemon.%Y%m%d%H%M%S.log`
        echo "Archiving current daemon log to $ARCHIVED_LOG"
        mv $CURRENT_DAEMON_LOG $ARCHIVED_LOG
    }

    CURRENT_APP_LOG = "$LOG_PATH/app.log"

    if [ -e $CURRENT_APP_LOG ]; then
        ARCHIVED_LOG = `date +$LOG_PATH/app.%Y%m%d%H%M%S.log`
        echo "Archiving current daemon log to $ARCHIVED_LOG"
        mv $CURRENT_APP_LOG $ARCHIVED_LOG
    }

    $PROG_PATH/$PROG $PROG_ARGS > $CURRENT_DAEMON_LOG 2>&1 > /dev/null &	
    echo "$PROG started"
    touch "$PID_PATH/$PROG.pid"
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
        echo "Usage: $0 {start|stop|restart}" 1>&2
        exit 1
    ;;
esac
