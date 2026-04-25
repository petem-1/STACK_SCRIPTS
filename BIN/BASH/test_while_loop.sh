#!/bin/bash


<<comment counter=1

while (( ${counter} <= 10 ))
do
	echo ${counter}
	#Increment Counter
	(( counter++ ))
done

echo "All done."

schemas="schema1 schema2 schema3 schema4"

for schema in ${schemas}
do
	echo "This is a for loop."
	echo "schema name is: ${schema}"
done
comment

schemas="schema1 schema2 schema3 schema4"

while read schema name age
do
	echo "This is a while loop"
	echo "Schema name is ${schema}, first-name is: ${name}, and age is: ${age}"
done < /home/oracle/scripts/practicedir_pet_jan26/BIN/BASH/schemas.lst
