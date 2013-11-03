#!/usr/bin/env bash
#
# @author: Janusz Kowalczyk
# @date:   2013-09-25
# @description:
#       This script works as a temporary solution to an issue in Jenkins Plot Plugin
#       https://issues.jenkins-ci.org/browse/JENKINS-4934
# @usage: 
#       example 1: delete data from build #1
#       ./rmbuilds.sh 1
#       example 2: delete data from builds #4,5,7,20
#       ./rmbuilds.sh 4 5 7 20

die() { echo "$@" 1>&2 ; exit 1; }

[ $# -gt 1 ] || die "this script requirers at least build number!"

# some global variables
sed_reg_pattern=''
sed_table_pattern=''
semicolon=""
DATETIME=$(date +"%Y-%m-%d_-_%H-%M")

# get the first argument
# will use it to check when we should add "|" (pipe) to the pattern
first=$1

# generate SED line matching patterns based on the number of passed arguments
for arg in $@ ; do
    # don't add semicolon before first pattern
    # of if there's only one argument passed
    if [ "${arg}" = "${first}" ] ; then
        semicolon=""
    else
        semicolon=";"
    fi;
    sed_reg_pattern=${sed_reg_pattern}"${semicolon}/,\"${arg}\",/d"
    sed_table_pattern=${sed_table_pattern}"${semicolon}/^\"${arg}\",/d"
done;

echo "Generated SED pattern from the provided parameters: '${sed_reg_pattern}'"
echo "Generated SED pattern from the provided parameters for files starting with table: '${sed_table_pattern}'"

# iterate through all csv files which filename doesn't start with "table_"
for f in `find * -maxdepth 1 -name "*.csv" | grep -v "^table"` ; do
    echo "Processing file: ${f}"
    # use SED to remove all matching lines
    sed -i.bak.${DATETIME} "${sed_reg_pattern}" ${f}
done;

# iterate through all csv files which filename starts with "table_"
for f in `find * -maxdepth 1 -name "*.csv" | grep "^table"` ; do
    echo "Processing file: ${f}"
    # use SED to remove all matching lines
    sed -i.bak.${DATETIME} "${sed_table_pattern}" ${f}
done;
