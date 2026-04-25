#!/bin/bash

#Add Function
ADD(){
	expr ${NUM1} + ${NUM2}
	if [ $? -ne 0 ]
	then
		echo "CRITICAL ERROR: Addition operation failed."
		exit 1
	fi
}

#Subtract Function
SUB(){
	expr ${NUM1} - ${NUM2}
	if [ $? -ne 0 ]
	then
		echo "CRITICAL ERROR: Subtraction operation failed."
		exit 1
	fi
}

#Multiply Function
MUL(){
	expr ${NUM1} \* ${NUM2}
	if [ $? -ne 0 ]
	then
		echo "CRITICAL ERROR: Multiplication operation failed."
		exit 1
	fi
}

#Division Function
DIV(){
	expr ${NUM1} / ${NUM2}
	if [ $? -ne ]
	then
		echo "CRITICAL ERROR: Division operation failed"
		exit 1
	fi
}

#Utilization Definition 
ask_for_help(){
	read -p "$1 (y/n):" ANSWER
	[[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]
}

usage(){
	echo "Usage:"
	echo " $0 <operation> <num1> <num2>"
	echo ""
	echo "Operations: add, sub, mul, div"

}

#Utilization Check
	if [[ $# -ne 3 ]]
	then
		echo "The number of command line arguments is: $#"


		if ask_for_help "Hello! Do you need help entering the required values?"
		then
			read -p "Enter Operation (add, sub, mul, div):" OPERATION
			read -p "Enter first number:" NUM1
			read -p "Enter second number:" NUM2
		else
			usage
			exit 1
		fi
	else
		OPERATION="$1" #Variables
		NUM1="$2"
		NUM2="$3"
	fi	

#Case Statement
case ${OPERATION} in
	"add")
	#RESULT=$(( NUM1 + NUM2 ))
	result="$(ADD ${NUM1} ${NUM2})"
	echo "Addition is: ${result}"
	;;

	"sub")
	result="$(SUB ${NUM1} ${NUM2})"	
	echo "Subtraction is: ${result}"
	;;

	"mul")
	result="$(MUL ${NUM1} ${NUM2})"
	echo "Multiplication is: ${result}"
	
	;;

	"div")
	result="$(DIV ${NUM1} ${NUM2})"
	echo "Division is: ${result}"
	;;
*)
	echo "ERROR: Invalid function '${OPERATION}' entered"
	usage
	exit 1
 ;;
esac
