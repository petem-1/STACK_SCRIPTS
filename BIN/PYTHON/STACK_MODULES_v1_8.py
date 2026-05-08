#!/usr/bin/python

#Module Declaration
import shutil
import subprocess
import os
import gzip
#Import just the datetime class from the datetime module so we can call datetime.now() directly
from datetime import datetime

#Function Declaration

#copy_file() - copies a single file from a source path to a destination directory
def copy_file(src,dst):
	#Confirm what file is being copied and where it is going
	print ("Copying file {} into directory {}.".format(src,dst))
	#Verify the source file exists before attempting the copy — stops the script with a clear message if missing
	if not os.path.isfile(src):
		print ("ERROR: File {} does not exist.".format(src))
		exit()
	#Copy the file to the destination directory
	shutil.copy(src, dst)
	print ("SUCCESS: File {} has successfully been copied to directory {}.".format(src,dst))

#copy_directory() - copies an entire directory from a source path to a destination runner directory
def copy_directory(src,runner):
	#Confirm what directory is being copied and where it is going
	print ("Copying directory {} to runner directory {}.".format(src,runner))
	#Verify the source directory exists before attempting the copy — stops the script with a clear message if missing
	if not os.path.isdir(src):
		print ("ERROR: Directory {} does not exist.".format(src))
		exit()
	#Copy the entire directory tree to the runner destination
	shutil.copytree(src, runner)
	print ("SUCCESS: Directory {} has successfully been copied to runner directory {}.".format(src,runner))

#database_backup() - performs a Data Pump export for a schema using a PAR file
def database_backup(schema,runner):
	#Confirm which schema is being backed up and who is running it
	print ("Backing up schema {} for runner {}.".format(schema,runner))
	#Build the PAR filename using the runner name
	par_file = "{}.par".format(runner)
	print ("Building {}.".format(par_file))
	#Build the PAR file contents — each line sets a parameter that expdp reads at runtime
	par_contents="""userid=/@peter_apexdb
	directory=DATA_PUMP_DIR
	dumpfile={}_{}.dmp
	logfile={}_{}.log
	schemas={}""".format(schema,runner,schema,runner,schema)
	#Open the PAR file for writing and write the contents to disk
	fh=open(par_file, "w")
	fh.write(par_contents)
	#Always close the file after writing — ensures all data is flushed to disk before expdp reads it
	fh.close()
	#Source the Oracle environment to set ORACLE_HOME and PATH, then run expdp using the PAR file
	result=subprocess.run(["bash", "-c", "source /home/oracle/scripts/oracle_env_APEXDB.sh && expdp parfile={}".format(par_file)])
	#Check the exit code — a non-zero return code means expdp failed
	if result.returncode != 0:
		print("ERROR: Database backup failed.")
		exit()
	print ("SUCCESS: Database backed up")

#G_Zip() - gzips or unzips a file based on its extension
def G_Zip(file_path):
	#Check the file extension — if it ends in .gz it is already compressed so unzip it
	if file_path.endswith(".gz"):
		print("Unzipping {}.".format(file_path))
		#Strip the .gz extension to build the output filename for the unzipped file
		output_path=file_path.replace(".gz", "")
		#Open the gzipped file for reading in binary mode and write decompressed data to the output file
		with gzip.open(file_path, 'rb') as f_in:
			with open(output_path, 'wb') as f_out:
				#Copy the decompressed contents from the gz file into the output file
				shutil.copyfileobj(f_in, f_out)
		print("SUCCESS: Unzipped to {}.".format(output_path))
	else:
		print("Gzipping {}.".format(file_path))
		#Build a timestamp to include in the output filename — ensures each gzip run creates a unique file
		ts=datetime.now().strftime("%m-%d-%Y_%H-%M-%S")
		#Build the output filename by appending the timestamp and .gz extension to the original path
		output_path="{}_{}.gz".format(file_path, ts)
		#Open the original file for reading in binary mode and write compressed data to the output gz file
		with open(file_path, 'rb') as f_in:
			with gzip.open(output_path, 'wb') as f_out:
				#Copy the contents of the original file into the gzip file — gzip handles the compression
				shutil.copyfileobj(f_in, f_out)
		print("SUCCESS: Gzipped {}.".format(output_path))
