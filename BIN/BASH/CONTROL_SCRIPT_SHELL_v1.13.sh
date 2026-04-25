#!/bin/bash
#Control Script Version 1.13

#Secure Copy Function
secure_copy() {

   if ( ! nslookup "${dest_server}" )
   then
      echo "${dest_server} is not active"
      exit 1
   fi

   scp -i stackcloud15_kp.pem ${src} ${dest_user}@${dest_server}:${dest_path}
if (( $? !=0 ))
then
   echo "Secure copy has FAILED"
else
   echo "Secure copy was SUCCESSFUL"
fi
}

#Backup File/Directory Function
backup_f_d() {
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

#Database Backup Function
database_backup() {
   echo "Commencing Database Backup..."
   echo "Using RUNNER='${RUNNER}'"
   echo "Using SCHEMA='${SCHEMA}'"

BACKUP_DBCHECKLOG="/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/dbcheck.log"

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
   sqlplus -s stack_temp/stackinc <<EOF > ${BACKUP_DBCHECKLOG}
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
   DMP_NAME="${SCHEMA}_backup_${TS}.dmp"
   LOG_NAME="${SCHEMA}_${MYNAME}_${TS}.log"
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

#Databse Import Function
database_import() {

	echo "Commencing Database Import"
	echo "Using Runner='${RUNNER}'"
	echo "Using Database='${DB_NAME}'"
	echo "Using Schema='${SCHEMA}'"
	echo "Using Directory='${DIRECTORY}'"
	echo "Using Dumpfile='${DUMPFILE}'"

	if ! grep -q "^${DB_NAME}:" /etc/oratab
	then
		echo "The ${DB_NAME} database cannot be found on this server"
	exit 1
	fi
#Import DB Check Log
IMPORT_DBCHECKLOG="/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/dbcheck_import.log"
ENV_FILE="/home/oracle/scripts/oracle_env_${DB_NAME}.sh"

	if [[ ! -f "${ENV_FILE}" ]]
	then
		echo "Environment file not found."
	exit 1
	fi
#Source the Oracle Env Dynamically
	source "${ENV_FILE}"

#Check DB Instance
	if ( ps -ef | grep pmon | grep ${DB_NAME} )
	then
		echo "The ${DB_NAME} Instance is UP AND RUNNING."
	else
		echo "The ${DB_NAME} Instance is DOWN."
		exit 1
	fi

#Check DB Open Status
	sqlplus -s stack_temp/stackinc <<EOF > ${IMPORT_DBCHECKLOG}
	set heading off feedback off pagesize 0
	select status from v\$instance;
	exit;
EOF

   if ( grep "OPEN" ${IMPORT_DBCHECKLOG} )
   then
		echo "Database is OPEN. Ready for import."
	else
		echo "The Database is NOT OPEN. Terminating import."
		exit 1
	fi

#Build PAR file
	PAR_FILE="impdp_${SCHEMA}_${RUNNER}.par"
	LOG_FILE="impdp_${SCHEMA}_${RUNNER}_${TS}.log"
	
	DATA_PUMP_PATH="/backup/AWSJAN26/DATAPUMP/${DB_NAME}"
	FULL_LOG_PATH="${DATA_PUMP_PATH}/${LOG_FILE}"
	echo "Creating PAR file: ${PAR_FILE}"

#Write PAR file contents
	echo "userid=stack_temp/stackinc" > "${PAR_FILE}"
	echo "schemas=${SCHEMA}" >> "${PAR_FILE}"
	echo "remap_schema=${SCHEMA}:${SCHEMA}_${RUNNER}" >> "${PAR_FILE}"
	echo "directory=${DIRECTORY}" >> "${PAR_FILE}"
	echo "dumpfile=${DUMPFILE}" >> "${PAR_FILE}"
	echo "logfile=${LOG_FILE}" >> "${PAR_FILE}"
	
	cat "${PAR_FILE}"
#Execute import
	impdp parfile="${PAR_FILE}"
	
#Verify Success
	
	echo "Checking import log: ${FULL_LOG_PATH}"
	if grep -q "successfully completed" "${FULL_LOG_PATH}"
		then
		echo "SUCCESS! Database imported confirmed in logfile"
	else
		echo "CRITICAL ERROR! Import success was not confirmed in logfile"
	exit 1
	fi
}


#Usage
usage() {
   echo "Usage:"
	echo "$0 secure_copy <dest_user> <dest_server> <dest_path> <src>"
   echo "$0 backup_f_d <source_file|source_dir> <backup_dir> <runner_name>"
   echo "$0 database_backup <RUNNER> <SCHEMA>"
   echo "$0 database_import <RUNNER> <DB_NAME> <SCHEMA> <DIRECTORY> <DUMPFILE>"
   echo "Examples:"
	echo "  $0 secure_copy"
   echo "  $0 backup_f_d test_dir backup test.txt"
   echo "  $0 backup_f_d test_dir backup \"directory name\""
   echo "  $0 database_backup"
	echo "  $0 database_import database_import Peter SAMD STACK_TEMP DATA_PUMP_DIR expdp_APEXDB_PETER.dmp"
}

#Main Body
TS=$(date "+%m%d%Y%H%M%S")
TDS=$(date "+%m%d%Y")
ORA_SID="APEXDB"
MYNAME="PETER"
DB_BACKUP_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"


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

	"secure_copy")
		echo "Workflow: Secure Copy (SCP) Transfer"

	if [[ $# -eq 5 ]]	
		then
		dest_user="$2"
		dest_server="$3"
		dest_path="$4"
		src="$5"
	secure_copy
	else
      echo "ERROR: Incorrect number of arguments."
      echo "Usage: $0 scp <user> <server> <path> <source>"

	if ask_for_help "Hello! Do you need help entering the required values?"
	then
		read -p "Enter destination user: " dest_user
		read -p "Enter destination server: " dest_server
		read -p "Enter destination path: " dest_path
		read -p "Enter source: " src		
	secure_copy
	else
		usage
		exit 1
		fi
	fi
   ;;


   "backup_f_d")
      echo "Workflow: File/Directory Backup"

   if [[ $# -eq 4 ]]
   then
      SRC="$2"
      DST="$3"
      RUNNER="$4"
      backup_f_d
   else
      echo "ERROR: Incorrect number of arguments."
      echo "Usage: $0 backup_f_d <source_file> <backup_dir> <runner_name>"

      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter source path:" SRC
         read -p "Enter destination path:" DST
         read -p "Enter runner path:" RUNNER
      backup_f_d
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
         read -p "Enter YOUR NAME:" RUNNER
         read -p "Enter STACK_TEMP:" SCHEMA
      database_backup
      else
         usage
         exit 1
      fi
   fi
   ;;

   "database_import")
   echo "Workflow: Database Import"
	if [[ $# -eq 6 ]]
	then
		RUNNER="$2"
		DB_NAME="$3"
		SCHEMA="$4"
		DIRECTORY="$5"
		DUMPFILE="$6"
		database_import
	else
		echo "ERROR: Incorrect number of arguments"
		echo "Usage: $0 database_import <RUNNER> <DB_NAME> <SCHEMA> <DIRECTORY> <DUMPFILE>"

		if ask_for_help "Hello! Do you need help entering the required values?"
		then
			read -p "Enter Runner:" RUNNER
			read -p "Enter APEXDB or SAMD:" DB_NAME
			read -p "Enter STACK_TEMP: " SCHEMA
			read -p "Enter DATA_PUMP_DIR:" DIRECTORY
			read -p "Enter DUMPFILE:" DUMPFILE
		database_import
		else
			usage
			exit 1
		fi
	fi
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

