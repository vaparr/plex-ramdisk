RAMDISKDIR=/dev/shm/plex_db_ramdisk

DOCKER_NAME=plex

PLEXDBLOC="/mnt/user/appdata/$DOCKER_NAME/Library/Application Support/Plex Media Server/Plug-in Support/Databases/"
dry_run=0


function Help(){

    echo "-h,--help:  Displays this"
    echo "--start  :  Starts the ramdisk"
    echo "--stop   :  Stops the ramdisk"
    exit 1
}

function FailExit(){

umount "$PLEXDBLOC"
start_docker $DOCKER_NAME

exit 1
}


function LogInfo() {
    echo "$@"
}

function LogVerbose() {
    [ "$verbose" == "1" ] && echo "$@"
}

function LogWarning() {
    echo "[WARNING] $@"
}

function LogError() {
    echo "[ERROR] $@"
}


function stop_docker() {
    local op="[DOCKER STOP]"
    local stop_seconds=$SECONDS
    LogInfo $op: STOPPING $1 with timeout: $2
    local RUNNING=$(docker container inspect -f '{{.State.Running}}' $1)

    if [[ "$RUNNING" == "false" ]]; then
        LogInfo $op: Docker is already stopped!
        return
    fi

    if [ "$dry_run" == "0" ]; then
        STOPPED_DOCKER=$1
        LogInfo $op: STOPPED docker $(docker stop -t $2 $1) in $((SECONDS - $stop_seconds)) Seconds
    fi
    RUNNING=$(docker container inspect -f '{{.State.Running}}' $1)

    if [[ "$RUNNING" == "false" ]]; then
        LogVerbose $op: Docker Stopped Successfully
    else
        LogWarning $op: Docker not stopped.
        docker stop -t 600 $1
    fi
}

function start_docker() {
    local op="[DOCKER START]"
    local start_seconds=$SECONDS
    LogInfo $op: STARTING $1
    local RUNNING=$(docker container inspect -f '{{.State.Running}}' $1)
    if [[ "$RUNNING" == "true" ]]; then
        LogInfo $op: Docker is already started!
        return
    fi
    if [ "$dry_run" == "0" ]; then
        LogInfo $op: STARTED docker $(docker start $1) in $((SECONDS - $start_seconds)) Seconds
        STOPPED_DOCKER=""
    fi
    RUNNING=$(docker container inspect -f '{{.State.Running}}' $1)
    if [[ "$RUNNING" == "true" ]]; then
        LogVerbose $op: Docker Started Successfully
    else
        LogWarning $op: Docker not started.
        docker start $1
    fi

}




function Start(){


if [ ! -d "$RAMDISKDIR" ]; then
    mkdir "$RAMDISKDIR"
fi

touch "$RAMDISKDIR/THIS_IS_A_RAMDISK"

if [ -f "$PLEXDBLOC/THIS_IS_A_RAMDISK" ]; then
   echo Ramdisk already installed. Exiting.
   exit
fi

stop_docker $DOCKER_NAME 60
rsync -a --progress -h --exclude '*.db-20*' "$PLEXDBLOC/" "$RAMDISKDIR/"
if [ "$?" != "0" ]; then
   echo rsync failed. Exiting
   FailExit
fi

mount --bind "$RAMDISKDIR" "$PLEXDBLOC"
if [ "$?" != "0" ]; then
   echo mount failed. Exiting
   FailExit
fi

mountpoint "$PLEXDBLOC"

if [ "$?" != "0" ]; then
   echo $PLEXDBLOC is not a mountpoint.  Something went wrong.
   FailExit
fi

if [ -f "$PLEXDBLOC/THIS_IS_A_RAMDISK" ]; then
   echo Ramdisk installed successfully.
   start_docker $DOCKER_NAME
else
   echo Something went wrong
   FailExit
fi

}

function Stop() {

mountpoint "$PLEXDBLOC"

if [ "$?" != "0" ]; then
   echo $PLEXDBLOC is not a mountpoint.  Nothing to stop.
   FailExit
fi

stop_docker $DOCKER_NAME 60

umount "$PLEXDBLOC"

mountpoint "$PLEXDBLOC"


if [ "$?" == "0" ]; then
   echo $PLEXDBLOC is still a  mountpoint after unmounting. Something went wrong.
   FailExit
fi

rsync -a --progress -h --exclude THIS_IS_A_RAMDISK --exclude '*.db-20*' "$RAMDISKDIR/" "$PLEXDBLOC/"

start_docker $DOCKER_NAME


}



TEMP=`getopt -o ?h --long start,stop,help  -n 'plex-ramdisk' -- "$@"`

if [ $? != 0 ] ; then Help ; fi

eval set -- "$TEMP"

while true ; do
    case "$1" in
        "--start") echo "Starting the Ramdisk"
            Start
            break
            ;;
        "--stop") echo "Stop" 
            Stop
            break
            ;;
        -?|-h|--help) 
            Help 
            ;;
        --) shift ; break ;;
        *) Help
            ;;
    esac
done
#echo "Remaining arguments:"
#for arg do echo '--> '"\`$arg'" ; done
exit 2

