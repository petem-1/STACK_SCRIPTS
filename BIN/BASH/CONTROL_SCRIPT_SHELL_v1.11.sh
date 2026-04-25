#!/bin/bash
#Control Script Version 1.11

#Logic for file and directory backups
BACKUP_F_D() {
	echo "Using SRC='${SRC}'"
   echo "Using DST='${DST}'"
   echo "Using RUNNER='${RUNNER}'"

   BACKUP_PATH="${DST}/${RUNNER}/${TS}"
   echo "Creating directory: ${BACKUP_PATH}"
   mkdir -p "${BACKUP_PATH}"

   if [ $? -ne 0 ]
   then
      echo "CRITICAL ERROR: Directory creation failed."
      exit 1
   fi

   if [[ -d ${SRC} ]]
   then
      cp -rf "${SRC}" "${BACKUP_PATH}"
   else
      cp -f "${SRC}" "${BACKUP_PATH}"
   fi

   if [ $? -ne 0 ]
   then
      echo "ERROR: Copy operation failed."
   exit 1
   fi

   echo "Listing files in backup directory..."
   ls -R "${DST}/${RUNNER}"
}

#Logic for Database Backup
database_backup() {
ORA_SID="APEXDB"
MYNAME="PETER"
DB_BACKUP_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"
DBCHECKLOG="/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/dbcheck.log"
	
	echo "Commencing Database Backup..."
	echo "Using RUNNER='${RUNNER}'"
	echo "Using SCHEMA='${SCHEMA}'"

#Check DB Instance
	if ( ps -ef | grep pmon | grep ${ORA_SID} )
   then
      echo "The ${ORA_SID} Instance is UP AND RUNNING."
   else
      echo "The ${ORA_SID} Instance is DOWN."
      exit 1
   fi

#Check DB Open Status
   source /home/oracle/scripts/oracle_env_APEXDB.sh
   sqlplus -s stack_temp/stackinc <<EOF > ${DBCHECKLOG}
   set heading off feedback off pagesize 0
   select status from v\$instance;
   exit;
EOF

   if ( grep "OPEN" ${DBCHECKLOG} )
   then
      echo "Database is OPEN. Ready for backup."
   else
      echo "The Database is NOT OPEN. Terminating backup."
      exit 1
   fi

#Build Data Pump PAR file

   DMP_NAME="${SCHEMA}_${RUNNER}_${TS}.dmp"
   LOG_NAME="${SCHEMA}_${RUNNER}_${TS}.log"
   PAR_FILE="${DB_BACKUP_DIR}/${RUNNER}"

   echo "userid=stack_temp/stackinc" > "${PAR_FILE}"
   echo "directory=DATA_PUMP_DIR" >> "${PAR_FILE}"
   echo "dumpfile=${DMP_NAME}" >> "${PAR_FILE}"
   echo "logfile=${LOG_NAME}" >> "${PAR_FILE}"
   echo "schemas=${SCHEMA}" >> "${PAR_FILE}"

#Execute Export
   expdp parfile="${PAR_FILE}"

   FULL_LOG_PATH="${DB_BACKUP_DIR}/${LOG_NAME}"
   echo "Verifying backup status in: ${FULL_LOG_PATH}"

#Check if log contains the Oracle success message
   if grep -q "successfully completed" "${FULL_LOG_PATH}"
   then
      echo "SUCCESS: Database backup confirmed in log file."
   else
      echo "CRITICAL ERROR: Backup success not found in log. Please check ${FULL_LOG_PATH}"
      exit 1
   fi
}

#Usage
usage() {
   echo "Usage:"
   echo "  $0 backup_f_d <source_file|source_dir> <backup_dir> <runner_name>"
   echo "  $0 database_backup <RUNNER> <SCHEMA>"
   echo ""
   echo "Examples:"
   echo "  $0 backup_f_d test_dir backup test.txt"
   echo "  $0 backup_f_d test_dir backup \"name\""
   echo "  $0 database_backup"
}

#Main Body
TS=$(date "+%m%d%Y%H%M%S")
TDS=$(date "+%m%d%Y")

#Utilization
ask_for_help() {

	read -p "$1 (y/n): " ANSWER
	[[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]
}

	if [[ $# -lt 1 ]]
	then
	echo "The number of command line arguments in this script is: $#"
		usage
		exit 1
	fi
#Case statements routes the script to the correct specific workflow
FUNCTION="$1"
case ${FUNCTION} in

   "backup_f_d")
      echo "Workflow: File/Directory Backup"

	if [ $# -eq 4 ]
	then
		SRC="$2"
		DST="$3"
		RUNNER="$4"
		BACKUP_F_D
	else
		echo "ERROR: Incorrect number of arguments."
		echo "Usage: $0 backup_f_d <source_file> <backup_dir> <runner_name>"

		if ask_for_help "Hello! Do you need help entering the required values?"
		then
			read -p "Enter source path (SRC):" SRC
			read -p "Enter destination path (DST):" DST
			read -p "Enter runner path (RUNNER):" RUNNER
		BACKUP_F_D
		else
			usage
			exit 1
		fi
	fi
   ;;

   "database_backup")
   	echo "Workflow: Database Backup"
	
	if [[ $# -eq 3 ]]
	then
		RUNNER="$2"
		SCHEMA="$3"
		database_backup
	else
		echo "ERROR: Incorrect number of arguments."
		echo "Usage: $0 database_backup <RUNNER> <SCHEMA>"

		if ask_for_help "Hello! Do you need help entering the required values?"
		then
			read -p "Enter YOUR NAME (RUNNER):" RUNNER
			read -p "Enter STACK_TEMP (SCHEMA):" SCHEMA
		database_backup
		else
			usage
			exit 1	
		fi
	fi
   ;;

   "database_import")
   echo "Workflow: Database Import"
   # Future logic for DB restoration will go here
   free -m
   ;;

   "secure_copy" | "scp")
   echo "Workflow: Secure Copy (SCP) Transfer"
   # Future logic for remote transfers will go here
   ;;

   "data_migration")
   echo "Workflow: Data Migration"
   ;;

   "AWS")
   echo "Workflow: AWS Cloud Operations"
   ;;

    *)
   # Default error handling for incorrect inputs
   echo "ERROR: Invalid function '${FUNCTION}' entered."
   exit 1
   ;;
esac

