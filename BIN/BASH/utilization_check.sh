#!/bin/bash

fname=$1
lname=$2

echo "The number of command-line arguments in this script is: $#"

if [[ $# != 2 ]]
then
	echo "You did not run this script the right way. Run the script like below:
UTITLITY: utilization_check.sh arg1 arg2
e.g. utilization_check.sh Peter Molina"
fi
