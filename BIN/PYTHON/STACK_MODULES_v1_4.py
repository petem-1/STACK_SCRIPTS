#!/usr/bin/python

#Module Declaration
import shutil
#Function Declaration
def copy_file(src,dst):
	print ("Copying file {} into directory {}.".format(src,dst))

	shutil.copy(src, dst)
	print ("SUCCESS: File {} has successfully been copied to directory {}.".format(src,dst))

def copy_directory(src,runner):
	print ("Copying directory {} to runner directory {}.".format(src,runner))

	shutil.copytree(src, runner)
	print ("SUCCESS: Directory {} has successfully been copied to runner directory {}.".format(src,runner))

