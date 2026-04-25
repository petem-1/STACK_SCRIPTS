#!/bin/bash

#variables declarations
SRC=$1
DST=$2
RUNNER=$3

#Builds the unique path
BACKUP_PATH="${DST}/${RUNNER}"

#MainBody
echo "creating backup directory ${BACKUP_PATH}..."
mkdir -p ${BACKUP_PATH}

#copying source file to backup destination
echo "copying ${SRC} to backup location ${BACKUP_PATH}"
cp -rf ${SRC} ${BACKUP_PATH}

if (( $? != 0 ))
then
	echo "The copy command failed: "
fi

echo "exit status of above command is: " $?

#validate
path=$(pwd)
echo "listing files in backup directory"
ls -ltr ${BACKUP_PATH}

