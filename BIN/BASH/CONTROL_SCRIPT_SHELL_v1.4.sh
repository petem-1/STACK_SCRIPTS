#!/bin/bash

#Check if 3 arguments are provided when running script
if [ $# -ne 3 ]; then
	echo "ERROR: Incorrect number of arguments."
	echo "Usage: $0 <source_file> <backup_dir> <runner_name>"
	exit 1
fi

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


#Identifies if source is a file or directory
if [[ -d ${SRC} ]]; then
	echo "${SRC} is a directory"
	echo "copying ${SRC} to backup location ${BACKUP_PATH}"
cp -rf "${SRC}" "${BACKUP_PATH}"
else
	echo "${SRC} is a file"
	echo "copying ${SRC} to backup location ${BACKUP_PATH}"
	cp -f "${SRC}" "${BACKUP_PATH}"
fi

if [ $? -ne 0 ]; then
	 echo "ERROR: Copy failed for ${SRC}"
	exit 1
fi

#validate
path=$(pwd)
echo "listing files in backup directory"
ls -ltr ${BACKUP_PATH}

