#!/bin/bash
DBCHECKLOG=/home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/dbcheck.log

if ( ps -ef | grep pmon | grep APEXDB )
then 
	echo "The APEXDB Database Instance is up and running."
else
	echo "The APEXDB Database IS DOWN"
fi
#Setting Database Environment for APEXDB
source /home/oracle/scripts/oracle_env_APEXDB.sh

#Check Database open status
sqlplus stack_temp/stackinc<<EOF>${DBCHECKLOG}
set echo on feedback on term on pagesize 0
select status from v\$instance;
EOF

#Checking file for open status
if ( grep "OPEN" 	${DBCHECKLOG} )
then
	echo "The Database is open and ready for backup"
else
	echo "The Database is not open and backup cannot occur"
	exit 1
fi

#Creating Backup Config File
echo "userid=stack_temp">>backup_peter.par
echo "schemas=STACK_TEMP">>backup_peter.par

