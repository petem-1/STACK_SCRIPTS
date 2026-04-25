#!/usr/bin/python

#Module Declaration
import shutil
import sys
#Function Declaration
def copy_file(src,dst):
	print ("Copying file {} into directory {}.".format(src,dst))

	shutil.copy(src, dst)
	print ("SUCCESS: File {} has successfully been copied to directory {}.".format(src,dst))

def copy_directory(src,runner):
	print ("Copying directory {} to runner directory {}.".format(src,runner))

	shutil.copytree(src, runner)
	print ("SUCCESS: Directory {} has successfully been copied to runner directory {}.".format(src,runner))
#main
if __name__=="__main__":
	if sys.argv[1] == "copy_file":
		src = sys.argv[2]
		dst = sys.argv[3]
		copy_file(src,dst)

	elif sys.argv[1] == "copy_directory":
		src = sys.argv[2]
		runner = sys.argv[3]
		copy_directory(src,runner)
