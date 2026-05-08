#!/usr/bin/python

import STACK_MODULES_v1_8 as SM1_8
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
			SM1_8.copy_file(src, dst)
		else:
			exit()
	else:
		#Read the values directly from the command line arguments
		src = sys.argv[2]
		dst = sys.argv[3]
		SM1_8.copy_file(src,dst)

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
			SM1_8.copy_directory(src,runner)
		else:
			exit()
	else:
		#Read the values directly from the command line arguments
		src = sys.argv[2]
		runner = sys.argv[3]
		SM1_8.copy_directory(src,runner)
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
			SM1_8.database_backup(schema,runner)
		else:
			exit()
	else:
		#Read the values directly from the command line arguments
		schema = sys.argv[2]
		runner = sys.argv[3]
		SM1_8.database_backup(schema,runner)
		print("Database backup function called successfully")

elif sys.argv[1] == "G_Zip":
	#Check that exactly 2 arguments were passed — function keyword plus file_path
	if command_line_args != 2:
		print("USAGE: G_Zip file_path")
		#Ask the user if they need help entering the value manually
		answer = input("Do you need help? (y/n): ")
		if answer == "y":
			#Prompt the user for the absolute path of the file to gzip or unzip
			filename = input("Enter filename: ")
			SM1_8.G_Zipp(filename)
		else:
			exit()
	else:
		#Read the file path directly from the command line argument
		filename = sys.argv[2]
		SM1_8.G_Zip(filename)
		print("G_Zip function called successfully")