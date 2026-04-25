#!/bin/bash
#Control Script Version 1.17

#Secure Copy Function
secure_copy() {
#Validate server is reachable
	if ( ! nslookup "${dest_server}" )
   then
      echo "${dest_server} is not active"
      exit 1
   fi

#Determine if the source is file or directory
	scp_option=""
	if [[ -d "${src}" ]]
		then
	scp_option="-r"
	fi
#Select the correct SCP command
	if [[ "${dest_type}" == "cloud" ]]
	then
		echo "Starting Cloud Transfer with PEM key"
		scp -i stackcloud15_kp.pem ${scp_option} "${src}" "${dest_user}@${dest_server}:${dest_path}"
	else
		echo "Starting On-Prem Transfer..."
		scp ${scp_option} "${src}" "${dest_user}@${dest_server}:${dest_path}"
	fi

	if (( $? != 0 ))
	then
   	echo "Secure copy has FAILED"
		exit 1
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

   if [[ -d "${SRC}" ]]
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

   if ( grep "OPEN" ${BACKUP_DBCHECKLOG} )
   then
      echo "Database is OPEN. Ready for backup."
   else
      echo "The Database is NOT OPEN. Terminating backup."
      exit 1
   fi

#Build Data Pump PAR file
   DMP_NAME="${SCHEMA}_${RUNNER}_${TS}.dmp"
   LOG_NAME="${SCHEMA}_${RUNNER}_${TS}.log"
   PAR_FILE="${DB_BACKUP_DIR}/${RUNNER}.par"

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

	ARCHIVE="expdp_${SCHEMA}_${RUNNER}_${TS}.tar"
	echo "Creating archive ${ARCHIVE}"
	
	tar -cvf "${DB_BACKUP_DIR}/${ARCHIVE}" -C "${DB_BACKUP_DIR}" "${DMP_NAME}" "${LOG_NAME}" --remove-files

		if (( $? != 0 ))
		then
			echo "CRITICAL ERROR: Archive creation failed."
			exit 1
		else
			echo "SUCCESS: Archive ${ARCHIVE} created successfully."
		fi

   else
      echo "CRITICAL ERROR: Backup success not found in log. Please check ${FULL_LOG_PATH}"
      exit 1
   fi
}

#Database Import Function
database_import() {
	echo "Using Runner='${RUNNER}'"
	echo "Using Database='${DB_NAME}'"
	echo "Using Schema='${SCHEMA}'"
	echo "Using Directory='${DIRECTORY}'"
	echo "Using Dumpfile='${DUMPFILE}'"
	echo "Using Archive File='${ARCHIVE_FILE}'"

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

	BACKUP_ARCHIVE_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"
#Define Data Pump directory using db name	
	DATA_PUMP_PATH="/backup/AWSJAN26/DATAPUMP/${DB_NAME}"
	ARCHIVE_PATH="BACKUP_ARCHIVE_DIR/${ARCHIVE_FILE}"

#Specifies the archive we want to extract
	echo "Extracting archive ${ARCHIVE_PATH}"

#Extracts the archive into the Data Pump dir
	tar -xvf "${BACKUP_ARCHIVE_DIR}/${ARCHIVE_FILE}" -C "${DATA_PUMP_PATH}" "${DUMPFILE}"
	
	if (( $? !=0 ))
	then
		echo "CRITICAL ERROR: Archive extraction failed."
		exit 1
	fi

#Build PAR file
	PAR_FILE="impdp_${SCHEMA}_${RUNNER}.par"
	LOG_FILE="impdp_${SCHEMA}_${RUNNER}_${TS}.log"
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
	elif grep -q "completed with" "${FULL_LOG_PATH}"
	then
		echo "completed with errors"
	else
		echo "CRITICAL ERROR! Import success was not confirmed in logfile"
	exit 1
	fi
}

#Disk Utilization Function
Disk_Utilization() {
	echo "Checking disk utilization"
	echo "Threshold set to ${THRESHOLD}"
#List of disks that will be checked	
	DISKS="/u01 /u02 /u03 /u04 /u05 /backup"

#Validate that the disc is mounted before checking the disks
	for DISK in ${DISKS}
	do
#Searchs disks to find if the specified disk is not mounted, listed in disks
		if ! df -h | grep "${DISK}" > /dev/null
		then
			echo "Error: ${DISK} is not mounted"
			exit 1
		fi
	done

#For loop to loop through each disk and search for the utilization percentage
	for DISK in ${DISKS}
	do
#Extract usage value for the current disk and remove percent sign
	USAGE=$(df -h | grep "${DISK}" | awk '{print $4}' | sed 's/%//')
	
	echo "${DISK} utilization: ${USAGE}"
#Compares disk usage to threshold	
	if (( USAGE > THRESHOLD ))
	then
		echo "<<<<<ALERT>>>>>: ${DISK} disk utilization is above threshold at ${USAGE}"
		echo "${DISK} utilization is ${USAGE}% which exceeds threshold at ${THRESHOLD}%"
		echo "Sending an email alert to the DEVOPS email distro stackcloud15@mkitconsulting.net"

#Sends an alert email to the Devops email distro to notify which disk exceeds the usage threshold
mail -s "Disk Utilization Alert" stackcloud15@mkitconsulting.net <<EOF
Disk Utilization Alert

Disk: ${DISK}
Usage: ${USAGE}%
Threshold: ${THRESHOLD}%

EOF

	fi
done

}

#Cleanup Function
cleanup() {
	echo "Removing files older than Retention Days='${RETENTION_DAYS}' days"
	echo "From Target Directory='${TARGET_DIR}'"
	echo "Locating Wildcard File/File='${RM_FILE}' for removal"

#Validate Target Directory
	if [[ ! -d "${TARGET_DIR}" ]]
	then
		echo "CRITICAL ERROR: Target directory not found."
		exit 1
	fi
#Preview Matching Files
	echo "Preview of files older than ${RETENTION_DAYS} days matching ${RM_FILE}:"
	find "${TARGET_DIR}" -type f -name "${RM_FILE}" -mtime +"${RETENTION_DAYS}" -print

#Count Matching Files
	MATCH_COUNT=$(find "${TARGET_DIR}" -type f -name "${RM_FILE}" -mtime +"${RETENTION_DAYS}" | wc -l)

	if [[ "${MATCH_COUNT}" -eq 0 ]]
	then
		echo "No files matched for cleanup"
		echo "Nothing to remove."
		return 0
	fi

#Delete Matching Files
	find "${TARGET_DIR}" -type f -name "${RM_FILE}" -mtime +"${RETENTION_DAYS}" -exec rm -f {} \;

#Check Cleanup Status
	if [[ $? -ne 0 ]]
	then
		echo "CRITICAL ERROR: Cleanup failed."
		exit 1
	fi

echo "Cleanup completed successfully."
}

#Usage Function
usage() {
   echo "Usage:"
	echo "$0 secure_copy <dest_type> <dest_user> <dest_server> <dest_path> <src>"
   echo "$0 backup_f_d <source_file|source_dir> <backup_dir> <runner_name>"
   echo "$0 database_backup <RUNNER> <SCHEMA>"
   echo "$0 database_import <RUNNER> <DB_NAME> <SCHEMA> <DIRECTORY> <DUMPFILE> <ARCHIVE_FILE>"
	echo "$0 disk_utilization <THRESHOLD>"
	echo "$0 cleanup <RETENTION_DAYS> <TARGET_DIR> <RM_FILE>"
   echo "Examples:"
	echo "$0 secure_copy cloud oracle ec2-54-152-190-208.compute-1.amazonaws.com /home/oracle/scripts/practicedir_pet_jan26/BIN/BASH file_v15_test"
   echo "$0 backup_f_d test_dir backup test.txt"
   echo "$0 backup_f_d test_dir backup \"directory name\""
   echo "$0 database_backup Peter STACK_TEMP"
	echo "$0 database_import database_import PETER SAMD STACK_TEMP DATA_PUMP_DIR STACK_TEMP_PETER_03-16-2026_13-48-54.dmp expdp_STACK_TEMP_PETER_03-16-2026_13-48-54.tar"
	echo "$0 disk_utilization 80"
	echo "$0 cleanup 7 /backup/AWSJAN26/DATAPUMP/APEXDB pete.txt"
}

#Main Body
TS=$(date "+%m-%d-%Y_%H-%M-%S")
TDS=$(date "+%m-%d-%Y")
ORA_SID="APEXDB"
DB_BACKUP_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"
DB_IMPORT_DIR="/backup/AWSJAN26/DATAPUMP/SAMD"

#Utilization Function
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

	if [[ $# -eq 6 ]]	
		then
		dest_type="$2"
		dest_user="$3"
		dest_server="$4"
		dest_path="$5"
		src="$6"
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
	if [[ $# -eq 7 ]]
	then
		RUNNER="$2"
		DB_NAME="$3"
		SCHEMA="$4"
		DIRECTORY="$5"
		DUMPFILE="$6"
		ARCHIVE_FILE="$7"
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
	
	"disk_utilization")
	echo "Workflow: Disk Utilization Check"
	
	if [[ $# -eq 2 ]]
	then
		THRESHOLD="$2"
		Disk_Utilization
	else
		echo "Usage: $0 disk_utilization <THRESHOLD>"
		exit 1
	fi
	;;
	
	"cleanup")	
	echo "Workflow: Cleanup"
	
	if [[ $# -eq 4 ]]
	then
		RETENTION_DAYS="$2"
		TARGET_DIR="$3"
		RM_FILE="$4"
		cleanup
	else
		echo "ERROR: Incorrect number of arguments."	
		echo "Usage: $0 cleanup <RETENTION_DAYS> <TARGET_DIR> <RM_FILE>"
		exit 1
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

