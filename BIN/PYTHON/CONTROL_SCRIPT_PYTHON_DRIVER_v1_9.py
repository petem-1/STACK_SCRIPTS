#!/usr/bin/python

import STACK_MODULES_v1_9 as SM1_9
import os
import sys

#Count the number of arguments the user passed in — subtract 1 to exclude the script name
command_line_args=len(sys.argv) - 1

#Route execution to the correct function based on the first argument typed by the user
if sys.argv[1] == "copy_file":
	#Check that exactly 3 arguments were passed — function keyword plus src and dst
	if command_line_args != 3:
		print("USAGE: copy_file src dst")
		#Ask the user if they need help entering the values manually
		answer = input("Do you need help? (y/n): ")
		if answer == "y":
			#Prompt the user for each required value one at a time
			src = input("Enter source file: ")
			dst = input("Enter destination directory: ")
			SM1_9.copy_file(src, dst)
		else:
			exit()
	else:
		#Read the values directly from the command line arguments
		src = sys.argv[2]
		dst = sys.argv[3]
		SM1_9.copy_file(src,dst)

elif sys.argv[1] == "copy_directory":
	#Check that exactly 3 arguments were passed — function keyword plus src and runner
	if command_line_args != 3:
		print("USAGE: copy_directory src runner")
		#Ask the user if they need help entering the values manually
		answer = input("Do you need help? (y/n): ")
		if answer == "y":
			#Prompt the user for each required value one at a time
			src = input("Enter source directory: ")
			runner = input("Enter destination runner: ")
			SM1_9.copy_directory(src,runner)
		else:
			exit()
	else:
		#Read the values directly from the command line arguments
		src = sys.argv[2]
		runner = sys.argv[3]
		SM1_9.copy_directory(src,runner)
		print("Copy function called successfully")

elif sys.argv[1] == "database_backup":
	#Check that exactly 3 arguments were passed — function keyword plus schema and runner
	if command_line_args != 3:
		print("USAGE: database_backup schema runner")
		#Ask the user if they need help entering the values manually
		answer = input("Do you need help? (y/n): ")
		if answer == "y":
			#Prompt the user for each required value one at a time
			schema = input("Enter schema: ")
			runner = input("Enter runner: ")
			SM1_9.database_backup(schema,runner)
		else:
			exit()
	else:
		#Read the values directly from the command line arguments
		schema = sys.argv[2]
		runner = sys.argv[3]
		SM1_9.database_backup(schema,runner)
		print("Database backup function called successfully")

elif sys.argv[1] == "database_import":
	#Check that exactly 6 arguments were passed — function keyword plus runner, db_name, schema, directory, dumpfile
	if command_line_args != 6:
		print("USAGE: database_import runner db_name schema directory dumpfile")
		#Ask the user if they need help entering the values manually
		answer=input("Do you need help? (y/n): ")
		if answer == "y":
			#Prompt the user for each required value one at a time
			runner = input("Enter runner:")
			db_name = input("Enter Database name:")
			schema = input("Enter schema:")
			directory = input("Enter Directory:")
			dumpfile = input("Enter Dumpfile name:")
			SM1_9.database_import(runner, db_name, schema, directory, dumpfile)
		else:
			exit()
	else:
		#Read the values directly from the command line arguments
		runner = sys.argv[2]
		db_name = sys.argv[3]
		schema = sys.argv[4]
		directory = sys.argv[5]
		dumpfile = sys.argv[6]
		SM1_9.database_import(runner, db_name, schema, directory, dumpfile)
		print("Database import function called successfully")



elif sys.argv[1] == "G_Zip":
	#Check that exactly 2 arguments were passed — function keyword plus file_path
	if command_line_args != 2:
		print("USAGE: G_Zip file_path")
		#Ask the user if they need help entering the value manually
		answer = input("Do you need help? (y/n): ")
		if answer == "y":
			#Prompt the user for the absolute path of the file to gzip or unzip
			filename = input("Enter filename: ")
			SM1_9.G_Zip(filename)
		else:
			exit()
	else:
		#Read the file path directly from the command line argument
		filename = sys.argv[2]
		SM1_9.G_Zip(filename)
		print("G_Zip function called successfully")