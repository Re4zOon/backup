#!/bin/bash
###########################################################################################################
#
# COPYRIGHT (C) 2020 BY My sanity
#
# DESCRIPTION:
#
#       Backup script. Uses a folder list, which it first copies to a tarball, then compresses and copies
#               it to a remote server. The script has a cleanup function.
#
#       This script can be executed manually.
#
# MODIFICATION HISTORY:
#
# YYMMDD |                      Auth                     | Description
# -------+-----------------------------------------------+-------------------------------------------------
# 200311 | Mátyás Szombathy (szombathy.matyas@gmail.com) | Base script
#--------+-----------------------------------------------+-------------------------------------------------
# XXXXXX | Mátyás Szombathy (szombathy.matyas@gmail.com) | Exclude Journal
#--------+-----------------------------------------------+-------------------------------------------------
###########################################################################################################

#backup options
HOSTNAME_SHORT=$(hostname --short)
FILEDATE=`date +%Y-%m-%d-%H-%M-%S`
LOCALFOLDER="/backup"
TARBALL="$LOCALFOLDER/$HOSTNAME_SHORT-backup-$FILEDATE.tar"

#target options
TARGETHOST=192.168.0.15
TARGETFOLDER="/backup/$HOSTNAME_SHORT"



# Logging options
logfolder="/var/log/backuplog"
logfile="$logfolder/backup-$FILEDATE.log"
output=true
log2file=true
syslog=true

Get_Date() {
        local Date=$(date +"%b %d %T")
        echo "$Date"
}

Log_Info() {
        [ $syslog == true ] && logger -p 'local6.info' -t ${0##*/} "$1"
        [ $log2file == true ] && Date=$(Get_Date) && echo "INFO: $Date : $1" >> "$logfile"
        [ $output == true ] && Date=$(Get_Date) && echo "INFO: $Date : $1"
}

Log_Warn() {
        [ $syslog == true ] && logger -p 'local6.warn' -t ${0##*/} "$1"
        [ $log2file == true ] && Date=$(Get_Date) && echo "WARNING: $Date : $1" >> "$logfile"
        [ $output == true ] && Date=$(Get_Date) && echo "WARNING: $Date : $1"
}

Log_Err() {
        [ $syslog == true ] && logger -p 'local6.crit' -t ${0##*/} "$1"
        [ $log2file == true ] && Date=$(Get_Date) && echo "ERROR: $Date : $1" >> "$logfile"
        [ $output == true ] && Date=$(Get_Date) && echo "ERROR: $Date : $1"
}

Return_Check() {
                local Retval=$1
                local object=$2
                local action=$3

                if [ $Retval != 0 ] ; then
                        Log_Err "$object $action failed"
                        exit 1
                else
                        Log_Info "$object $action finished"
                fi

}

Add_to_TAR() {
                local tar=$1
                local folder=$2
                local skip=$3
                local action="taring"

                nice -n 15 tar -rSf $tar $folder
                RTN=$?

                if [ $skip = 1 ]; then
                        Log_Info "$folder $action check skipped"
                else
                        Return_Check $RTN $folder $action
                fi
}

Compress_TAR() {
                local tar=$1
                local action="compression"

                nice -n 17 xz -v -T 0 -6 $tar
                RTN=$?

                Return_Check $RTN $tar $action
}

Check_target() {
                local targethost=$1
                local targetfolder=$2

                ssh $targethost -o StrictHostKeyChecking=no ls -la $targetfolder
                RTN=$?

                if [ 2 = $RTN ] ; then
                        Log_Info "Backup folder does not exist, creating it"
                        Create_target $targethost $targetfolder
                elif [ 0 = $RTN ] ; then
                        :
                else
                        Log_Err "Backup folder check failed"
                        exit 1
                fi
}

Create_target() {
                local targethost=$1
                local targetfolder=$2
                local message="Target"
                local action="mkdir"

                ssh -o StrictHostKeyChecking=no $targethost mkdir $targetfolder
                RTN=$?

                Return_Check $RTN $message $action
}

Copy_tarball() {
                local localfolder=$1
                local targethost=$2
                local targetfolder=$3
                local message="Backup"
                local action="scp"

                /usr/bin/rsync -av --progress $localfolder/ $targethost:/$targetfolder/
                RTN=$?

                Return_Check $RTN $message $action
}

Cleanup_old() {
                local backupfolder=$1

                /usr/bin/find $backupfolder -type f -mtime +1 -ls -exec rm {} \; >> /root/remove.log
}

Prepare_backup() {
                #Prepare folders and logging
                local action="folder creation"
                if [ ! -d "/backup" ]; then
                        mkdir /backup
                fi
                RTN=$?
                local message="Backup"
                Return_Check $RTN $message "$action"

                if [ ! -d "/var/log/backuplog" ]; then
                        mkdir /var/log/backuplog
                fi

                RTN=$?
                local message="Log"
                Return_Check $RTN $message "$action"

		systemctl list-unit-files > /root/services.txt
}

CreateLogRotateConf() {
local conf=$1

cat << EOF > "$conf"
$logfolder/*log {
        missingok
    notifempty
    maxsize 500k
    daily
    rotate 10
    create 0600 root root
}
EOF

}

Main() {


                #Prepare folders
                Prepare_backup

                #Directory list
                local etc="/etc"
                local opt="/opt"
                local log="/var/log"
                local cron="/var/spool/cron"
                local root="/root"
                local html="/usr/share/nginx/html"
                local plex="/var/lib/plexmediaserver/backup"
		local transmission="/var/lib/transmission"

                dirlist=($etc $opt $log $cron $root $html $plex $transmission)

                #Skip list
                skiplist=($log $opt)

                Log_Info "Creating TARBALL"
                for dir in      ${dirlist[*]}; do
                        Log_Info "Starting taring $dir"
                        local skip=0

			if [[ " ${skiplist[@]} " =~ " ${dir} " ]]; then
                                skip=1
                        fi

                        Add_to_TAR $TARBALL $dir $skip

                done

                #Compressing tarball
                Log_Info "Compressing tarball"
                Compress_TAR $TARBALL

                #Checking target directory
                Log_Info "Checking target directory"
                Check_target $TARGETHOST $TARGETFOLDER

                #Copying backup tarball to target
                Log_Info "Copying backup tarball to target"
                Copy_tarball $LOCALFOLDER $TARGETHOST $TARGETFOLDER

                #Deleting old backups
                Log_Info "Deleting old backups"
                Cleanup_old $LOCALFOLDER
}

Main

