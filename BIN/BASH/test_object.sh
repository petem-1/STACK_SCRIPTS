#!/bin/bash


object=$1

if {{ -d ${object} }}
then
	echo " ${object} is a directory"
else
	echo " ${object} is a file"
fi
