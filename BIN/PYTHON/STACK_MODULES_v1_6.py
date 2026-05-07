#!/usr/bin/python

#Module Declaration
import shutil
import subprocess
import os
#Function Declaration
def copy_file(src,dst):
	print ("Copying file {} into directory {}.".format(src,dst))

	if not os.path.isfile(src):
		print ("ERROR: File {} does not exist.".format(src))
		exit()

	shutil.copy(src, dst)
	print ("SUCCESS: File {} has successfully been copied to directory {}.".format(src,dst))

def copy_directory(src,runner):
	print ("Copying directory {} to runner directory {}.".format(src,runner))
	if not os.path.isdir(src):
		print ("ERROR: Directory {} does not exist.".format(src))
		exit()

	shutil.copytree(src, runner)
	print ("SUCCESS: Directory {} has successfully been copied to runner directory {}.".format(src,runner))

def database_backup(schema,runner):
	print ("Backing up schema {} for runner {}.".format(schema,runner))
	par_file = "{}.par".format(runner)
	print ("Building {}.".format(par_file))
	par_contents="""userid=/@peter_apexdb
	directory=DATA_PUMP_DIR
	dumpfile={}_{}.dmp
	logfile={}_{}.log
	schemas={}""".format(schema,runner,schema,runner,schema)
	fh=open(par_file, "w")
	fh.write(par_contents)
	fh.close()
	result = subprocess.run(["bash", "-c", "source /home/oracle/scripts/oracle_env_APEXDB.sh && expdp parfile={}".format(par_file)])
	if result.returncode != 0:
		print("ERROR: Database backup failed.")
		exit()
	print ("SUCCESS: Database backed up")