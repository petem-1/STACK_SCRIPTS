#!/bin/bash

#variables declarations
SRC='/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/test_dir'
DST='/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/backup'

#MainBody
#Creating Backup Directory
echo "creating backup directory ${DST}..."
mkdir -p ${DST}

#copying source file to backup destination
echo "copying ${SRC} to backup location $DST"
cp -rf ${SRC} ${DST}
if (( $? != 0 ))
then
    echo "The copy command failed: "
fi

echo "exit status of above command is: " $?

#validate
path=$(pwd)
echo "listing files in backup directory"


ls -ltr ${DST}
