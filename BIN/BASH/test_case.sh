#!/bin/bash

arg="aws"

case ${arg} in
aws)

	echo "${arg} is aws"
	;;
*)
	echo "${arg} was not selected."
	;;
esac
