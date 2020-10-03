RAMDISKDIR=/dev/shm/plex_db_ramdisk
PLEXDBLOC="/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/Plug-in Support/Databases/"


function Help(){

    echo "-h,--help:  Displays this"
    echo "--start  :  Starts the ramdisk"
    echo "--stop   :  Stops the ramdisk"
    exit 1
}

function FailExit(){

umount "$PLEXDBLOC"
docker start plex

exit 1
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

docker stop plex
rsync -a --progress -h "$PLEXDBLOC/" "$RAMDISKDIR/"
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
   docker start plex
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

docker stop plex

umount "$PLEXDBLOC"

mountpoint "$PLEXDBLOC"


if [ "$?" == "0" ]; then
   echo $PLEXDBLOC is still a  mountpoint after unmounting. Something went wrong.
   FailExit
fi

rsync -a --progress -h --exclude THIS_IS_A_RAMDISK "$RAMDISKDIR/" "$PLEXDBLOC/"

docker start plex


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

