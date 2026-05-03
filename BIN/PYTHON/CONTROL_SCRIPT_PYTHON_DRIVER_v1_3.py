#!/usr/bin/python

import STACK_MODULES_v1_3 as SM1_3
import os
import sys

command_line_args=len(sys.argv) - 1
if command_line_args<3:
	print("This script has {} command line args.".format(command_line_args))
	print("Incorrect amount of command line arguments, exiting....")
	exit()

#variable declaration
if sys.argv[1] == "copy_file":
	src = sys.argv[2]
	dst = sys.argv[3]
	SM1_3.copy_file(src,dst)

elif sys.argv[1] == "copy_directory":
	src = sys.argv[2]
	runner = sys.argv[3]
	SM1_3.copy_directory(src,runner)
	print("Copy function called successfully")
	print("Hello World")