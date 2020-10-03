RAMDISKDIR=/dev/shm/plex_db_ramdisk
PLEXDBLOC="/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/Plug-in Support/Databases/"

function FailExit(){

umount "$PLEXDBLOC"
docker start plex

exit 1
}


if [ ! -d "$RAMDISKDIR" ]; then
    mkdir "$RAMDISKDIR"
fi

touch "$RAMDISKDIR/THIS_IS_A_RAMDISK"

if [ -f "$PLEXDBLOC/THIS_IS_A_RAMDISK" ]; then
   echo Ramdisk already installed. Exiting.
   exit
fi

docker stop plex
rsync -a --progress -h "$PLEXDBLOC" "$RAMDISKDIR"
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



