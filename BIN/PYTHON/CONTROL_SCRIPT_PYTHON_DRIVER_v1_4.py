
#!/usr/bin/python

import STACK_MODULES_v1_4 as SM1_4
import os
import sys

command_line_args=len(sys.argv) - 1
#variable declaration
if sys.argv[1] == "copy_file":
	if command_line_args != 3:
		print("USAGE: copy_file src dst")
		exit()
	src = sys.argv[2]
	dst = sys.argv[3]
	SM1_4.copy_file(src,dst)

elif sys.argv[1] == "copy_directory":
	if command_line_args != 3:
		print("USAGE: copy_directory src runner")
		exit()
	src = sys.argv[2]
	runner = sys.argv[3]
	SM1_4.copy_directory(src,runner)
	print("Copy function called successfully")