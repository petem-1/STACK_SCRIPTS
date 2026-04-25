#!/bin/bash
# Version 1.7
# DESCRIPTION: Multipurpose controller script using case logic

TS=$(date "+%m%d%Y%H%M%S")
TDS=$(date "+%m%d%Y")

# --- Section 1: Input Validation ---
# Checks for the 4 required arguments: command, source, destination, and runner
if [ $# -ne 4 ]; then
    echo "ERROR: Incorrect number of arguments."
    echo "Usage: $0 <command> <source_file> <backup_dir> <runner_name>"
    exit 1
fi

COMMAND=$1
SRC=$2
DST=$3
RUNNER=$4

# --- Section 2: Function Definitions ---
# Logic for file and directory backups
BACKUP_F_D() {
    BACKUP_PATH="${DST}/${RUNNER}/${TS}"
    echo "Creating directory: ${BACKUP_PATH}"
    mkdir -p "${BACKUP_PATH}"
    
    if [[ -d ${SRC} ]]; then
        cp -rf "${SRC}" "${BACKUP_PATH}"
    else
        cp -f "${SRC}" "${BACKUP_PATH}"
    fi
}

# --- Section 3: Multipurpose Command Logic ---
# This case statement routes the script to the correct specific workflow
case ${COMMAND} in
    "backup_f_d")
        echo "Workflow: File/Directory Backup"
        # Utilization check inside the case
        if [ $? -eq 0 ]; then
            BACKUP_F_D
        fi
        ;;

    "database_backup")
        echo "Workflow: Database Backup"
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
        echo "ERROR: Invalid function '${COMMAND}' entered."
        exit 1
        ;;
esac

# --- Section 4: Post-Execution Validation ---
echo "Listing files in backup directory..."
ls -R "${DST}/${RUNNER}"

