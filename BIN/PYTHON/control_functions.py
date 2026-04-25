#!/usr/bin/python

import python_functions as pf
import os
import sys

command_line_args=len(sys.argv) - 1
if command_line_args<2:
	print("This script has %s command line args."%(command_line_args))
	print("Incorrect amount of command line arguments, exiting....")
	exit()

#variable declaration
fname,lname=sys.argv[1],sys.argv[2]

pf.myfunc1(fname,lname)

