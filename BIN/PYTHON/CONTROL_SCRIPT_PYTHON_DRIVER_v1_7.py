#!/usr/bin/python

import STACK_MODULES_v1_7 as SM1_7
import os
import sys

command_line_args=len(sys.argv) - 1
#variable declaration
if sys.argv[1] == "copy_file":
	if command_line_args != 3:
		print("USAGE: copy_file src dst")
		answer = input("Do you need help? (y/n): ")
		if answer == "y":
			src = input("Enter source file: ")
			dst = input("Enter destination directory: ")
			SM1_7.copy_file(src, dst)
		else:
			exit()
	else:
		src = sys.argv[2]
		dst = sys.argv[3]
		SM1_7.copy_file(src,dst)

elif sys.argv[1] == "copy_directory":
	if command_line_args != 3:
		print("USAGE: copy_directory src runner")
		answer = input("Do you need help? (y/n): ")
		if answer == "y":
			src = input("Enter source directory: ")
			runner = input("Enter destination runner: ")
			SM1_7.copy_directory(src,runner)
		else:
			exit()
	else:
		src = sys.argv[2]
		runner = sys.argv[3]
		SM1_7.copy_directory(src,runner)
		print("Copy function called successfully")

elif sys.argv[1] == "database_backup":
	if command_line_args != 3:
		print("USAGE: database_backup schema runner")
		answer = input("Do you need help? (y/n): ")
		if answer == "y":
			schema = input("Enter schema: ")
			runner = input("Enter runner: ")
			SM1_7.database_backup(schema,runner)
		else:
			exit()
	else:
		schema = sys.argv[2]
		runner = sys.argv[3]
		SM1_7.database_backup(schema,runner)
		print("Database backup function called successfully")
