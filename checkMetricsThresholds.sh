#!/usr/bin/env bash
#
################################################################################
# Author: Janusz Kowalczyk
# Created: 2013-08-15
# Updated: 2013-08-16
#
# DESCRIPTION:
# This script checks if the error rate meets acceptable threshold.
# It reads the value of current error rate from the last line of the 
# JMeter's aggregate CSV report. Such report can be generated using:
# http://jmeter-plugins.org/wiki/JMeterPluginsCMD/#Plugin-Type-Classes
# 
# If error rate is higher or equal to the acceptable threshold, then
# it sets the Jenkins build as unstable
# 
# USAGE:
# ex. 1)
# ./checkMetricsThresholds.sh
# Will load default threshold values from ./defaultPerformanceThresholds.csv
# and will try to compare them with the results from ./aggregate.csv
#
# ex. 2)
# cfgAggregateReportFile="projects/drKingShultz/aggregate.csv" ./checkMetricsThresholds.sh
# Will load default threshold values from ./defaultPerformanceThresholds.csv
# and will try to compare them with the results from projects/drKingShultz/aggregate.csv
#
# ex. 3)
# cfgThresholds="projects/drKingShultz/cfg/thresholds.csv" cfgAggregateReportFile="projects/drKingShultz/aggregate.csv" ./checkMetricsThresholds.sh
# Will load threshold values from projects/drKingShultz/cfg/thresholds.csv
# and will try to compare them with the results from projects/drKingShultz/aggregate.csv
#
# ex. 4)
# cfgFailureThresholdAvg=1 cfgFailureThresholdMin=2 cfgFailureThresholdMax=3 cfgFailureThresholdMed=4 cfgFailureThreshold90p=5 cfgFailureThresholdErr=6 cfgUnstableThresholdAvg=7 cfgUnstableThresholdMin=8 cfgUnstableThresholdMax=9 cfgUnstableThresholdMed=10 cfgUnstableThreshold90p=11 cfgUnstableThresholdErr=12 cfgAggregateReportFile="projects/drKingShultz/aggregate.csv" ./checkMetricsThresholds.sh
# Will use threshold values provided on run-time as variables
# and will try to compare them with the results from projects/drKingShultz/aggregate.csv
#
# ex. 5)
# cfgFailureThresholdAvg=1 cfgFailureThresholdMin=2 cfgFailureThresholdMax=3 cfgFailureThresholdMed=4 cfgFailureThreshold90p=5 cfgFailureThresholdErr=6 cfgUnstableThresholdAvg=7 cfgUnstableThresholdMin=8 cfgUnstableThresholdMax=9 cfgUnstableThresholdMed=10 cfgUnstableThreshold90p=11 cfgUnstableThresholdErr=12 cfgThresholds="projects/drKingShultz/cfg/thresholds.csv" cfgAggregateReportFile="projects/drKingShultz/aggregate.csv" ./checkMetricsThresholds.sh
# Will use threshold values provided on run-time as variables, despite the fact that
# cfgThresholds="projects/drKingShultz/cfg/thresholds.csv" was provided
# and will try to compare them with the results from projects/drKingShultz/aggregate.csv
#
# ex. 6)
# JENKINS_URL=http://you-jenkins-url:8080 ./checkMetricsThresholds.sh
# Will use cutom Jenkins URL to download jenkins-cli.jar and mark builds
# Will load default threshold values from ./defaultPerformanceThresholds.csv
# and will try to compare them with the results from ./aggregate.csv
#
# 
# An example CSV file that contains results from an aggregate report:
# sampler_label,count,average,median,90%_line,min,max,error%,rate,bandwidth
# Get,1182,31,30,39,21,162,0.0,121.28052534373077,2701.80695124923
# TOTAL,1182,31,30,39,21,162,0.0,121.28052534373077,2701.80695124923
#
# 
# An example CSV file with all the thresholds defined:
# cfgFailureThresholdAvg,cfgFailureThresholdMin,cfgFailureThresholdMax,cfgFailureThresholdMed,cfgFailureThreshold90p,cfgFailureThresholdErr,cfgUnstableThresholdAvg,cfgUnstableThresholdMin,cfgUnstableThresholdMax,cfgUnstableThresholdMed,cfgUnstableThreshold90p,cfgUnstableThresholdErr
# 40,-1,700,50,50,0.23,30,-1,500,30,30,0.2
#
# or with shorter column names:
# (actually column names are not important as we load only values from the second line)
# FTAvg   ,FTMin  ,FTMax  ,FTMed  ,FT90p  ,FTErr  ,UTAvg  ,UTMin  ,UTMax  ,UTMed  ,UT90p  ,UTErr  
# 45  ,-1 ,200    ,55 ,50 ,0.23   ,30 ,-1 ,100    ,35 ,40 ,0.2    
#
################################################################################


# load an external script with bunch of helpers
. helpers.sh


################################################################################
# Steps
################################################################################
#-1 archive thresholds file
#0 check if csv report exists
#1 check if jenkins-cli.jar exists, and try to download it if it's not there
#2 load settings from the cfgThresholds file if present 
#3 assign default values for remaining variables
#4 variable sanity check (whether they make sense)
#5 extract all the metrics from the report file 
#5 verify all metrics
#


# Globals
cfgThresholds=${cfgThresholds-defaultPerformanceThresholds.csv}
DEBUG=${DEBUG-false}
JENKINS_URL="${JENKINS_URL-http://localhost:8080}"
cfgAggregateReportFile="${cfgAggregateReportFile-aggregate.csv}"
# if an environment variable ${resultsDir} was configured ie. on Jenkins then
# this will pick it up, but if not then it such file will be archive in /tmp
# which is a safe place to save file if we don't know where exactly we should keep it :)
cfgResultsDir=${resultsDir-/tmp} 
cfgArchiveThresholdsFile=${cfgArchiveThresholdsFile-true}

# Two global flags upon which build result depends. 
# if any of them is true, then build status will be set accordingly
FAILED=false
UNSTABLE=false

################################################################################
# helper functions
################################################################################
# author: Janusz Kowalczyk
# created: 2013-08-19
# Description:
# checks whether two values meets the greater or equal (x>=y) condition
# if current value fals into one of the thresholds
# then build is set as unstable or failed
# Example usage:
# avg=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f3`                           
# verifyThreshold ${avg} ${cfgUnstableThresholdAvg} ${cfgFailureThresholdAvg} "Average response time"
function verifyThreshold(){
    local leftOperand=${1-}
    local unstalbleThreshold=${2-}
    local failedThreshold=${3-}
    local label="${4-Default operand name}"

    # check if operand's value start with hyphen '-'
    # if so, exit from the function
    #if [[ "${unstalbleThreshold}" =~ ^- ]] || [[ "${failedThreshold}" =~ ^- ]]; then
    if [[ "${unstalbleThreshold}" =~ ^- ]] || [[ "${failedThreshold}" =~ ^- ]] || [[ -z "${unstalbleThreshold}" ]] || [[ -z "${failedThreshold}" ]]; then
        cLog "Skipping the check for '${label}' as one of the configured thresholds is -1" 
        return 0
    fi

    # if compared value is in scientific notation then convert it to a form
    # that BC understands :) leaves the value unchanged otherwise
    # src: http://stackoverflow.com/a/12882612
    leftOperand=`echo ${leftOperand} | sed -e 's/[eE]+*/\\*10\\^/'`

    # mark build as unstable if the left hand operator is greater or equal to 
    # the acceptable thresholds
    if (($(echo "${leftOperand} >= ${failedThreshold}" |bc)!=0)); then
        cErr "'${label}'=${leftOperand} is greater or equal than the failure threshold: ${failedThreshold}"
        FAILED=true
        return 1
    elif (($(echo "${leftOperand} >= $unstalbleThreshold" |bc)!=0)); then
        cWarn "'${label}'=${leftOperand} is greater or equal than the unstable threshold: ${unstalbleThreshold}"
        UNSTABLE=true
        return 2
    else
        cLog "'${label}'=${leftOperand} is below all the configured thresholds [unstable=${unstalbleThreshold} and failure=${failedThreshold}]"
    fi;
}


function setBuildAsUnstable(){
    cWarn "Setting the build as unstable..."
    java -jar jenkins-cli.jar -s ${JENKINS_URL} set-build-result unstable \
        && {
            cLog "Successfully set build as UNSTABLE!!!"
            return 0
        } || {
            cErr "Failed to set the build as UNSTABLE!!!"
            return 4
        }
}

function setBuildAsFailed(){
    cErr "Setting the build as failed..."
    java -jar jenkins-cli.jar -s ${JENKINS_URL} set-build-result failed \
        && {
            cLog "Successfully set build as FAILED!!!"
            return 0
        } || {
            cErr "Failed to set the build as FAILED!!!"
            return 3
        }
}


################################################################################
# -1 - Archive thresholds file if needed
################################################################################
if ${cfgArchiveThresholdsFile} ; then
    [ -d "${cfgResultsDir}" ] \
        && {
            cp "${cfgThresholds}" "${cfgResultsDir}/thresholds.csv" \
                && {
                    cLog "Provided thresholds file '${cfgThresholds}' was archived in: '${cfgResultsDir}/thresholds.csv'"
                } || {
                    cErr "Couldn't archive '${cfgThresholds}' in: '${cfgResultsDir}'!!!"
                }
        } || {
            cWarn "Specified results directory: '${cfgResultsDir}' doesn't exist!"
        }
else
    cWarn "Archiving thresholds file is disabled!"
fi;


################################################################################
# 0 - check if the aggregateReportFile is present
################################################################################
if [ ! -e "${cfgAggregateReportFile}" ]; then
    cErr "Couldn't find aggregated report file: '${cfgAggregateReportFile}'!!!!!"
    exit 1
fi


################################################################################
# 1 - download jenkins-cli.jar to current dir if not present
################################################################################
if [ ! -e jenkins-cli.jar ]; then
    cLog "Downloading jenkins-cli.jar..."
    wget ${JENKINS_URL}/jnlpJars/jenkins-cli.jar -O jenkins-cli.jar \
        && {
            cLog "jenkins-cli.jar downlaoded successfuly" ;
        } || {
            rm jenkins-cli.jar
            cErr "Couldn't download ${JENKINS_URL}/jnlpJars/jenkins-cli.jar. Script will exit with err.code 99!!!" ;
            exit 99
        }
fi


################################################################################
# 2 - load settings from the cfgThresholds file if present and set as executable
# 
# Description:
#   This bit will read the CSV file with defined threshold values. 
#   It will load values from the second (2nd) line and assigne them to matching
#   variables.
#
# Notes:
#   Column order is important!!!!. 
#   Error thresholds have to be provided as floating-point number in a range from 0 to 1. i.e.: 22% is 0.22
#   Please refer to an example thresholds file below.
# 
# Example csv file with all the thresholds:
#   cfgFailureThresholdAvg,cfgFailureThresholdMin,cfgFailureThresholdMax,cfgFailureThresholdMed,cfgFailureThreshold90p,cfgFailureThresholdErr,cfgUnstableThresholdAvg,cfgUnstableThresholdMin,cfgUnstableThresholdMax,cfgUnstableThresholdMed,cfgUnstableThreshold90p,cfgUnstableThresholdErr
#   40,-1,700,50,50,0.23,30,-1,500,30,30,0.2
#
################################################################################
[ -e ${cfgThresholds} ] && { 
    cLog "Loading threshold values from: ${cfgThresholds}"
    OLDIFS=$IFS
    IFS=,
    let LINE_CNT=0
    while read col1 col2 col3 col4 col5 col6 col7 col8 col9 col10 col11 col12 col13 col14 col15 col16 col17 col18
    do
        ((LINE_CNT++))
        # read in only second line, which holds thresholds values
        if [ ${LINE_CNT} -eq 2 ] ; then
            cfgFailureThresholdAvg=${cfgFailureThresholdAvg-${col1}}
            cfgFailureThresholdMin=${cfgFailureThresholdMin-${col2}}
            cfgFailureThresholdMax=${cfgFailureThresholdMax-${col3}}
            cfgFailureThresholdMed=${cfgFailureThresholdMed-${col4}}
            cfgFailureThreshold90p=${cfgFailureThreshold90p-${col5}}
            cfgFailureThresholdErr=${cfgFailureThresholdErr-${col6}}
            cfgUnstableThresholdAvg=${cfgUnstableThresholdAvg-${col7}}
            cfgUnstableThresholdMin=${cfgUnstableThresholdMin-${col8}}
            cfgUnstableThresholdMax=${cfgUnstableThresholdMax-${col9}}
            cfgUnstableThresholdMed=${cfgUnstableThresholdMed-${col10}}
            cfgUnstableThreshold90p=${cfgUnstableThreshold90p-${col11}}
            cfgUnstableThresholdErr=${cfgUnstableThresholdErr-${col12}}
            cfgFailureThresholdThroughput=${cfgFailureThresholdThroughput-${col13}}
            cfgFailureThresholdBandwidth=${cfgFailureThresholdBandwidth-${col14}}
            cfgFailureThresholdStdDeviation=${cfgFailureThresholdStdDeviation-${col15}}
            cfgUnstableThresholdThroughput=${cfgUnstableThresholdThroughput-${col16}}
            cfgUnstableThresholdBandwidth=${cfgUnstableThresholdBandwidth-${col17}}
            cfgUnstableThresholdStdDeviation=${cfgUnstableThresholdStdDeviation-${col18}}
        fi;
    done < ${cfgThresholds}
    IFS=$OLDIFS
    cLog "All settings from: '${cfgThresholds}' were loaded"
}


################################################################################
# 3 - assign default values for remaining variables
################################################################################
cfgFailureThresholdAvg=${cfgFailureThresholdAvg--1}
cfgFailureThresholdMin=${cfgFailureThresholdMin--1}
cfgFailureThresholdMax=${cfgFailureThresholdMax--1}
cfgFailureThresholdMed=${cfgFailureThresholdMed--1}
cfgFailureThreshold90p=${cfgFailureThreshold90p--1}
cfgFailureThresholdErr=${cfgFailureThresholdErr--1}
cfgFailureThresholdThroughput=${cfgFailureThresholdThroughput--1}
cfgFailureThresholdBandwidth=${cfgFailureThresholdBandwidth--1}
cfgFailureThresholdStdDeviation=${cfgFailureThresholdStdDeviation--1}
cfgUnstableThresholdAvg=${cfgUnstableThresholdAvg--1}
cfgUnstableThresholdMin=${cfgUnstableThresholdMin--1}
cfgUnstableThresholdMax=${cfgUnstableThresholdMax--1}
cfgUnstableThresholdMed=${cfgUnstableThresholdMed--1}
cfgUnstableThreshold90p=${cfgUnstableThreshold90p--1}
cfgUnstableThresholdErr=${cfgUnstableThresholdErr--1}
cfgUnstableThresholdThroughput=${cfgUnstableThresholdThroughput--1}
cfgUnstableThresholdBandwidth=${cfgUnstableThresholdBandwidth--1}
cfgUnstableThresholdStdDeviation=${cfgUnstableThresholdStdDeviation--1}


cLog "Threshold settings after processing config file:"
( set -o posix ; set ) | grep "^cfg"


################################################################################
# 4 - variable sanity check
################################################################################
cLog "Checking if all the provided thresholds are valid. (unstable threshold < failure threshold and it's a number!)"
assertGEWithLabels ${cfgUnstableThresholdAvg} ${cfgFailureThresholdAvg} "Avarage unstable threshold" "Avarage failure threshold"
assertGEWithLabels ${cfgUnstableThresholdMin} ${cfgFailureThresholdMin} "Minimum unstable threshold" "Minimum failure threshold"
assertGEWithLabels ${cfgUnstableThresholdMax} ${cfgFailureThresholdMax} "Maximum unstable threshold" "Maximum failure threshold"
assertGEWithLabels ${cfgUnstableThresholdMed} ${cfgFailureThresholdMed} "Median unstable threshold" "Median failure threshold"
assertGEWithLabels ${cfgUnstableThreshold90p} ${cfgFailureThreshold90p} "90% line unstable threshold" "90% line failure threshold"
assertGEWithLabels ${cfgUnstableThresholdErr} ${cfgFailureThresholdErr} "Error rate unstable threshold" "Error rate failure threshold"
assertGEWithLabels ${cfgUnstableThresholdThroughput} ${cfgUnstableThresholdThroughput} "Throughput rate unstable threshold" "Throughput rate failure threshold"
assertGEWithLabels ${cfgUnstableThresholdBandwidth} ${cfgFailureThresholdBandwidth} "Bandwidth rate unstable threshold" "Bandwidth rate failure threshold"
assertGEWithLabels ${cfgUnstableThresholdStdDeviation} ${cfgFailureThresholdStdDeviation} "Standard Deviation unstable threshold" "Standard Deviation failure threshold"


################################################################################
# 5 - Extract all the metrics from the report file
# 
# for metric definitions please refer to:
# http://jmeter.apache.org/usermanual/component_reference.html#Aggregate_Report
#
# Average    - The average time of a set of results
# Median     - The median is the time in the middle of a set of results. 50% of the samples took no more than this time; the remainder took at least as long.
# 90% Line   - 90% of the samples took no more than this time. The remaining samples at least as long as this. (90 th percentile )
# Min        - The shortest time for the samples with the same label
# Max        - The longest time for the samples with the same label
# Error %    - Percent of requests with errors
# Throughput - the Throughput is measured in requests per second/minute/hour. 
#              The time unit is chosen so that the displayed rate is at least 1.0. 
#              When the throughput is saved to a CSV file, it is expressed in 
#              requests/second, i.e. 30.0 requests/minute is saved as 0.5.
#
#              http://jmeter.apache.org/usermanual/glossary.html#Throughput
#              Throughput is calculated as requests/unit of time. 
#              The time is calculated from the start of the first sample to 
#              the end of the last sample. This includes any intervals between 
#              samples, as it is supposed to represent the load on the server. 
#              The formula is: 
#                  Throughput = (number of requests) / (total time).
#
# Kb/sec     - The throughput measured in Kilobytes per second
#              Inside JMeter-Plugins project this metric is called 'Bandwidth'
#              https://github.com/undera/jmeter-plugins/blob/master/standard/src/kg/apc/jmeter/vizualizers/AggregateReportGui.java#L58
#
# stddev     - Standard Deviation is a measure of the variability of a data set.
#              This is a standard statistical measure. See, for example: 
#              Standard Deviation entry at http://en.wikipedia.org/wiki/Standard_deviation
#              JMeter calculates the population standard deviation 
#              (e.g. STDEVP function in spreadheets), not the sample 
#              standard deviation (e.g. STDEV).
################################################################################
avg=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f3`
med=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f4`
nine=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f5`
min=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f6`
max=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f7`
err=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f8`
trate=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f9`
band=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f10`
stddev=`tail -n1 ${cfgAggregateReportFile} | cut -d, -f11`

cLog "This build: Average response time: ${avg} ms"
cLog "This build: Median response time:  ${med} ms"
cLog "This build: 90% line value:        ${nine} ms"
cLog "This build: Minimum response time: ${min} ms"
cLog "This build: Maximum response time: ${max} ms"
cLog "This build: Error rate:            ${err} %"
cLog "This build: Throughput rate:       ${trate} Requests Per Second ((number of requests) / (total time))"
cLog "This build: Bandwidth rate:        ${band} Kb/sec"
cLog "This build: Standard Deviation:    ${stddev}"


################################################################################
# 6 - Verify all the metrics
################################################################################
verifyThreshold ${avg} ${cfgUnstableThresholdAvg} ${cfgFailureThresholdAvg} "Average response time"
verifyThreshold ${min} ${cfgUnstableThresholdMin} ${cfgFailureThresholdMin} "Minimum response time"
verifyThreshold ${max} ${cfgUnstableThresholdMax} ${cfgFailureThresholdMax} "Maximum response time"
verifyThreshold ${med} ${cfgUnstableThresholdMed} ${cfgFailureThresholdMed} "Median response time"
verifyThreshold ${nine} ${cfgUnstableThreshold90p} ${cfgFailureThreshold90p} "90% line response time"
verifyThreshold ${err} ${cfgUnstableThresholdErr} ${cfgFailureThresholdErr} "Error rate"
verifyThreshold ${trate} ${cfgUnstableThresholdThroughput} ${cfgFailureThresholdThroughput} "Throughput rate"
verifyThreshold ${band} ${cfgUnstableThresholdBandwidth} ${cfgFailureThresholdBandwidth} "Bandwidth rate"
verifyThreshold ${stddev} ${cfgUnstableThresholdStdDeviation} ${cfgFailureThresholdStdDeviation} "Standard Deviation"


if ${FAILED} ; then
    setBuildAsFailed
elif ${UNSTABLE} ; then
    setBuildAsUnstable
else
    cLog "All thresholds were successfully verified..."
fi;

