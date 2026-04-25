#!/usr/bin/python

#Module Declaration
import shutil

#Function Declaration
def copy_file():
	src = "test.txt"
	dst = "testdir"
	print ("Copying file {} into directory {}.".format(src,dst))

	shutil.copy(src, dst)

def copy_directory():
	src = "testdir" 
	runner = "petedir"
	print ("Copying directory {} to runner directory {}.".format(src,runner))

	shutil.copytree(src, runner)

#main
copy_file()
copy_directory()
	
