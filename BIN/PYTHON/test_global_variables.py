#!/usr/bin/python


x="awesome"
y=10
print("The datatype for x is %s "%(type(x)))
print("The datatype for y is %s "%(type(y)))
#function declaration
def test_global_var():
	global x
	x="Brilliant"
	print("Python is %s"%(x))

#Function call
test_global_var()

print("Python is %s"%(x))
