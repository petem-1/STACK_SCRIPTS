#!/bin/bash


FNAME=$1
LNAME=$2

echo "The number of command-line arguments in this script is: $#"

if [[ $# != 2 ]]
then
        echo "You did not run this script the right way. Run the script like below:
UTITLITY: utilization_check.sh arg1 arg2
e.g. utilization_check.sh Peter Molina"

read -p "Do you need help? : " INPUT
	if [[ ${INPUT} == 'y' ]]
	then
		echo "You opted for help..."
		read -p "Enter value for fname: " FNAME
		read -p "Enter value for lname: " LNAME
	fi
fi


echo "fname entered is: {$FNAME}"
echo "fname entered is: {$LNAME}"

