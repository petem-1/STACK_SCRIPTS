#!/usr/bin/python

# module declaration
import os
import sys

# function declaration
def myfunc1(a,b):
	print("My first name is {}. My last name is {}.".format(a,b))
	if a=="Peter":
		print ("The right person is running my code.")
	else:
		print("The wrong person is running my code.")
		answer=input("Do you need my help running my code? ")
		if answer=="yes":
			print("I'll help you in the process of running my code.")	

# main
if __name__=="__main__":
	fname=sys.argv[1]
	lname=sys.argv[2]
	myfunc1(fname,lname)


