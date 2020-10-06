#!/bin/bash
RAMDISKDIR=/dev/shm/plex_db_ramdisk

DOCKER_NAME=plex

PLEXLOC=http://192.168.1.62:32400
PLEXTOKEN=NONE

# curl -s http://192.168.1.62:32400/livetv/sessions?X-Plex-Token=FAKEKEY | xmllint --xpath 'string(//MediaContainer/@size)' -
# curl -s http://192.168.1.62:32400/status/sessions?X-Plex-Token=FAKEKEY | xmllint --xpath 'string(//MediaContainer/@size)' -

PLEXDBLOC="/mnt/cache/appdata/$DOCKER_NAME/Library/Application Support/Plex Media Server/Plug-in Support/Databases/"
dry_run=0
is_user_script=1

function Help() {

    echo "-h,--help:  Displays this"
    echo "--start  :  Starts the ramdisk"
    echo "--stop   :  Stops the ramdisk"
    echo "--estop  :  Emergency Stop.  Stops docker, and unmounts ramdisk, but does not copy any files."
    echo "--validate [DIR] : Validates the files in this dir are valid"
    echo "--copyback : Stops Plex, Stops the ramdisk, validates db, copies the DB back to disk, restarts"
    echo "--status: Displays current status"
    exit 1
}

function IsPlexIdle() {

    local sessions=$(curl -s $PLEXLOC/status/sessions?X-Plex-Token=$PLEXTOKEN | xmllint --xpath 'string(//MediaContainer/@size)' - 2>/dev/null)
    local livesessions=$(curl -s $PLEXLOC/livetv/sessions?X-Plex-Token=$PLEXTOKEN | xmllint --xpath 'string(//MediaContainer/@size)' - 2>/dev/null)

    echo "Plex has $sessions active streams and $livesessions Live TV streams"

    if [[ "$sessions" == "0" || "$sessions" == "" ]]; then
        if [[ "$livesessions" == "0" || "$livesessions" == "" ]]; then
            return "0"
        fi
    fi
    return "1"

}

function CheckBindsForShm() {

    [[ is_dockerd_running == "false" ]] && LogWarning "Docker is not running." && return

    binds=$(docker inspect -f '{{json .HostConfig.Binds }}' $DOCKER_NAME | jq | grep /dev/shm: 2>/dev/null)
    if [[ "$binds" == "" ]]; then
        LogError "/dev/shm must be mapped to /dev/shm in $DOCKER_NAME config."
        FailExit
    else
        LogInfo "$DOCKER_NAME has /dev/shm mapped. This is good."
    fi

}

function NotifyInfo() {
    if [[ $is_user_script = 1 ]]; then
        /usr/local/emhttp/webGui/scripts/notify -e "[Plex-Ramdisk]" -s "$1" -d "$2" -i "normal"
    fi
    echo "$1 - $2"
}

function NotifyError() {
    if [[ $is_user_script = 1 ]]; then
        /usr/local/emhttp/webGui/scripts/notify -e "[Plex-Ramdisk]" -s "$1" -d "$2" -i "alert"
    fi
    echo "[ERROR] $1 - $2"
}

function FailExit() {

    
    #umount "$PLEXDBLOC"
    #start_docker $DOCKER_NAME

    exit 1
}

function is_dockerd_running() {

    local STATUS=$(/etc/rc.d/rc.docker status 2>/dev/null | head -1 | grep running)

    if [ "$STATUS" != "" ]; then
        echo "true"
    else
        echo "false"
    fi

}

function LogInfo() {
    echo "$@"
}

function LogVerbose() {
    [ "$verbose" == "1" ] && echo "$@"
}

function LogWarning() {
    echo "[WARNING] $*"
}

function LogError() {
    echo "[ERROR] $*"
    NotifyError "Something bad" "$@"
}

function is_docker_running() {

    local RUNNING=$(docker container inspect -f '{{.State.Running}}' "$1")
    LogVerbose "$1 is Running: $RUNNING"
    echo "$RUNNING"
    if [[ "$RUNNING" == "true" ]]; then
        return "0"
    fi

    return "1"

}

function stop_docker() {

    [[ $(is_dockerd_running) == "false" ]] && LogWarning "Docker is not running." && return

    local op="[DOCKER STOP]"
    local stop_seconds=$SECONDS
    LogInfo "$op: STOPPING $1 with timeout: $2"
    local RUNNING=$(docker container inspect -f '{{.State.Running}}' "$1")

    if [[ "$RUNNING" == "false" ]]; then
        LogInfo "$op: Docker is already stopped!"
        return
    fi

    if [ "$dry_run" == "0" ]; then
        LogInfo "$op: STOPPED docker $(docker stop -t "$2" "$1") in $((SECONDS - stop_seconds)) Seconds"
    fi
    RUNNING=$(docker container inspect -f '{{.State.Running}}' "$1")

    if [[ "$RUNNING" == "false" ]]; then
        LogVerbose "$op: Docker Stopped Successfully"
    else
        LogWarning "$op: Docker not stopped."
        docker stop -t 600 "$1"
    fi
}

function start_docker() {
    [[ $(is_dockerd_running) == "false" ]] && LogWarning "Docker is not running." && return

    local op="[DOCKER START]"
    local start_seconds=$SECONDS
    LogInfo "$op: STARTING $1"
    local RUNNING=$(docker container inspect -f '{{.State.Running}}' "$1")
    if [[ "$RUNNING" == "true" ]]; then
        LogInfo "$op: Docker is already started!"
        return
    fi
    if [ "$dry_run" == "0" ]; then
        LogInfo "$op: STARTED docker $(docker start "$1") in $((SECONDS - start_seconds)) Seconds"
    fi
    RUNNING=$(docker container inspect -f '{{.State.Running}}' "$1")
    if [[ "$RUNNING" == "true" ]]; then
        LogVerbose "$op: Docker Started Successfully"
    else
        LogWarning "$op: Docker not started."
        docker start "$1"
    fi

}

function Start() {

    CheckBindsForShm

    if [ ! -d "$RAMDISKDIR" ]; then
        mkdir "$RAMDISKDIR"
    fi

    touch "$RAMDISKDIR/THIS_IS_A_RAMDISK"

    #if [ -f "$PLEXDBLOC/THIS_IS_A_RAMDISK" ]; then
    #   echo Ramdisk already installed. Exiting.
    #   exit
    #fi

    if mountpoint "$PLEXDBLOC"; then
        echo Ramdisk already installed. Exiting.
        exit
    fi

    stop_docker $DOCKER_NAME 60
    sync
    if ! rsync -c -a --progress -h --exclude '*.db-20*' --exclude Last_Known_Good "$PLEXDBLOC/" "$RAMDISKDIR/"; then
        LogError "rsync failed. Exiting"
        FailExit
    fi
    sync

    if ! ValidateDir $RAMDISKDIR; then
        LogError "At least 1 DB is Corrupt"
        FailExit
    fi

    if ! mount --bind "$RAMDISKDIR" "$PLEXDBLOC"; then
        LogError "mount failed. Exiting"
        FailExit
    fi

    if ! mountpoint "$PLEXDBLOC"; then
        LogError "$PLEXDBLOC is not a mountpoint.  Something went wrong."
        FailExit
    fi

    if [ -f "$PLEXDBLOC/THIS_IS_A_RAMDISK" ]; then
        LogInfo "Ramdisk installed successfully."
        start_docker $DOCKER_NAME
    else
        LogInfo "Something went wrong"
        FailExit
    fi

}

function Stop() {
    if ! mountpoint "$PLEXDBLOC"; then    
        LogWarning "$PLEXDBLOC is not a mountpoint.  Nothing to stop."
        FailExit
    fi

    stop_docker $DOCKER_NAME 60
    sleep 15
    umount "$PLEXDBLOC"

    if mountpoint "$PLEXDBLOC"; then    
        LogError "$PLEXDBLOC is still a  mountpoint after unmounting. Something went wrong."
        FailExit
    fi

    if [[ "$1" == "EMERGENCY" ]]; then
        echo "Emergency Stop Completed. Please manually copy the db files in $RAMDISKDIR to $PLEXDBLOC before starting the ramdisk or the docker container again."
        echo "You can use --validate $RAMDISKDIR to validate the files are not corrupted."
        exit 0
    fi

    if ! ValidateDir $RAMDISKDIR; then    
        LogError At least 1 DB is Corrupt
        FailExit
    fi

    rsync -c -a --progress -h --exclude THIS_IS_A_RAMDISK --exclude '*.db-20*' "$RAMDISKDIR/" "$PLEXDBLOC/"

    start_docker $DOCKER_NAME

}

function CopyBack() {

    if IsPlexIdle; then    
        echo Plex is not playing
    else
        echo Plex is currently playing. Not Copying.
        exit 1
    fi

    if ! mountpoint "$PLEXDBLOC"; then    
        LogWarning "$PLEXDBLOC is not a mountpoint.  Nothing to stop."
        FailExit
    fi

    stop_docker $DOCKER_NAME 60
    sleep 15
    umount "$PLEXDBLOC"

    if mountpoint "$PLEXDBLOC"; then    
        LogError "$PLEXDBLOC is still a  mountpoint after unmounting. Something went wrong."
        FailExit
    fi

    if ! ValidateDir $RAMDISKDIR; then
        LogError At least 1 DB is Corrupt
        FailExit
    fi

    rsync -c -a --progress -h --exclude THIS_IS_A_RAMDISK --exclude '*.db-20*' "$RAMDISKDIR/" "$PLEXDBLOC/"

    Start

}

function Status() {
    echo ------------- DOCKER STATUS --------------
    echo "dockerd Service Running: $(is_dockerd_running)"
    echo "$DOCKER_NAME container: $(is_docker_running $DOCKER_NAME)"
    echo

    echo ------------- DOCKER CONFIG --------------
    CheckBindsForShm
    echo "db location: $PLEXDBLOC"
    echo
    echo --------------- PLEX ---------------------
    IsPlexIdle
    echo
    echo -------------- RAMDISK -------------------
    echo Ramdisk Location: $RAMDISKDIR
    if ! mountpoint "$PLEXDBLOC"; then
        echo "Ramdisk is currently not mounted"
    else
        echo "Ramdisk is active:"
        echo "$RAMDISKDIR is currently mounted at $PLEXDBLOC"
    fi
    echo Size:
    du -h -d1 $RAMDISKDIR

    exit 0

}

function ValidateDb() {
    sync
    echo -n "Checking DB $1 ..."
    #echo cp "$1" "$1.old"
    cp "$1" "$1.old"
    sqlite3 "$1.old" "DROP index 'index_title_sort_naturalsort'" >/dev/null 2>&1
    sqlite3 "$1.old" "DELETE from schema_migrations where version='20180501000000'" >/dev/null 2>&1
    local check=$(sqlite3 "$1.old" "PRAGMA integrity_check")
    rm "$1.old"
    if [[ "$check" == "ok" ]]; then

        if [[ "$2" != "NOCOPY" ]]; then
            LogInfo "Database is good! Copying $1 to $PLEXDBLOC/Last_Known_Good"
            mkdir -p "$PLEXDBLOC/Last_Known_Good"
            cp -f "$1" "$PLEXDBLOC/Last_Known_Good"
        fi
        echo PASS
        return 0
    else
        echo FAIL
        return 1
    fi

}

function ValidateDir() {

    if is_docker_running $DOCKER_NAME; then    
        echo "$DOCKER_NAME is running! Can not validate db's in this state!"
        return 1
    fi

    local error=0

    for db in $(find "$1" -type f -name '*.db'); do
        if ! ValidateDb "$db" "$2"; then        
            LogError "$db: DB is Corrupt"
            error=1
        fi
    done

    return $error

}

TEMP=$(getopt -o h --long status,start,stop,estop,validate:,copyback,help -n 'plex-ramdisk' -- "$@")

if [ $? != 0 ]; then Help; fi

eval set -- "$TEMP"
START=0
STOP=0
ESTOP=0
COPYBACK=0
STATUS=0
VALIDATE=""
while true; do
    case "$1" in
    "--start")
        echo "Starting the Ramdisk"
        START=1
        shift
        ;;
    "--stop")
        echo "Stopping the Ramdisk"
        STOP=1
        shift
        ;;
    "--estop")
        echo "Emergency Stop"
        ESTOP=1
        shift
        ;;
    "--validate")
        echo "Validate $2"
        VALIDATE="$2"
        shift 2
        ;;
    "--copyback")
        COPYBACK=1
        shift
        ;;
    "--status")
        STATUS=1
        shift
        ;;
    -h | "--help")
        Help
        break
        ;;
    --)
        shift
        break
        ;;
    *) break ;;
    esac
done
#echo "Remaining arguments:"
#for arg do echo '--> '"\`$arg'" ; done

if [[ "$COPYBACK" == "1" ]]; then
    echo Starting CopyBack
    CopyBack
fi
if [[ "$VALIDATE" != "" ]]; then
    LogInfo "Starting validate on $VALIDATE"
    ValidateDir "$VALIDATE" NOCOPY
fi

if [[ "$STOP" == "1" ]]; then
    Stop
    exit 0
fi
if [[ "$ESTOP" == "1" ]]; then
    Stop EMERGENCY
    exit 0
fi
if [[ "$START" == "1" ]]; then
    Start
fi
if [[ "$STATUS" == "1" ]]; then
    Status
fi

exit 2
