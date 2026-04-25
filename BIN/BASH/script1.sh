#!/bin/bash

#variables
name=$1

#Main Body

echo "This is my first script"
touch file1.txt
cp file1.txt file2.txt
ls -ltr

mkdir backup
mv file1.txt file2.txt backup
