#!/bin/bash
#Control Script Version 1.18.4
#gather_schema_list() - executes a SQL statement against the source database and writes the resulting schema names to a file
#database_backup() - performs a Data Pump export for a single schema or loops through a schema list file for multi-schema backups
#database_import() - performs a Data Pump import for a single schema or loops through a schema list file for multi-schema imports
#sql_schema_list - end-to-end workflow that runs a SQL query to build the schema list, then drives backup and import for each result
#---------------------------------------------------------------


#Secure Copy Function
secure_copy() {
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

   SCP_STATUS=$?
   if (( SCP_STATUS != 0 ))
   then
      echo "Secure copy has FAILED"
      send_email "ERROR: Secure Copy Failed" \
"Secure copy has FAILED.

Source: ${src}
Destination: ${dest_user}@${dest_server}:${dest_path}
Type: ${dest_type}"
      echo "Email notification sent to ${DISTRO_EMAIL}"
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
      send_email "ERROR: Backup Failed - Copy Operation" \
"The copy operation has FAILED.

Source: ${SRC}
Destination: ${BACKUP_PATH}
Runner: ${RUNNER}"
      echo "Email notification sent to ${DISTRO_EMAIL}"
      exit 1
   fi

   echo "Listing files in backup directory..."
   ls -R "${DST}/${RUNNER}"
}

#Database Backup Function
database_backup() {
   echo "Using RUNNER='${RUNNER}'"

   BACKUP_DBCHECKLOG="/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/dbcheck.log"

#Confirm the Oracle instance is running by checking for the PMON process — PMON is Oracle's process monitor and is only present when the instance is active
   if ( ps -ef | grep pmon | grep ${ORA_SID} )
   then
      echo "The ${ORA_SID} Instance is UP AND RUNNING."
   else
      echo "The ${ORA_SID} Instance is DOWN."
      exit 1
   fi

#Verify the database is in OPEN status before attempting a backup — an instance can be running but not yet open
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

#If a schema list file exists, run in multi-schema mode — otherwise fall through to the original single schema behavior
   if [[ -n "${SCHEMA_LIST_FILE}" && -f "${SCHEMA_LIST_FILE}" ]]
   then
      echo "Multi-schema mode: reading schemas from ${SCHEMA_LIST_FILE}"

#Read each schema name from the file one at a time — LFS= preserves leading/trailing whitespace, -r prevents backslash interpretation
      while LFS= read -r SCHEMA
      do
#Blank lines in the schema file are skipped to avoid passing an empty value to expdp
         [[ -z "${SCHEMA}" ]] && continue

         echo "--- Backing up schema: ${SCHEMA} ---"

#Build the PAR file for this schema
         DMP_NAME="${SCHEMA}_${RUNNER}_${TS}.dmp"
         LOG_NAME="${SCHEMA}_${RUNNER}_${TS}.log"
         PAR_FILE="${DB_BACKUP_DIR}/${RUNNER}.par"

         echo "userid=stack_temp/stackinc" > "${PAR_FILE}"
         echo "directory=DATA_PUMP_DIR" >> "${PAR_FILE}"
         echo "dumpfile=${DMP_NAME}" >> "${PAR_FILE}"
         echo "logfile=${LOG_NAME}" >> "${PAR_FILE}"
         echo "schemas=${SCHEMA}" >> "${PAR_FILE}"

#Run the Data Pump export — expdp reads the connection credentials, schema name, dumpfile name, and log location from the PAR file
         expdp parfile="${PAR_FILE}"
         EXPDP_STATUS=$?

         FULL_LOG_PATH="${DB_BACKUP_DIR}/${LOG_NAME}"
         echo "Verifying backup status in: ${FULL_LOG_PATH}"

#Check the log and archive if successful
         if grep -q "successfully completed" "${FULL_LOG_PATH}"
         then
            echo "SUCCESS: Database backup confirmed in log file."

            ARCHIVE="expdp_${SCHEMA}_${RUNNER}_${TS}.tar"
            echo "Creating archive ${ARCHIVE}"

            tar -cvf "${DB_BACKUP_DIR}/${ARCHIVE}" -C "${DB_BACKUP_DIR}" "${DMP_NAME}" "${LOG_NAME}" --remove-files

            if (( $? != 0 ))
            then
               echo "CRITICAL ERROR: Archive creation failed."
               send_email "ERROR: Database Backup Failed - ${SCHEMA}" \
"The archive creation has FAILED after export.

Schema: ${SCHEMA}
Runner: ${RUNNER}
ORA_SID: ${ORA_SID}"
               echo "Email notification sent to ${DISTRO_EMAIL}"
               exit 1
            else
               echo "SUCCESS: Archive ${ARCHIVE} created successfully."
               send_email "SUCCESS: Database Backup Completed - ${SCHEMA}" \
"The database backup has completed SUCCESSFULLY.

Schema: ${SCHEMA}
Runner: ${RUNNER}
ORA_SID: ${ORA_SID}
Dump File: ${DMP_NAME}
Archive: ${ARCHIVE}"
               echo "Email notification sent to ${DISTRO_EMAIL}"
#Remove tar archives from the backup directory that are 2 or more days old — enforces the retention policy after each successful backup
               find "${DB_BACKUP_DIR}" -type f -name "*.tar" -mtime +2 -exec rm -f {} \;
               echo "Retention cleanup complete: removed .tar files older than 2 days from ${DB_BACKUP_DIR}"
            fi

         else
            echo "CRITICAL ERROR: Backup success not found in log. Please check ${FULL_LOG_PATH}"
            send_email "ERROR: Database Backup Failed - ${SCHEMA}" \
"The expdp log does not confirm a successful backup.

Schema: ${SCHEMA}
Runner: ${RUNNER}
ORA_SID: ${ORA_SID}
Exit Code: ${EXPDP_STATUS}
Log: ${FULL_LOG_PATH}"
            echo "Email notification sent to ${DISTRO_EMAIL}"
            exit 1
         fi

#End of the backup loop — advance to the next schema in the file
      done < "${SCHEMA_LIST_FILE}"

   else
#Single schema mode — original behavior, no changes to this path
      echo "Using SCHEMA='${SCHEMA}'"

#Build the Data Pump PAR file — this file tells expdp where to connect, which schema to export, and where to write the output
      DMP_NAME="${SCHEMA}_${RUNNER}_${TS}.dmp"
      LOG_NAME="${SCHEMA}_${RUNNER}_${TS}.log"
      PAR_FILE="${DB_BACKUP_DIR}/${RUNNER}.par"

      echo "userid=stack_temp/stackinc" > "${PAR_FILE}"
      echo "directory=DATA_PUMP_DIR" >> "${PAR_FILE}"
      echo "dumpfile=${DMP_NAME}" >> "${PAR_FILE}"
      echo "logfile=${LOG_NAME}" >> "${PAR_FILE}"
      echo "schemas=${SCHEMA}" >> "${PAR_FILE}"

#Run the Data Pump export — expdp reads the connection credentials, schema name, dumpfile name, and log location from the PAR file
      expdp parfile="${PAR_FILE}"
      EXPDP_STATUS=$?

      FULL_LOG_PATH="${DB_BACKUP_DIR}/${LOG_NAME}"
      echo "Verifying backup status in: ${FULL_LOG_PATH}"

#Oracle writes "successfully completed" to the expdp log when the export finishes without errors — use this to verify the backup
      if grep -q "successfully completed" "${FULL_LOG_PATH}"
      then
         echo "SUCCESS: Database backup confirmed in log file."

         ARCHIVE="expdp_${SCHEMA}_${RUNNER}_${TS}.tar"
         echo "Creating archive ${ARCHIVE}"

         tar -cvf "${DB_BACKUP_DIR}/${ARCHIVE}" -C "${DB_BACKUP_DIR}" "${DMP_NAME}" "${LOG_NAME}" --remove-files

         if (( $? != 0 ))
         then
            echo "CRITICAL ERROR: Archive creation failed."
            send_email "ERROR: Database Backup Failed - ${SCHEMA}" \
"The archive creation has FAILED after export.

Schema: ${SCHEMA}
Runner: ${RUNNER}
ORA_SID: ${ORA_SID}"
            echo "Email notification sent to ${DISTRO_EMAIL}"
            exit 1
         else
            echo "SUCCESS: Archive ${ARCHIVE} created successfully."
            send_email "SUCCESS: Database Backup Completed - ${SCHEMA}" \
"The database backup has completed SUCCESSFULLY.

Schema: ${SCHEMA}
Runner: ${RUNNER}
ORA_SID: ${ORA_SID}
Dump File: ${DMP_NAME}
Archive: ${ARCHIVE}"
            echo "Email notification sent to ${DISTRO_EMAIL}"
#Remove tar archives from the backup directory that are 2 or more days old — enforces the retention policy after each successful backup
            find "${DB_BACKUP_DIR}" -type f -name "*.tar" -mtime +2 -exec rm -f {} \;
            echo "Retention cleanup complete: removed .tar files older than 2 days from ${DB_BACKUP_DIR}"
         fi

      else
         echo "CRITICAL ERROR: Backup success not found in log. Please check ${FULL_LOG_PATH}"
         send_email "ERROR: Database Backup Failed - ${SCHEMA}" \
"The expdp log does not confirm a successful backup.

Schema: ${SCHEMA}
Runner: ${RUNNER}
ORA_SID: ${ORA_SID}
Exit Code: ${EXPDP_STATUS}
Log: ${FULL_LOG_PATH}"
         echo "Email notification sent to ${DISTRO_EMAIL}"
         exit 1
      fi
   fi
}

#Database Import Function
database_import() {
   echo "Using Runner='${RUNNER}'"
   echo "Using Database='${DB_NAME}'"
   echo "Using Directory='${DIRECTORY}'"

   if ! grep -q "^${DB_NAME}:" /etc/oratab
   then
      echo "The ${DB_NAME} database cannot be found on this server"
      exit 1
   fi
#Log file used to capture the output of the database open status check before the import begins
   IMPORT_DBCHECKLOG="/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/dbcheck_import.log"
   ENV_FILE="/home/oracle/scripts/oracle_env_${DB_NAME}.sh"

   if [[ ! -f "${ENV_FILE}" ]]
   then
      echo "Environment file not found."
      exit 1
   fi
#Source the Oracle environment file to set ORACLE_HOME, ORACLE_SID, and PATH — required before running sqlplus or impdp
   source "${ENV_FILE}"

#Confirm the Oracle instance is running by checking for the PMON process — PMON is Oracle's process monitor and is only present when the instance is active
   if ( ps -ef | grep pmon | grep ${DB_NAME} )
   then
      echo "The ${DB_NAME} Instance is UP AND RUNNING."
   else
      echo "The ${DB_NAME} Instance is DOWN."
      exit 1
   fi

#Verify the database is in OPEN status before attempting an import — an instance can be running but not yet open
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

#If a schema list file exists, run in multi-schema mode — otherwise fall through to the original single schema behavior
   if [[ -n "${SCHEMA_LIST_FILE}" && -f "${SCHEMA_LIST_FILE}" ]]
   then
      echo "Multi-schema mode: reading schemas from ${SCHEMA_LIST_FILE}"

#Read each schema name from the file one at a time — IFS= preserves leading/trailing whitespace, -r prevents backslash interpretation
      while IFS= read -r SCHEMA
      do
#Blank lines in the schema file are skipped to avoid passing an empty value to impdp
         [[ -z "${SCHEMA}" ]] && continue

         echo "--- Importing schema: ${SCHEMA} ---"

#Build dumpfile and archive names to match what backup created
         DUMPFILE="${SCHEMA}_${RUNNER}_${TS}.dmp"
         ARCHIVE_FILE="expdp_${SCHEMA}_${RUNNER}_${TS}.tar"

         BACKUP_ARCHIVE_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"
         DATA_PUMP_PATH="/backup/AWSJAN26/DATAPUMP/${DB_NAME}"
         ARCHIVE_PATH="${BACKUP_ARCHIVE_DIR}/${ARCHIVE_FILE}"

         echo "Extracting archive ${ARCHIVE_PATH}"
         tar -xvf "${BACKUP_ARCHIVE_DIR}/${ARCHIVE_FILE}" -C "${DATA_PUMP_PATH}" "${DUMPFILE}"

         if (( $? != 0 ))
         then
            echo "CRITICAL ERROR: Archive extraction failed."
            exit 1
         fi

#Build the PAR file for this schema
         PAR_FILE="impdp_${SCHEMA}_${RUNNER}.par"
         LOG_FILE="impdp_${SCHEMA}_${RUNNER}_${TS}.log"
         FULL_LOG_PATH="${DATA_PUMP_PATH}/${LOG_FILE}"
         echo "Creating PAR file: ${PAR_FILE}"

         echo "userid=stack_temp/stackinc" > "${PAR_FILE}"
         echo "schemas=${SCHEMA}" >> "${PAR_FILE}"
         echo "remap_schema=${SCHEMA}:${SCHEMA}_${RUNNER}" >> "${PAR_FILE}"
         echo "directory=${DIRECTORY}" >> "${PAR_FILE}"
         echo "table_exists_action=replace" >> "${PAR_FILE}"
         echo "dumpfile=${DUMPFILE}" >> "${PAR_FILE}"
         echo "logfile=${LOG_FILE}" >> "${PAR_FILE}"

         cat "${PAR_FILE}"

#Run the Data Pump import — impdp reads the schema mapping, dumpfile name, directory, and log location from the PAR file
         impdp parfile="${PAR_FILE}"
         IMPDP_STATUS=$?

#Oracle writes a completion message to the impdp log — check for both clean completion and completion with errors
         echo "Checking import log: ${FULL_LOG_PATH}"
         if grep -q "successfully completed" "${FULL_LOG_PATH}"
         then
            echo "SUCCESS! Database import confirmed in logfile"
         elif grep -q "completed with" "${FULL_LOG_PATH}"
         then
            echo "Import completed with errors. Proceeding to schema verification."
         else
            echo "CRITICAL ERROR! Import success was not confirmed in logfile"
            send_email "ERROR: Database Import Failed - ${SCHEMA}" \
"The database import was not confirmed in the log.

Schema: ${SCHEMA}
Runner: ${RUNNER}
DB Name: ${DB_NAME}
Exit Code: ${IMPDP_STATUS}
Log: ${FULL_LOG_PATH}"
            echo "Email notification sent to ${DISTRO_EMAIL}"
            exit 1
         fi

#Verify the remapped schema shows up in dba_users
         SCHEMA_CHECK_LOG="/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/schema_check.log"
         SCHEMA_RUNNER="${SCHEMA}_${RUNNER}"

         echo "Running schema verification for: ${SCHEMA_RUNNER}"

#Query dba_users and spool the result
         sqlplus -s stack_temp/stackinc <<EOF
set heading off feedback off pagesize 0
spool ${SCHEMA_CHECK_LOG}
select username from dba_users where username like '%${SCHEMA_RUNNER}%';
spool off
exit;
EOF

#If the schema check log was not created, sqlplus likely failed to connect or encountered a session error
         if [[ ! -f "${SCHEMA_CHECK_LOG}" ]]
         then
            echo "CRITICAL ERROR: Schema check log was not created."
            send_email "ERROR: Schema Check Log Missing - ${DB_NAME}" \
"The schema verification log was not created after import.
This may indicate a sqlplus connection issue.

Expected Schema: ${SCHEMA_RUNNER}
DB Name: ${DB_NAME}
Runner: ${RUNNER}"
            echo "Email notification sent to ${DISTRO_EMAIL}"
            exit 1
         fi

#Search the spool log for the remapped schema name to confirm it was created in the target database
         if grep -q "${SCHEMA_RUNNER}" "${SCHEMA_CHECK_LOG}"
         then
            echo "SUCCESS: Schema ${SCHEMA_RUNNER} confirmed in ${DB_NAME}."
         else
            echo "CRITICAL ERROR: Schema ${SCHEMA_RUNNER} was NOT found in ${DB_NAME}."
            send_email "ERROR: Schema Not Found After Import - ${DB_NAME}" \
"The imported schema was NOT found in the database after import.

Expected Schema: ${SCHEMA_RUNNER}
DB Name: ${DB_NAME}
Runner: ${RUNNER}
Schema Check Log: ${SCHEMA_CHECK_LOG}"
            echo "Email notification sent to ${DISTRO_EMAIL}"
            exit 1
         fi

#End of the import loop — advance to the next schema in the file
      done < "${SCHEMA_LIST_FILE}"

   else
#Single schema mode — original behavior, no changes to this path
      echo "Using Schema='${SCHEMA}'"
      echo "Using Dumpfile='${DUMPFILE}'"
      echo "Using Archive File='${ARCHIVE_FILE}'"

      BACKUP_ARCHIVE_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"
      DATA_PUMP_PATH="/backup/AWSJAN26/DATAPUMP/${DB_NAME}"
      ARCHIVE_PATH="${BACKUP_ARCHIVE_DIR}/${ARCHIVE_FILE}"

      echo "Extracting archive ${ARCHIVE_PATH}"
      tar -xvf "${BACKUP_ARCHIVE_DIR}/${ARCHIVE_FILE}" -C "${DATA_PUMP_PATH}" "${DUMPFILE}"

      if (( $? != 0 ))
      then
         echo "CRITICAL ERROR: Archive extraction failed."
         exit 1
      fi

#Build the Data Pump PAR file — this file tells impdp where to connect, which schema to import, how to remap it, and where to write the log
      PAR_FILE="impdp_${SCHEMA}_${RUNNER}.par"
      LOG_FILE="impdp_${SCHEMA}_${RUNNER}_${TS}.log"
      FULL_LOG_PATH="${DATA_PUMP_PATH}/${LOG_FILE}"
      echo "Creating PAR file: ${PAR_FILE}"
      echo "userid=stack_temp/stackinc" > "${PAR_FILE}"
      echo "schemas=${SCHEMA}" >> "${PAR_FILE}"
      echo "remap_schema=${SCHEMA}:${SCHEMA}_${RUNNER}" >> "${PAR_FILE}"
      echo "directory=${DIRECTORY}" >> "${PAR_FILE}"
      echo "table_exists_action=replace" >> "${PAR_FILE}"
      echo "dumpfile=${DUMPFILE}" >> "${PAR_FILE}"
      echo "logfile=${LOG_FILE}" >> "${PAR_FILE}"

      cat "${PAR_FILE}"
#Run the Data Pump import — impdp reads the schema mapping, dumpfile name, directory, and log location from the PAR file
      impdp parfile="${PAR_FILE}"
      IMPDP_STATUS=$?

#Oracle writes a completion message to the impdp log — check for both clean completion and completion with errors
      echo "Checking import log: ${FULL_LOG_PATH}"
      if grep -q "successfully completed" "${FULL_LOG_PATH}"
      then
         echo "SUCCESS! Database imported confirmed in logfile"
      elif grep -q "completed with" "${FULL_LOG_PATH}"
      then
         echo "Import completed with errors. Proceeding to schema verification."
      else
         echo "CRITICAL ERROR! Import success was not confirmed in logfile"
         send_email "ERROR: Database Import Failed - ${SCHEMA}" \
"The database import was not confirmed in the log.

Schema: ${SCHEMA}
Runner: ${RUNNER}
DB Name: ${DB_NAME}
Exit Code: ${IMPDP_STATUS}
Log: ${FULL_LOG_PATH}"
         echo "Email notification sent to ${DISTRO_EMAIL}"
         exit 1
      fi

#Verify the remapped schema shows up in dba_users
      SCHEMA_CHECK_LOG="/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/schema_check.log"
      SCHEMA_RUNNER="${SCHEMA}_${RUNNER}"

      echo "Running schema verification for: ${SCHEMA_RUNNER}"

#Query dba_users and spool the result
      sqlplus -s stack_temp/stackinc <<EOF
set heading off feedback off pagesize 0
spool ${SCHEMA_CHECK_LOG}
select username from dba_users where username like '%${SCHEMA_RUNNER}%';
spool off
exit;
EOF

#If the schema check log was not created, sqlplus likely failed to connect or encountered a session error
      if [[ ! -f "${SCHEMA_CHECK_LOG}" ]]
      then
         echo "CRITICAL ERROR: Schema check log was not created."
         send_email "ERROR: Schema Check Log Missing - ${DB_NAME}" \
"The schema verification log was not created after import.
This may indicate a sqlplus connection issue.

Expected Schema: ${SCHEMA_RUNNER}
DB Name: ${DB_NAME}
Runner: ${RUNNER}"
         echo "Email notification sent to ${DISTRO_EMAIL}"
         exit 1
      fi

#Search the spool log for the remapped schema name to confirm it was created in the target database
      if grep -q "${SCHEMA_RUNNER}" "${SCHEMA_CHECK_LOG}"
      then
         echo "SUCCESS: Schema ${SCHEMA_RUNNER} confirmed in ${DB_NAME}."
      else
         echo "CRITICAL ERROR: Schema ${SCHEMA_RUNNER} was NOT found in ${DB_NAME}."
         send_email "ERROR: Schema Not Found After Import - ${DB_NAME}" \
"The imported schema was NOT found in the database after import.

Expected Schema: ${SCHEMA_RUNNER}
DB Name: ${DB_NAME}
Runner: ${RUNNER}
Schema Check Log: ${SCHEMA_CHECK_LOG}"
         echo "Email notification sent to ${DISTRO_EMAIL}"
         exit 1
      fi
   fi
}

#Gather Schema List Function
#Takes a SQL statement, runs it against the source database, and writes the results to a file
gather_schema_list() {
   echo "Gathering schema list using SQL statement"
   echo "SQL: ${SQL_STATEMENT}"

#Set the schema list file path
   SCHEMA_LIST_FILE="/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/schema_list.log"

#Run the SQL and redirect output to the schema list file
   sqlplus -s stack_temp/stackinc@${SOURCE_DB} <<EOF > "${SCHEMA_LIST_FILE}"
set heading off feedback off pagesize 0
${SQL_STATEMENT}
exit;
EOF

#Verify the schema list file was written to disk — if it does not exist, sqlplus likely failed to connect or returned an error
   if [[ ! -f "${SCHEMA_LIST_FILE}" ]]
   then
      echo "CRITICAL ERROR: Schema list file was not created."
      send_email "ERROR: Schema List Missing - SQL Failed" \
"The schema list file was not created.

SQL: ${SQL_STATEMENT}"
      echo "Email notification sent to ${DISTRO_EMAIL}"
      exit 1
   fi

#An empty file means the SQL returned no rows — without a schema list there is nothing to process, so exit early
   if [[ ! -s "${SCHEMA_LIST_FILE}" ]]
   then
      echo "CRITICAL ERROR: Schema list file is empty. No schemas returned by SQL."
      send_email "ERROR: Schema List Empty - No Results" \
"The SQL statement returned no schemas.

SQL: ${SQL_STATEMENT}
Schema List File: ${SCHEMA_LIST_FILE}"
      echo "Email notification sent to ${DISTRO_EMAIL}"
      exit 1
   fi

#Display the schema list so you can review the SQL results before the backup and import begin
   echo "---Schema file contents---"
   cat "${SCHEMA_LIST_FILE}"
   echo "--------------------------"

#Count and report how many schemas the query returned so you can confirm the scope before proceeding
   SCHEMA_COUNT=$(wc -l < "${SCHEMA_LIST_FILE}")
   if [[ "${SCHEMA_COUNT}" -gt 1 ]]
   then
      echo "Schema list detected: ${SCHEMA_COUNT} schemas found"
   else
      echo "Single schema detected"
   fi
}

#Local Migration Function
local_migration() {

#Display the key runtime variables at the start to confirm the correct values were passed in before executing
   echo "Starting local migration"
   echo "Using RUNNER='${RUNNER}'"
   echo "Using SOURCE_DB='${SOURCE_DB}'"
   echo "Using TARGET_DB='${TARGET_DB}'"
   echo "Using SCHEMA='${SCHEMA}'"
   echo "Using DIRECTORY='${DIRECTORY}'"

#Set source database for export
   ORA_SID="${SOURCE_DB}"
   echo "Preparing export from source database '${ORA_SID}'"
#Execute DB Backup workflow
   database_backup

#Validate export output
   if [[ -z "${DMP_NAME}" || -z "${ARCHIVE}" ]]
   then
      echo "CRITICAL ERROR: Export did not create the required migration files."
      send_email "ERROR: Local Migration Failed - ${SOURCE_DB}" \
"The migration export did not produce the required files.

Source DB: ${SOURCE_DB}
Target DB: ${TARGET_DB}
Runner: ${RUNNER}"
      echo "Email notification sent to ${DISTRO_EMAIL}"
      exit 1
   fi

#Prepare import variables
   DB_NAME="${TARGET_DB}"
   DUMPFILE="${DMP_NAME}"
   ARCHIVE_FILE="${ARCHIVE}"

   echo "Preparing import into target database '${DB_NAME}'"
   echo "Using exported dumpfile '${DUMPFILE}'"
   echo "Using exported archive '${ARCHIVE_FILE}'"
#Execute DB Import workflow
   database_import

#Confirm Migration Success
   echo "SUCCESS: Local migration from '${SOURCE_DB}' to '${TARGET_DB}' completed."
}


#Disk Utilization Function
Disk_Utilization() {
   echo "Checking disk utilization"
   echo "Threshold set to ${THRESHOLD}"
#Define the list of mount points to monitor — each entry will be checked for utilization
   DISKS="/u01 /u02 /u03 /u04 /u05 /backup"

#Verify each disk is mounted before checking utilization — unmounted volumes will not appear in df output
   for DISK in ${DISKS}
   do
#If the disk is not found in df output, it is not mounted — exit to avoid reporting on a missing volume
      if ! df -h | grep "${DISK}" > /dev/null
      then
         echo "Error: ${DISK} is not mounted"
         exit 1
      fi
   done

#Loop through each disk and extract the current utilization percentage
   for DISK in ${DISKS}
   do
#Extract the usage percentage for this disk and strip the % sign so it can be compared numerically
#Column 5 in df -h output is the Use% field
      USAGE=$(df -h | grep "${DISK}" | awk '{print $5}' | sed 's/%//')

      echo "${DISK} utilization: ${USAGE}"
#Compare disk usage against the threshold — if exceeded, send an alert email and log the violation
      if ((USAGE > THRESHOLD))
      then
         echo "------ALERT------: ${DISK} disk utilization is above threshold at ${USAGE}"
         echo "${DISK} utilization is ${USAGE}% which exceeds threshold at ${THRESHOLD}%"
         echo "Sending an email alert to the DEVOPS email distro ${DISTRO_EMAIL}"

#Send an alert email to the DevOps distribution list identifying the disk that exceeded the threshold
         send_email "ALERT: Disk Utilization Exceeded - ${DISK}" \
"Disk utilization has exceeded the threshold.

Disk: ${DISK}
Usage: ${USAGE}%
Threshold: ${THRESHOLD}%"
         echo "Email notification sent to ${DISTRO_EMAIL}"
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
      send_email "ERROR: Cleanup Failed - ${TARGET_DIR}" \
"The file cleanup operation has FAILED.

Directory: ${TARGET_DIR}
File Pattern: ${RM_FILE}
Retention Days: ${RETENTION_DAYS}"
      echo "Email notification sent to ${DISTRO_EMAIL}"
      exit 1
   fi

   echo "Cleanup completed successfully."
}

#Send Email Function
#Sends an alert email to DISTRO_EMAIL with a subject and body
#Usage: send_email "<subject>" "<body>"

send_email() {
   EMAIL_SUBJECT="$1"
   EMAIL_BODY="$2"

   if [[ -z "${DISTRO_EMAIL}" ]]
   then
      echo "WARNING: DISTRO_EMAIL is not set. Cannot send email."
      return 1
   fi

   mail -s "${EMAIL_SUBJECT}" "${DISTRO_EMAIL}" <<EOF
${EMAIL_BODY}
EOF
}

#Usage Function
usage() {
   echo "Usage:"
   echo "$0 secure_copy <dest_type> <dest_user> <dest_server> <dest_path> <src>"
   echo "$0 backup_f_d <source_file|source_dir> <backup_dir> <runner_name>"
   echo "$0 database_backup <RUNNER> <SCHEMA>"
   echo "$0 database_import <RUNNER> <DB_NAME> <SCHEMA> <DIRECTORY> <DUMPFILE> <ARCHIVE_FILE>"
   echo "$0 local_migration <RUNNER> <SOURCE_DB> <TARGET_DB> <SCHEMA> <DIRECTORY>"
   echo "$0 disk_utilization <THRESHOLD>"
   echo "$0 cleanup <RETENTION_DAYS> <TARGET_DIR> <RM_FILE>"
   echo "$0 sql_schema_list \"<SQL_STATEMENT>\" <RUNNER> <SOURCE_DB> <TARGET_DB> <DIRECTORY>"
   echo "Examples:"
   echo "$0 secure_copy cloud oracle ec2-54-152-190-208.compute-1.amazonaws.com /home/oracle/scripts/practicedir_pet_jan26/BIN/BASH file_v15_test"
   echo "$0 backup_f_d test_dir backup test.txt"
   echo "$0 backup_f_d test_dir backup \"directory name\""
   echo "$0 database_backup Peter STACK_TEMP"
   echo "$0 database_import PETER SAMD STACK_TEMP DATA_PUMP_DIR STACK_TEMP_PETER_03-16-2026_13-48-54.dmp expdp_STACK_TEMP_PETER_03-16-2026_13-48-54.tar"
   echo "$0 local_migration PETER APEXDB SAMD STACK_TEMP DATA_PUMP_DIR"
   echo "$0 disk_utilization 80"
   echo "$0 cleanup 7 /backup/AWSJAN26/DATAPUMP/APEXDB pete.txt"
   echo "$0 sql_schema_list \"select username from dba_users where username like '%STACK_TEMP_JAN26%';\" PETER APEXDB SAMD DATA_PUMP_DIR"
}

#Main Body
TS=$(date "+%m-%d-%Y_%H-%M-%S")
TDS=$(date "+%m-%d-%Y")
ORA_SID="APEXDB"
DB_BACKUP_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"
DB_IMPORT_DIR="/backup/AWSJAN26/DATAPUMP/SAMD"
DISTRO_EMAIL="stackcloud15@mkitconsulting.net"

#Helper function to prompt the user for a yes or no response — returns 0 (true) for yes, 1 (false) for no
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

#Route execution to the correct workflow based on the function argument passed to the script

FUNCTION_OPTIONS="secure_copy backup_f_d database_backup database_import disk_utilization cleanup local_migration sql_schema_list quit"
PS3="You have entered an invalid function. Please select a valid function: "

FUNCTION="$1"
while true
do
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
      break
   else
      echo "ERROR: Incorrect number of arguments."
      echo "Usage: $0 scp <user> <server> <path> <source>"

      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter destination type (Example: cloud): " dest_type
         read -p "Enter destination username (oracle): " dest_user
         read -p "Enter destination server (Example: ec2-54-152-190-208.compute-1.amazonaws.com): " dest_server
         read -p "Enter destination path (Example: /home/oracle/scripts/practicedir_pet_jan26/BIN/BASH):" dest_path
         read -p "Enter source file:" src
         secure_copy
         break
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
      break
   else
      echo "ERROR: Incorrect number of arguments."
      echo "Usage: $0 backup_f_d <source_file> <backup_dir> <runner_name>"

      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter source path:" SRC
         read -p "Enter destination path:" DST
         read -p "Enter runner path:" RUNNER
         backup_f_d
         break
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
      break
   else
      echo "ERROR: Incorrect number of arguments."
      echo "Usage: $0 database_backup <RUNNER> <SCHEMA>"

      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter Runner (Example: PETER):" RUNNER
         read -p "Enter Schema (Example: STACK_TEMP):" SCHEMA
         database_backup
         break
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
      break
   else
      echo "ERROR: Incorrect number of arguments"
      echo "Usage: $0 database_import <RUNNER> <DB_NAME> <SCHEMA> <DIRECTORY> <DUMPFILE> <ARCHIVE_FILE>"

      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter Runner (Example: PETER:" RUNNER
         read -p "Enter DB Name (Example: SAMD):" DB_NAME
         read -p "Enter Schema (Example: STACK_TEMP): " SCHEMA
         read -p "Enter DATA_PUMP_DIR:" DIRECTORY
         read -p "Enter Dump File:" DUMPFILE
         read -p "Enter an Archive File:" ARCHIVE_FILE
         database_import
         break
      else
         usage
         exit 1
      fi
   fi
   ;;

   "local_migration")
   echo "Workflow: Local Migration"

   if [[ $# -eq 6 ]]
   then
      RUNNER="$2"
      SOURCE_DB="$3"
      TARGET_DB="$4"
      SCHEMA="$5"
      DIRECTORY="$6"
      local_migration
      break
   else
      echo "ERROR: Incorrect number of arguments"
      echo "Usage $0 <local_migration <RUNNER> <SOURCE_DB> <TARGET_DB> <SCHEMA> <DIRECTORY>"

      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter Runner (Example: PETER):" RUNNER
         read -p "Enter Source DB (Example: APEXDB):" SOURCE_DB
         read -p "Enter Target DB (Example: SAMD):" TARGET_DB
         read -p "Enter Schema (Example: STACK_TEMP):" SCHEMA
         read -p "Enter Directory (Example: DATA_PUMP_DIR):" DIRECTORY
         local_migration
         break
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
      break
   else
      echo "ERROR: Incorrect number of arguments"
      echo "Usage: $0 disk_utilization <THRESHOLD>"

      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter Threshold:" THRESHOLD
         Disk_Utilization
         break
      else
         usage
         exit 1
      fi
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
      break
   else
      echo "ERROR: Incorrect number of arguments."
      echo "Usage: $0 cleanup <RETENTION_DAYS> <TARGET_DIR> <RM_FILE>"

      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter Retention Days:" RETENTION_DAYS
         read -p "Enter Target Directory:" TARGET_DIR
         read -p "Enter file you want removed:" RM_FILE
         cleanup
         break
      else
         usage
         exit 1
      fi
   fi
   ;;

#SQL Schema List workflow
#Runs a SQL query to get schema names, then backs up and imports each one
   "sql_schema_list")
   echo "Workflow: SQL Schema List - Multi-Schema Backup and Import"

   if [[ $# -eq 6 ]]
   then
      SQL_STATEMENT="$2"
      RUNNER="$3"
      SOURCE_DB="$4"
      TARGET_DB="$5"
      DIRECTORY="$6"

#Gather the schema list from the SQL query
      gather_schema_list

#Ask before kicking off backup and import
      read -p "Continue with backup and import? (y/n) " CONFIRM </dev/tty
      if [[ "${CONFIRM^^}" == "Y" ]]
      then
         echo "Proceeding with backup and import..."
      else
         echo "Backup and import canceled."
         exit 1
      fi

#Run backup for each schema in the list
      ORA_SID="${SOURCE_DB}"
      echo "Starting multi-schema backup from ${SOURCE_DB}"
      database_backup

#Run import for each schema in the list
      DB_NAME="${TARGET_DB}"
      echo "Starting multi-schema import into ${TARGET_DB}"
      database_import

      break
   else
      echo "ERROR: Incorrect number of arguments."
      echo "Usage: $0 sql_schema_list \"<SQL_STATEMENT>\" <RUNNER> <SOURCE_DB> <TARGET_DB> <DIRECTORY>"
      echo "Example: $0 sql_schema_list \"select username from dba_users where username like '%STACK_TEMP_JAN26%';\" PETER APEXDB SAMD DATA_PUMP_DIR"
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

   echo "ERROR: The function is incorrect '${FUNCTION}'."

   select MENU_FUNCTION in ${FUNCTION_OPTIONS}
   do
      if [[ "${MENU_FUNCTION}" == "quit" ]]
      then
         echo "Try again...terminating"
         exit 1
      elif [[ -n "${MENU_FUNCTION}" ]]
      then
         FUNCTION="${MENU_FUNCTION}"
         break
   else
      echo "Invalid selection. Please choose a correct menu option."
   fi
   done
   ;;
esac
done

