#!/bin/bash

TS=$(date "+%m%d%Y%H%S")
TDS=$(date "+%m%d%Y")
PRACTICE_DIR='/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH'
BACKUP_DIR=${PRACTICE_DIR}/backup_${TDS}/${TS}

if [[ -d ${BACKUP_DIR} ]]
then
	echo "${BACKUP_DIR} already exists"
else
	echo "Creating timestamped backup directory..."
	
	mkdir -p ${BACKUP_DIR}
fi
