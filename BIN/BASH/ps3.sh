#!/bin/bash

servers="serv1 serv2 serv3 serv4 quit"
PS3="Select a server: "

select server in ${servers}
do
	if [[ ${server} == "quit" ]]
	then 
		break
	fi
	echo "server name is ${server}"
done

echo "Program ending"
