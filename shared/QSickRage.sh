#! /bin/sh

QPKG_NAME=QSickRage
QPKG_DIR=$(/sbin/getcfg $QPKG_NAME Install_Path -f /etc/config/qpkg.conf)
PID_FILE="$QPKG_DIR/config/sickrage.pid"

DAEMON_OPTS="SickBeard.py --datadir $QPKG_DIR/config --daemon --pidfile $PID_FILE --port 7073"

# Determin Arch
arch="$(/bin/uname -m)"

case $arch in
    i686|x86_64|x86)
        ver='x86'
        ;;
    armv5*)
        ver='arm'
        ;;
    armv7*)
       ver='x31'
       ;;
    *)
        ver='none'
        ;;
esac

[ $ver = "none" ] && err_log "Could not determine architecture for $arch"
export PATH=${QPKG_DIR}/${ver}/bin-utils:/Apps/bin:/usr/local/bin:/usr/bin:$PATH

CheckQpkgEnabled() { #Is the QPKG enabled? if not exit the script
    if [ $(/sbin/getcfg ${QPKG_NAME} Enable -u -d FALSE -f /etc/config/qpkg.conf) = UNKNOWN ]; then
        /sbin/setcfg ${QPKG_NAME} Enable TRUE -f /etc/config/qpkg.conf
    elif [ $(/sbin/getcfg ${QPKG_NAME} Enable -u -d FALSE -f /etc/config/qpkg.conf) != TRUE ]; then
        /bin/echo "${QPKG_NAME} is disabled."
        exit 1
    fi

    if [ -z $(which git) ] || [ ! -x $(which git) ]; then
        if [ $(/sbin/getcfg "git" Enable -u -d FALSE -f /etc/config/qpkg.conf) = UNKNOWN ]; then
            /sbin/setcfg "git" Enable TRUE -f /etc/config/qpkg.conf
        elif [ $(/sbin/getcfg "git" Enable -u -d FALSE -f /etc/config/qpkg.conf) != TRUE ]; then
            echo "git is disabled."
            exit 1
        fi
        [ -x /Apps/bin/git ] || /etc/init.d/git.sh restart && sleep 2
    fi

    # if [ $(/sbin/getcfg "Python" Enable -u -d FALSE -f /etc/config/qpkg.conf) = UNKNOWN ]; then
    #   /sbin/setcfg "Python" Enable TRUE -f /etc/config/qpkg.conf
    # elif [ $(/sbin/getcfg "Python" Enable -u -d FALSE -f /etc/config/qpkg.conf) != TRUE ]; then
    #   echo "Python is disabled."
    #   exit 1
    # fi
    #[ -x $DAEMON ] || /etc/init.d/python.sh restart && sleep 2
}

ConfigPython(){ #checks if the daemon exists and will link /usr/bin/python to it
    #python dependency checking
    VER=0
    DAEMON="None"
    for DAEMON2 in /usr/bin/python2.7 /usr/local/bin/python2.7 /opt/bin/python2.7 /Apps/opt/bin/python2.7 /opt/QPython2/bin/python2.7; do
        echo "Looking for $DAEMON2"
        [ ! -x $DAEMON2 ] && continue
        VER2=$(expr substr "$(${DAEMON2} -V 2>&1)" 8 8)
        if [ $VER2 > $VER ]; then
            DAEMON=$DAEMON2
            VER=$VER2
        fi
    done
    if [ ! -x $DAEMON ]; then
        /sbin/write_log "Failed to start $QPKG_NAME, $DAEMON was not found. Please re-install the Pythton qpkg." 1
        exit 1
    else
        /bin/echo "Found Python Version ${VER} at ${DAEMON}"
    fi
}

CheckForGit(){ #Does git exist?
    /bin/echo -n " Checking for git..."

    git_path=$(/sbin/getcfg General git_path -f $QPKG_DIR/config/config.ini)
    if [ ! -x $git_path ]; then
        if [ -x /etc/init.d/git.sh ]; then
            /bin/echo "  Starting git..."
            /etc/init.d/git.sh start
            sleep 2
        fi
        if [ ! -x $git_path ] && [ -x $(which git) ]; then
            git_path=$(which git)
            /sbin/setcfg General git_path $git_path -f $QPKG_DIR/config/config.ini
        else
            /bin/echo "  No git qpkg found, please install it"
            /sbin/write_log "Failed to start $QPKG_NAME, no git found." 1
            exit 1
        fi
    fi
    /bin/echo "Git Found!"
    export git_path
}

CheckQpkgRunning() { #Is the QPKG already running? if so, exit the script
    if [ -f $PID_FILE ]; then
        #grab pid from pid file
        Pid=$(/bin/cat $PID_FILE)
        if [ -d /proc/$Pid ]; then
            /bin/echo " $QPKG_NAME is already running"
            exit 1
        fi
    fi
    #ok, we survived so the QPKG should not be running
}

UpdateQpkg(){ # does a git pull to update to the latest code
    /bin/echo "Updating $QPKG_NAME"

    #The url to the git repository we're going to install
    GIT_URL=git@github.com:SickRage/SickRage.git
    GIT_URL1=https://github.com/SickRage/SickRage.git

    #git clone/pull the qpkg
    [ -d $QPKG_DIR/$QPKG_NAME/.git ] || $git_path clone --depth 1 $GIT_URL $QPKG_DIR/$QPKG_NAME || $git_path clone --depth 1 $GIT_URL1 $QPKG_DIR/$QPKG_NAME
    cd $QPKG_DIR/$QPKG_NAME && $git_path reset --hard HEAD && $git_path pull && /bin/sync
}

StartQpkg(){
    /bin/echo "Starting $QPKG_NAME"
    cd $QPKG_DIR/$QPKG_NAME
    PATH=${PATH} ${DAEMON} ${DAEMON_OPTS}
}

ShutdownQPKG() { #kills a proces based on a PID in a given PID file
    /bin/echo "Shutting down ${QPKG_NAME}... "
    if [ -f $PID_FILE ]; then
        #grab pid from pid file
        Pid=$(/bin/cat $PID_FILE)
        i=0
        /bin/kill $Pid
        /bin/echo -n " Waiting for ${QPKG_NAME} to shut down: "
        while [ -d /proc/$Pid ]; do
            sleep 1
            let i+=1
            /bin/echo -n "$i, "
            if [ $i = 45 ]; then
                /bin/echo " Tired of waiting, killing ${QPKG_NAME} now"
                /bin/kill -9 $Pid
                /bin/rm -f $PID_FILE
                exit 1
            fi
        done
        /bin/rm -f $PID_FILE
        /bin/echo "Done"
    else
        /bin/echo "${QPKG_NAME} is not running?"
    fi
}

case "$1" in
    start)
        CheckQpkgEnabled #Check if the QPKG is enabled, else exit
        /bin/echo "$QPKG_NAME prestartup checks..."
        CheckQpkgRunning #Check if the QPKG is not running, else exit
        CheckForGit      #Check for /opt, start qpkg if needed
        ConfigPython   #Check for Python, exit if not found
        UpdateQpkg     #do a git pull
        StartQpkg    #Finally Start the qpkg

        ;;
    stop)
        ShutdownQPKG
        ;;
    restart)
        echo "Restarting $QPKG_NAME"
        $0 stop
        $0 start
        ;;
    *)
        N=/etc/init.d/$QPKG_NAME.sh
        echo "Usage: $N {start|stop|restart}" >&2
        exit 1
        ;;
esac
