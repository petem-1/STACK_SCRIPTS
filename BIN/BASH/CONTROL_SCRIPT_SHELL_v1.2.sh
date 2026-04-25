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

#Check if directory creation worked
if [ $? -ne 0 ]; then
	echo "CRITICAL ERROR: Could not create directory ${BACKUP_PATH}. Stopping script."
	exit 1
fi

#copying source file to backup destination
echo "copying ${SRC} to backup location ${BACKUP_PATH}"
cp -rf ${SRC} ${BACKUP_PATH}

if [ $? -ne 0 ]; then
	echo "ERROR: Copy failed for ${SRC}"
	exit 1
fi

#validate
path=$(pwd)
echo "listing files in backup directory"
ls -ltr ${BACKUP_PATH}
