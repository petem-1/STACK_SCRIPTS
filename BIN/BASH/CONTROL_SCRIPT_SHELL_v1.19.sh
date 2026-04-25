ontrol Script Version 1.19
#secure_copy() - transfers files or directories to on-prem or cloud servers using SCP
#backup_f_d() - backs up a file or directory to a destination path with a timestamp
#database_backup() - performs a Data Pump export for a single schema or loops through a schema list file for multi-schema backups
#database_import() - performs a Data Pump import for a single schema or loops through a schema list file for multi-schema imports
#gather_schema_list() - executes a SQL statement against the source database and writes the resulting schema names to a file
#local_migration() - runs a full export from the source DB and import into the target DB on the same server
#cloud_database_migration() - exports schemas from on-prem, copies archives to cloud, builds import scripts on the fly, and runs them remotely
#Disk_Utilization() - checks all mount points against a threshold and alerts if any disk is over limit
#cleanup() - removes files older than the retention period from a target directory
#send_email() - sends an alert email to the distribution list with a subject and body
#---------------------------------------------------------------

#Secure Copy Function
secure_copy() {
#Determine if the source is file or directory
   scp_option=""
   if [[ -d "${src}" ]]
   then
#Set the recursive flag so directories are copied in full
      scp_option="-r"
   fi
#Select the correct SCP command based on whether the destination is cloud or on-prem
   if [[ "${dest_type}" == "cloud" ]]
   then
      echo "Starting Cloud Transfer with PEM key"
#Use the PEM key to authenticate against the cloud server
      scp -i stackcloud15_kp.pem ${scp_option} "${src}" "${dest_user}@${dest_server}:${dest_path}"
   else
      echo "Starting On-Prem Transfer..."
#Standard SCP for on-prem transfers — no key required
      scp ${scp_option} "${src}" "${dest_user}@${dest_server}:${dest_path}"
   fi

#Capture the exit code of the scp command to check if it succeeded
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
#Call Disk_Utilization before starting — confirms all disks are under threshold before writing any backup files
   Disk_Utilization
#If any disk exceeded the threshold, Disk_Utilization returns 1 — block the backup and alert the team
   if (( $? != 0 ))
   then
      echo "Backup cannot run - DISK UTILIZATION is above threshold"
      send_email "ALERT: Backup File/Directory Blocked" \
"Disk utilization has exceeded the threshold.
Source: ${SRC}
Destination: ${DST}
RUNNER: ${RUNNER}"
      echo "Email notification sent to ${DISTRO_EMAIL}"
      exit 1
   fi

#Build the full backup destination path using the runner name and timestamp to keep each run organized
   BACKUP_PATH="${DST}/${RUNNER}/${TS}"
   echo "Creating directory: ${BACKUP_PATH}"
#Create the full directory path — -p creates any missing parent directories without error
   mkdir -p "${BACKUP_PATH}"

#If mkdir failed, the backup cannot continue — exit immediately
   if [ $? -ne 0 ]
   then
      echo "CRITICAL ERROR: Directory creation failed."
      exit 1
   fi

#If the source is a directory copy it recursively, otherwise copy it as a single file
   if [[ -d "${SRC}" ]]
   then
      cp -rf "${SRC}" "${BACKUP_PATH}"
   else
      cp -f "${SRC}" "${BACKUP_PATH}"
   fi

#Check if the copy operation succeeded — exit and alert if it failed
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
#List all files recursively so you can visually confirm what was backed up
   ls -R "${DST}/${RUNNER}"
}

#Database Backup Function
database_backup() {
   echo "Using RUNNER='${RUNNER}'"
#Call Disk_Utilization before starting — expdp writes to /backup, a full disk mid-export leaves a corrupt dump file
   Disk_Utilization
#If any disk exceeded the threshold, Disk_Utilization returns 1 — block the backup and alert the team
   if (( $? != 0 ))
   then
      echo "Database Backup cannot run - DISK UTILIZATION is above threshold"
      send_email "ALERT: Database Backup Blocked" \
"Disk utilization has exceeded the threshold.
RUNNER: ${RUNNER}"
      echo "Email notification sent to ${DISTRO_EMAIL}"
      exit 1
   fi

#Path to the log file that captures the database open status check output
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
#Set TNS_ADMIN so the wallet and tnsnames.ora are found — required when running outside an interactive login shell
	export TNS_ADMIN=$ORACLE_HOME/network/admin
#Connect using the wallet alias and run a status query — output is redirected to the check log
   sqlplus -s /@peter_apexdb <<EOF > ${BACKUP_DBCHECKLOG}
   set heading off feedback off pagesize 0
   select status from v\$instance;
   exit;
EOF

#Search the check log for OPEN — any other status means the database is not ready for export
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
      while IFS= read -r SCHEMA
      do
#Blank lines in the schema file are skipped to avoid passing an empty value to expdp
         [[ -z "${SCHEMA}" ]] && continue

         echo "--- Backing up schema: ${SCHEMA} ---"

#Build the PAR file for this schema
         DMP_NAME="${SCHEMA}_${RUNNER}_${TS}.dmp"
         LOG_NAME="${SCHEMA}_${RUNNER}_${TS}.log"
         PAR_FILE="${DB_BACKUP_DIR}/${RUNNER}.par"

#Write the PAR file — each line sets a parameter that expdp reads at runtime
         echo "userid=/@peter_apexdb" > "${PAR_FILE}"
#Set the Oracle directory object that points to the datapump filesystem location on the server
         echo "directory=DATA_PUMP_DIR" >> "${PAR_FILE}"
#Name of the dump file that expdp will write the export data to
         echo "dumpfile=${DMP_NAME}" >> "${PAR_FILE}"
#Name of the log file that expdp will write progress and errors to
         echo "logfile=${LOG_NAME}" >> "${PAR_FILE}"
#The schema to export
         echo "schemas=${SCHEMA}" >> "${PAR_FILE}"

#Run the Data Pump export — expdp reads the connection credentials, schema name, dumpfile name, and log location from the PAR file
         expdp parfile="${PAR_FILE}"
#Capture the exit code so we can check whether expdp succeeded or failed
         EXPDP_STATUS=$?

#Build the full path to the expdp log so we can search it for a success message
         FULL_LOG_PATH="${DB_BACKUP_DIR}/${LOG_NAME}"
         echo "Verifying backup status in: ${FULL_LOG_PATH}"

#Check the log and archive if successful
         if grep -q "successfully completed" "${FULL_LOG_PATH}"
         then
            echo "SUCCESS: Database backup confirmed in log file."

            ARCHIVE="expdp_${SCHEMA}_${RUNNER}_${TS}.tar"
            echo "Creating archive ${ARCHIVE}"

#Bundle the dumpfile and log into a single tar archive — --remove-files deletes the originals after archiving
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

#Write the PAR file — each line sets a parameter that expdp reads at runtime
      echo "userid=/@peter_apexdb" > "${PAR_FILE}"
#Set the Oracle directory object that points to the datapump filesystem location on the server
      echo "directory=DATA_PUMP_DIR" >> "${PAR_FILE}"
#Name of the dump file that expdp will write the export data to
      echo "dumpfile=${DMP_NAME}" >> "${PAR_FILE}"
#Name of the log file that expdp will write progress and errors to
      echo "logfile=${LOG_NAME}" >> "${PAR_FILE}"
#The schema to export
      echo "schemas=${SCHEMA}" >> "${PAR_FILE}"

#Run the Data Pump export — expdp reads the connection credentials, schema name, dumpfile name, and log location from the PAR file
      expdp parfile="${PAR_FILE}"
#Capture the exit code so we can check whether expdp succeeded or failed
      EXPDP_STATUS=$?

#Build the full path to the expdp log so we can search it for a success message
      FULL_LOG_PATH="${DB_BACKUP_DIR}/${LOG_NAME}"
      echo "Verifying backup status in: ${FULL_LOG_PATH}"

#Oracle writes "successfully completed" to the expdp log when the export finishes without errors — use this to verify the backup
      if grep -q "successfully completed" "${FULL_LOG_PATH}"
      then
         echo "SUCCESS: Database backup confirmed in log file."

         ARCHIVE="expdp_${SCHEMA}_${RUNNER}_${TS}.tar"
         echo "Creating archive ${ARCHIVE}"

#Bundle the dumpfile and log into a single tar archive — --remove-files deletes the originals after archiving
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

#Check /etc/oratab to confirm the target database is registered on this server before attempting a connection
   if ! grep -q "^${DB_NAME}:" /etc/oratab
   then
      echo "The ${DB_NAME} database cannot be found on this server"
      exit 1
   fi
#Log file used to capture the output of the database open status check before the import begins
   IMPORT_DBCHECKLOG="/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/dbcheck_import.log"
#Build the path to the Oracle environment file for the target database — sets ORACLE_HOME, ORACLE_SID, and PATH
   ENV_FILE="/home/oracle/scripts/oracle_env_${DB_NAME}.sh"

#Confirm the environment file exists before sourcing it — a missing file means the DB is not set up on this server
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
#Set TNS_ADMIN so the wallet and tnsnames.ora are found — required when running outside an interactive login shell
   export TNS_ADMIN=$ORACLE_HOME/network/admin
#The ,, lowercases DB_NAME so it matches the wallet alias format (peter_samd not peter_SAMD)
   sqlplus -s /@peter_${DB_NAME,,} <<EOF > ${IMPORT_DBCHECKLOG}
   set heading off feedback off pagesize 0
   select status from v\$instance;
   exit;
EOF

#Search the check log for OPEN — any other status means the database is not ready for import
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

#Source directory where the export archives are stored
         BACKUP_ARCHIVE_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"
#Target directory where the dumpfile will be extracted for impdp to read
         DATA_PUMP_PATH="/backup/AWSJAN26/DATAPUMP/${DB_NAME}"
#Full path to the archive file that will be extracted
         ARCHIVE_PATH="${BACKUP_ARCHIVE_DIR}/${ARCHIVE_FILE}"

         echo "Extracting archive ${ARCHIVE_PATH}"
#Extract only the dumpfile from the archive into the datapump directory — impdp reads from there
         tar -xvf "${BACKUP_ARCHIVE_DIR}/${ARCHIVE_FILE}" -C "${DATA_PUMP_PATH}" "${DUMPFILE}"

#If extraction failed the dumpfile is missing and impdp cannot run
         if (( $? != 0 ))
         then
            echo "CRITICAL ERROR: Archive extraction failed."
            exit 1
         fi

#Build the PAR file for this schema
         PAR_FILE="impdp_${SCHEMA}_${RUNNER}.par"
         LOG_FILE="impdp_${SCHEMA}_${RUNNER}_${TS}.log"
#Build the full path to the impdp log so we can check it for a completion message after the import
         FULL_LOG_PATH="${DATA_PUMP_PATH}/${LOG_FILE}"
         echo "Creating PAR file: ${PAR_FILE}"

#Write the PAR file — each line sets a parameter that impdp reads at runtime
         echo "userid=/@peter_${DB_NAME,,}" > "${PAR_FILE}"
#The schema to import from the dumpfile
         echo "schemas=${SCHEMA}" >> "${PAR_FILE}"
#Remap the schema to a new name in the target database — appends the runner name to keep imports organized
         echo "remap_schema=${SCHEMA}:${SCHEMA}_${RUNNER}" >> "${PAR_FILE}"
#The Oracle directory object that points to the datapump filesystem location on the server
         echo "directory=${DIRECTORY}" >> "${PAR_FILE}"
#Replace existing tables if the schema already exists in the target database
         echo "table_exists_action=replace" >> "${PAR_FILE}"
#The dumpfile to import from
         echo "dumpfile=${DUMPFILE}" >> "${PAR_FILE}"
#The log file impdp will write progress and errors to
         echo "logfile=${LOG_FILE}" >> "${PAR_FILE}"

#Print the PAR file contents to the screen so you can verify all parameters before impdp runs
         cat "${PAR_FILE}"

#Run the Data Pump import — impdp reads the schema mapping, dumpfile name, directory, and log location from the PAR file
         impdp parfile="${PAR_FILE}"
#Capture the exit code so we can check whether impdp succeeded or failed
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
#Build the expected remapped schema name — this is what we search for in dba_users
         SCHEMA_RUNNER="${SCHEMA}_${RUNNER}"

         echo "Running schema verification for: ${SCHEMA_RUNNER}"

#Query dba_users and spool the result
         sqlplus -s /@peter_${DB_NAME,,} <<EOF
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

#Source directory where the export archives are stored
      BACKUP_ARCHIVE_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"
#Target directory where the dumpfile will be extracted for impdp to read
      DATA_PUMP_PATH="/backup/AWSJAN26/DATAPUMP/${DB_NAME}"
#Full path to the archive file that will be extracted
      ARCHIVE_PATH="${BACKUP_ARCHIVE_DIR}/${ARCHIVE_FILE}"

      echo "Extracting archive ${ARCHIVE_PATH}"
#Extract only the dumpfile from the archive into the datapump directory — impdp reads from there
      tar -xvf "${BACKUP_ARCHIVE_DIR}/${ARCHIVE_FILE}" -C "${DATA_PUMP_PATH}" "${DUMPFILE}"

#If extraction failed the dumpfile is missing and impdp cannot run
      if (( $? != 0 ))
      then
         echo "CRITICAL ERROR: Archive extraction failed."
         exit 1
      fi

#Build the Data Pump PAR file — this file tells impdp where to connect, which schema to import, how to remap it, and where to write the log
      PAR_FILE="impdp_${SCHEMA}_${RUNNER}.par"
      LOG_FILE="impdp_${SCHEMA}_${RUNNER}_${TS}.log"
#Build the full path to the impdp log so we can check it for a completion message after the import
      FULL_LOG_PATH="${DATA_PUMP_PATH}/${LOG_FILE}"
      echo "Creating PAR file: ${PAR_FILE}"
#Write the PAR file — each line sets a parameter that impdp reads at runtime
      echo "userid=/@peter_${DB_NAME,,}" > "${PAR_FILE}"
#The schema to import from the dumpfile
      echo "schemas=${SCHEMA}" >> "${PAR_FILE}"
#Remap the schema to a new name in the target database — appends the runner name to keep imports organized
      echo "remap_schema=${SCHEMA}:${SCHEMA}_${RUNNER}" >> "${PAR_FILE}"
#The Oracle directory object that points to the datapump filesystem location on the server
      echo "directory=${DIRECTORY}" >> "${PAR_FILE}"
#Replace existing tables if the schema already exists in the target database
      echo "table_exists_action=replace" >> "${PAR_FILE}"
#The dumpfile to import from
      echo "dumpfile=${DUMPFILE}" >> "${PAR_FILE}"
#The log file impdp will write progress and errors to
      echo "logfile=${LOG_FILE}" >> "${PAR_FILE}"

#Print the PAR file contents to the screen so you can verify all parameters before impdp runs
      cat "${PAR_FILE}"
#Run the Data Pump import — impdp reads the schema mapping, dumpfile name, directory, and log location from the PAR file
      impdp parfile="${PAR_FILE}"
#Capture the exit code so we can check whether impdp succeeded or failed
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
#Build the expected remapped schema name — this is what we search for in dba_users
      SCHEMA_RUNNER="${SCHEMA}_${RUNNER}"

      echo "Running schema verification for: ${SCHEMA_RUNNER}"

#Query dba_users and spool the result
      sqlplus -s /@peter_${DB_NAME,,} <<EOF
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
#The ,, lowercases SOURCE_DB so it matches the wallet alias format (peter_apexdb not peter_APEXDB)
   sqlplus -s /@peter_${SOURCE_DB,,} <<EOF > "${SCHEMA_LIST_FILE}"
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

#Validate export output — DMP_NAME and ARCHIVE are set inside database_backup, confirm they are not empty before continuing
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

#Prepare import variables — pass the export output into the import function
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

#Cloud Database Migration Function
#Exports schemas from the on-prem source database, copies archives to the cloud server,
#builds an import script on the fly for each schema, copies it to the cloud practicedir,
#and invokes it remotely from this on-prem server via SSH
cloud_database_migration() {
   echo "Starting Cloud Database Migration"
   echo "Using SQL Statement to gather database schemas='${SQL_STATEMENT}'"
   echo "Using Runner='${RUNNER}'"
   echo "Sourcing DB='${SOURCE_DB}'"
   echo "Sourcing Cloud DB='${CLOUD_DB}'"
   echo "Using Cloud User Name='${CLOUD_USER}'"
   echo "Using Cloud Server='${CLOUD_SERVER}'"
   echo "Using Cloud Data Pump Dir='${CLOUD_DATAPUMP_DIR}'"
   echo "Using Cloud Practice Directory='${CLOUD_PRACTICEDIR}'"
   echo "Using Directory='${DIRECTORY}'"
   echo "Threshold is set='${THRESHOLD}'"

#Run the SQL query to build the schema list before starting the migration
   gather_schema_list
#Prompt the user to review the schema list and confirm before any data movement begins
   read -p "Continue with migration? (y/n)" CONFIRM </dev/tty
   if [[ "${CONFIRM}" == Y || "${CONFIRM}" == y ]]
   then
      echo "Database Schemas have been confirm"
#Set the source database as the active Oracle SID for the export
      ORA_SID="${SOURCE_DB}"
#Run the export for all schemas in the list
      database_backup
#Read each schema name from the file one at a time — IFS= preserves leading/trailing whitespace, -r prevents backslash interpretation
      while IFS= read -r SCHEMA
      do
#Blank lines in the schema file are skipped to avoid passing an empty value to expdp
         [[ -z "${SCHEMA}" ]] && continue

         echo "--- LISTING SCHEMAS FOR DATABASE MIGRATION INTO CLOUD: ${SCHEMA} ---"
#Reconstruct the archive name for this schema — must match what database_backup created
         ARCHIVE="expdp_${SCHEMA}_${RUNNER}_${TS}.tar"
#Set the SCP source to the archive file in the on-prem backup directory
         src="${DB_BACKUP_DIR}/${ARCHIVE}"
#Set SCP variables for the cloud transfer
         dest_type="cloud"
         dest_user="${CLOUD_USER}"
         dest_server="${CLOUD_SERVER}"
         dest_path="${CLOUD_DATAPUMP_DIR}"
#Copy the archive to the cloud server's datapump directory
         secure_copy
#Build the import script name and local temp path — this script will run on the cloud server
         IMPORT_SCRIPT_NAME="impdp_${SCHEMA}_${RUNNER}_${TS}.sh"
         IMPORT_SCRIPT_LOCAL="/tmp/${IMPORT_SCRIPT_NAME}"
#Write the import script to a temp file using a heredoc — variables without \ expand now (on-prem), \$ variables expand later (on cloud)
         cat > "${IMPORT_SCRIPT_LOCAL}" <<EOF
#!/bin/bash
source /home/oracle/scripts/oracle_env_HERC.sh
DMP_NAME="${SCHEMA}_${RUNNER}_${TS}.dmp"
ARCHIVE="expdp_${SCHEMA}_${RUNNER}_${TS}.tar"
DATA_PUMP_PATH="${CLOUD_DATAPUMP_DIR}"
echo "Extracting archive \${ARCHIVE}"
tar -xvf "\${DATA_PUMP_PATH}/\${ARCHIVE}" -C "\${DATA_PUMP_PATH}" "\${DMP_NAME}"
if [[ \$? -ne 0 ]]
then
   echo "CRITICAL ERROR: UNZIP FAILED"
   exit 1
fi
PAR_FILE="impdp_${SCHEMA}_${RUNNER}.par"
LOG_FILE="impdp_${SCHEMA}_${RUNNER}_${TS}.log"
FULL_LOG_PATH="\${DATA_PUMP_PATH}/\${LOG_FILE}"
echo "Creating PAR file: \${PAR_FILE}"
echo "userid=/@peter_${CLOUD_DB,,}" > "\${PAR_FILE}"
echo "schemas=${SCHEMA}" >> "\${PAR_FILE}"
echo "remap_schema=${SCHEMA}:${SCHEMA}_${RUNNER}" >> "\${PAR_FILE}"
echo "directory=${DIRECTORY}" >> "\${PAR_FILE}"
echo "table_exists_action=replace" >> "\${PAR_FILE}"
echo "dumpfile=\${DMP_NAME}" >> "\${PAR_FILE}"
echo "logfile=\${LOG_FILE}" >> "\${PAR_FILE}"
impdp parfile="\${PAR_FILE}"
if grep -q "successfully completed" "\${FULL_LOG_PATH}"
then
   echo "SUCCESS: Import of ${SCHEMA} completed."
elif grep -q "completed with" "\${FULL_LOG_PATH}"
then
   echo "COMPLETED WITH ERRORS: review \${FULL_LOG_PATH}"
else
   echo "CRITICAL ERROR: Import not confirmed in log for ${SCHEMA}."
   exit 1
fi
EOF
         echo "Changing user permissions for ${IMPORT_SCRIPT_LOCAL} to executable"
#Make the import script executable before copying it to the cloud server
         chmod +x "${IMPORT_SCRIPT_LOCAL}"
#Set SCP variables to copy the import script to the cloud practicedir
         src="${IMPORT_SCRIPT_LOCAL}"
         dest_type="cloud"
         dest_user="${CLOUD_USER}"
         dest_server="${CLOUD_SERVER}"
         dest_path="${CLOUD_PRACTICEDIR}"
#Copy the import script to the cloud server
         secure_copy
#SSH into the cloud server and execute the import script remotely
         ssh -i stackcloud15_kp.pem "${CLOUD_USER}@${CLOUD_SERVER}" "bash ${CLOUD_PRACTICEDIR}/${IMPORT_SCRIPT_NAME}"
      done < "${SCHEMA_LIST_FILE}"

   else
      echo "Database Migration ending, schemas have been denied"
      exit 1
   fi
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
      if ! df -hP | grep "${DISK}" > /dev/null
      then
         echo "Error: ${DISK} is not mounted"
         exit 1
      fi
   done
#Initialize the failure flag — it will be set to 1 if any disk exceeds the threshold
   DISK_FAIL=0
#Loop through each disk and extract the current utilization percentage
   for DISK in ${DISKS}
   do
#Extract the usage percentage for this disk and strip the % sign so it can be compared numerically
#Column 5 in df -h output is the Use% field
      USAGE=$(df -hP | grep "${DISK}" | awk '{print $5}' | sed 's/%//')

      echo "${DISK} utilization: ${USAGE}"
#Compare disk usage against the threshold — if exceeded, send an alert email and log the violation
      if (( USAGE > THRESHOLD ))
      then
         echo "|-------ALERT-------|: ${DISK} disk utilization is above threshold at ${USAGE}"
         echo "${DISK} utilization is ${USAGE}% which exceeds threshold at ${THRESHOLD}%"
         echo "Sending an email alert to the DEVOPS email distro ${DISTRO_EMAIL}"
#Send an alert email to the DevOps distribution list identifying the disk that exceeded the threshold
         send_email "ALERT: Disk Utilization Exceeded - ${DISK}" \
"Disk utilization has exceeded the threshold.

Disk: ${DISK}
Usage: ${USAGE}%
Threshold: ${THRESHOLD}%"
         echo "Email notification sent to ${DISTRO_EMAIL}"
#Mark the failure flag so the function returns 1 after checking all disks
         DISK_FAIL=1
      fi
   done

#If any disk failed return 1 — calling functions check this to block their workflow
   if (( DISK_FAIL == 1 ))
   then
      return 1
   fi
#All disks are under threshold — return 0 to signal that it is safe to proceed
   return 0
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
#Preview Matching Files — show what will be deleted before actually removing anything
   echo "Preview of files older than ${RETENTION_DAYS} days matching ${RM_FILE}:"
   find "${TARGET_DIR}" -type f -name "${RM_FILE}" -mtime +"${RETENTION_DAYS}" -print

#Count how many files matched — if none, skip deletion and exit cleanly
   MATCH_COUNT=$(find "${TARGET_DIR}" -type f -name "${RM_FILE}" -mtime +"${RETENTION_DAYS}" | wc -l)

   if [[ "${MATCH_COUNT}" -eq 0 ]]
   then
      echo "No files matched for cleanup"
      echo "Nothing to remove."
      return 0
   fi

#Delete Matching Files — find locates them, -exec rm -f removes each one
   find "${TARGET_DIR}" -type f -name "${RM_FILE}" -mtime +"${RETENTION_DAYS}" -exec rm -f {} \;

#Check if the delete command succeeded
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
#Capture the first argument as the email subject
   EMAIL_SUBJECT="$1"
#Capture the second argument as the email body
   EMAIL_BODY="$2"

#Guard against sending an email when DISTRO_EMAIL is not set — avoids a silent failure
   if [[ -z "${DISTRO_EMAIL}" ]]
   then
      echo "WARNING: DISTRO_EMAIL is not set. Cannot send email."
      return 1
   fi

#Send the email using the mail command — the subject is passed via -s and the body is piped in via heredoc
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
#Set the timestamp used to uniquely name dumpfiles, archives, and log files for each run
TS=$(date "+%m-%d-%Y_%H-%M-%S")
#Set the date-only stamp used where a shorter timestamp is needed
TDS=$(date "+%m-%d-%Y")
#Default source database — used by database_backup when no SOURCE_DB is passed
ORA_SID="APEXDB"
#Default backup directory for Data Pump exports
DB_BACKUP_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"
#Default import directory for Data Pump imports
DB_IMPORT_DIR="/backup/AWSJAN26/DATAPUMP/SAMD"
#Email distribution list for all alerts and status notifications
DISTRO_EMAIL="stackcloud15@mkitconsulting.net"

#Helper function to prompt the user for a yes or no response — returns 0 (true) for yes, 1 (false) for no
ask_for_help() {
   read -p "$1 (y/n): " ANSWER
   [[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]
}

#Exit immediately if no arguments were passed — the script requires at least a function name
   if [[ $# -lt 1 ]]
   then
      echo "The number of command line arguments in this script is: $#"
      usage
      exit 1
   fi

#Route execution to the correct workflow based on the function argument passed to the script

#List of valid function names used by the select menu when an invalid function is entered
FUNCTION_OPTIONS="secure_copy backup_f_d database_backup database_import cloud_database_migration disk_utilization cleanup local_migration sql_schema_list quit"
#Custom prompt displayed when the select menu is triggered
PS3="You have entered an invalid function. Please select a valid function: "

#Read the first argument as the function name to route execution
FUNCTION="$1"
#Loop keeps the script alive so the select menu can re-prompt after an invalid entry
while true
do
case ${FUNCTION} in

   "secure_copy")
   echo "Workflow: Secure Copy (SCP) Transfer"
#Check that exactly 6 arguments were passed — function name plus 5 required parameters
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
#Check that exactly 5 arguments were passed — function name plus 4 required parameters
   if [[ $# -eq 5 ]]
   then
      SRC="$2"
      DST="$3"
      RUNNER="$4"
      THRESHOLD="$5"
      backup_f_d
      break
   else
      echo "ERROR: Incorrect number of arguments."
      echo "Usage: $0 backup_f_d <source_file> <backup_dir> <runner_name> <THRESHOLD>"
      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter source path:" SRC
         read -p "Enter destination path:" DST
         read -p "Enter runner path:" RUNNER
         read -p "Enter Threshold (Example: 80):" THRESHOLD
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
#Check that exactly 4 arguments were passed — function name plus 3 required parameters
   if [[ $# -eq 4 ]]
   then
      RUNNER="$2"
      SCHEMA="$3"
      THRESHOLD="$4"
      database_backup
      break
   else
      echo "ERROR: Incorrect number of arguments."
      echo "Usage: $0 database_backup <RUNNER> <SCHEMA> <THRESHOLD>"
      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter Runner (Example: PETER):" RUNNER
         read -p "Enter Schema (Example: STACK_TEMP):" SCHEMA
         read -p "Enter Threshold (Example: 80):" THRESHOLD
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
#Check that exactly 7 arguments were passed — function name plus 6 required parameters
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
#Check that exactly 7 arguments were passed — function name plus 6 required parameters
   if [[ $# -eq 7 ]]
   then
      RUNNER="$2"
      SOURCE_DB="$3"
      TARGET_DB="$4"
      SCHEMA="$5"
      DIRECTORY="$6"
      THRESHOLD="$7"
      local_migration
      break
   else
      echo "ERROR: Incorrect number of arguments"
      echo "Usage $0 <local_migration <RUNNER> <SOURCE_DB> <TARGET_DB> <SCHEMA> <DIRECTORY> <THRESHOLD>"
      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter Runner (Example: PETER):" RUNNER
         read -p "Enter Source DB (Example: APEXDB):" SOURCE_DB
         read -p "Enter Target DB (Example: SAMD):" TARGET_DB
         read -p "Enter Schema (Example: STACK_TEMP):" SCHEMA
         read -p "Enter Directory (Example: DATA_PUMP_DIR):" DIRECTORY
         read -p "Enter Threshold (Example: 80):" THRESHOLD
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
#Check that exactly 2 arguments were passed — function name plus threshold
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
#Check that exactly 4 arguments were passed — function name plus 3 required parameters
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
#Check that exactly 6 arguments were passed — function name plus 5 required parameters
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
#^^ uppercases CONFIRM so both y and Y are accepted
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

   "cloud_database_migration")
   echo "Workflow: Cloud Data Migration"
#Check that exactly 11 arguments were passed — function name plus 10 required parameters
   if [[ $# -eq 11 ]]
   then
      SQL_STATEMENT="$2"
      RUNNER="$3"
      SOURCE_DB="$4"
      CLOUD_DB="$5"
      CLOUD_USER="$6"
      CLOUD_SERVER="$7"
      CLOUD_DATAPUMP_DIR="$8"
      CLOUD_PRACTICEDIR="$9"
      DIRECTORY="${10}"
      THRESHOLD="${11}"
      cloud_database_migration
      break
   else
      echo "Usage: $0 cloud_database_migration \"<SQL_STATEMENT>\" <RUNNER> <SOURCE_DB> <CLOUD_DB> <CLOUD_USER> <CLOUD_SERVER> <CLOUD_DATAPUMP_DIR> <CLOUD_PRACTICEDIR> <DIRECTORY> <THRESHOLD>"
      echo "Example: $0 cloud_database_migration \"select username from dba_users where username like '%STACK_TEMP%';\" PETER APEXDB HERCDB oracle ec2-54-152-190-208.compute-1.amazonaws.com /backup/AWSJAN26/DATAPUMP/HERC /backup/AWSJAN26/practicedir_pet_jan26 DATA_PUMP_DIR 80"
      if ask_for_help "Hello! Do you need help entering the required values?"
      then
         read -p "Enter SQL Statement:" SQL_STATEMENT
         read -p "Enter Runner (Example: PETER):" RUNNER
         read -p "Enter Source DB (Example: APEXDB):" SOURCE_DB
         read -p "Enter Cloud DB (Example: HERCDB):" CLOUD_DB
         read -p "Enter Cloud User (Example: oracle):" CLOUD_USER
         read -p "Enter Cloud Server (Example: ec2-54-152-190-208.compute-1.amazonaws.com):" CLOUD_SERVER
         read -p "Enter Cloud Datapump Directory (Example: /backup/AWSJAN26/DATAPUMP/HERC):" CLOUD_DATAPUMP_DIR
         read -p "Enter Cloud Practice Directory (Example: /backup/AWSJAN26/practicedir_pet_jan26):" CLOUD_PRACTICEDIR
         read -p "Enter Oracle Directory Name (Example: DATA_PUMP_DIR):" DIRECTORY
         read -p "Enter Threshold (Example: 80):" THRESHOLD
         cloud_database_migration
         break
      else
         usage
         exit 1
      fi
   fi
   ;;

   "AWS")
   echo "Workflow: AWS Cloud Operations"
   ;;

   *)
   echo "ERROR: The function is incorrect '${FUNCTION}'."
#Display the select menu — lets the user pick a valid function instead of re-running the script
   select MENU_FUNCTION in ${FUNCTION_OPTIONS}
   do
      if [[ "${MENU_FUNCTION}" == "quit" ]]
      then
         echo "Try again...terminating"
         exit 1
      elif [[ -n "${MENU_FUNCTION}" ]]
      then
#Set FUNCTION to the selection and break back into the case statement to re-route
         FUNCTION="${MENU_FUNCTION}"
         break
      else
         echo "Invalid selection. Please choose a correct menu option."
      fi
   done
   ;;
esac
done

