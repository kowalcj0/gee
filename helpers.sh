#! /usr/bin/env bash


################################################################################
# Few helper functions
################################################################################

# Description: 
# Source: http://ubuntuforums.org/showthread.php?t=664657
# Usage: cLog 'Hello World' -> result "[Tue 2013-02-19 14:37:25 +0000] msg"
cLog() {
    # print normal log, for all nor DEBUG msgs;
    if [[ $# -lt 2 ]]; then 
        echo '['$(date +'%a %Y-%m-%d %H:%M:%S %z')']' '[INFO]:' $1;
    fi;
    if [[ $# -eq 2 ]] && ${DEBUG} && ${@: -1}; then #checks for the last arg, which should be DEBUG=true/false
        echo -e "\e[00;31m[$(date +'%a %Y-%m-%d %H:%M:%S %z')] [DEBUG]: $1 \e[00m";
    fi;
}

cErr(){
    echo -e "\e[00;31m[$(date +'%a %Y-%m-%d %H:%M:%S %z')] [ERROR]: $1 \e[00m";
}

cWarn(){
    echo -e "\e[01;33m[$(date +'%a %Y-%m-%d %H:%M:%S %z')] [WARN]: $1 \e[00m";
}

# Description: checks if spefified program is installed
# Source: http://stackoverflow.com/a/4785518
# Usage: isProgramInstalled "xmllint"
# $1 program name
isProgramInstalled() {
    cLog "Checking if '${1}' is installed" ${DEBUG};
    command -v "${1}" >/dev/null 2>&1 || { cLog "This script requires '\"${1}\"' but it's not installed. Aborting." >&2; exit 1; }
}


# Description: checks if spefified program is installed.
# Returns true or false accordingly. PS. it doesn't exit the script if not installed.
# Usage: isInstalled "xmllint"
# $1 program name
isInstalled(){
    command -v "${1}" >/dev/null 2>&1 \
        && {
            echo true
        } || { 
            echo false
        }
}


# Description: will extract all zips
# $1 - a list of zip files to extract
function extractFiles() {
    local FILES="${1}";
    for zipFile in $FILES; do
        local targetFolderName=`basename "${zipFile}" | cut -d. -f1`;
        cLog "Extracting: \"${zipFile}\" to ${TMP}/${targetFolderName}..."
        #mkdir "$TMP/$targetFolderName"
        unzip -q "${zipFile}" -d "$TMP/$targetFolderName"
        cLog "Done."
    done;
}


# author: Janusz Kowalczyk
# created: 2013-08-19
# Description:
# checks whether two values meets the greater or equal (x>=y) condition
# btw. function omitts values starting with a hyphen
# Example usage:
# assertGEWithLabels ${cfgUnstableThresholdAvg} ${cfgFailureThresholdAvg} "Avarage unstable threshold" "Avarage failure threshold"
# assertGEWithLabels 2.0 5.0 "Avarage unstable threshold" "Avarage failure threshold"
function assertGEWithLabels(){
    local leftOperand=${1-}
    local rightOperand=${2-}
    local leftLabel=${3-Left operand}
    local rightLabel=${4-Right operand}

    cLog "Checking values: '${leftLabel}'='${leftOperand}' / '${rightLabel}'='${rightOperand}'" ${DEBUG}

    # check if both operands are not empty
    if [[ -z ${leftOperand} ]] && [[ -z ${rightOperand} ]]; then
        cErr "Please check if values for both operands: '${leftLabel}' and '${rightLabel}' were provided!"
        exit 1
    fi

    # check if operand's value start with hyphen '-'
    # if so, exit from the function
    if [[ "${leftOperand}" =~ ^- ]] || [[ "${rightOperand}" =~ ^- ]]; then
        cLog "Omitting the check of: '${leftLabel}'='${leftOperand}' & '${rightLabel}'='${rightOperand}' as one of the operands starts with a hyphen" ${DEBUG}
        return 111
    fi

    # check if operads are numbers
    if [[ ! ${leftOperand} =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        cErr "'${leftLabel}'='${leftOperand}' should be a number!"
        exit 1
    fi
    if [[ ! ${rightOperand} =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        cErr "'${rightLabel}'='${rightOperand}' should be a number!"
        exit 1
    fi

    # check if they meet the >= condition
    if (($(echo "$leftOperand >= $rightOperand" |bc)!=0)); then
        cErr "'${leftLabel}'=${leftOperand} is >= than '${rightLabel}'=${rightOperand}"
        cErr "Please fix the configuration!"
        exit 1
    fi

    cLog "Successful assertion" ${DEBUG}
    return 0
}



# Description: Will merge selected file in folders into a grouped file.
# Folder names are based on the zip filenames used to extract them earlier
# $1 filename to merge
# $2 folders with files to merge
# $3 output filename
function mergeFilesUsingZipsNames() {
    local fileName="${1}"
    local FILES="${2}"
    local outputFile="${3}"
    for zipFile in $FILES; do
        local targetFolderName=`basename "${zipFile}" | cut -d. -f1`;
        cLog "Catting: \"${targetFolderName}/${fileName}\" to ${TMP}/${outputFile}..."
        cat ${TMP}/${targetFolderName}/${fileName} >> "$TMP/${outputFile}"
        cLog "Done."
    done;
}

# Description: 
# $1 input grouped file
# $2 output file name
function refineGroupedFile(){
    local inputF="${1}";
    local outputF="${2}";

	# Srt File
    cLog "Sorting grouped file and removing dupes..." ${DEBUG}
    sort -u "${TMP}/${inputF}" > ${TMP}/tmp-sorted.jtl

    cLog "Removing blank lines..." ${DEBUG}
	sed '/^$/d' ${TMP}/tmp-sorted.jtl > ${TMP}/tmp-noblanks.jtl

	# Remove any lines containing "0,0,Error:" - which seems to be an intermittant bug in JM where the getTimestamp call fails with a nullpointer
    cLog "Removing any lines containing \"0,0,Error:\"" ${DEBUG}
	sed '/^0,0,Error:/d' ${TMP}/tmp-noblanks.jtl > ${TMP}/tmp-noErrors.jtl

    cLog "Moving last line (column names) of the file to the first one..." ${DEBUG}
    sed '1h;1d;$!H;$!d;G' ${TMP}/tmp-noErrors.jtl  > ${TMP}/${outputF}
}

# Description: 
# $1 input grouped file
# $2 output file name
function refinePerfFile(){
    local inputF="${1}";
    local outputF="${2}";

	# Srt File
    cLog "Sorting grouped file and removing dupes..." ${DEBUG}
    sort -u "${TMP}/${inputF}" > ${TMP}/tmp-perf-sorted.jtl

    cLog "Removing blank lines..." ${DEBUG}
	sed '/^$/d' ${TMP}/tmp-perf-sorted.jtl > ${TMP}/tmp-perf-noblanks.jtl

	# Remove any lines containing "ConnectException" error - which occurs when server agent is not responding.
    cLog "Removing any lines containing \"0,0,Error:\"" ${DEBUG}
	sed '/ConnectException/d' ${TMP}/tmp-perf-noblanks.jtl > ${TMP}/tmp-perf-noErrors.jtl

    cLog "Moving last line (column names) of the file to the first one..." ${DEBUG}
    sed '1h;1d;$!H;$!d;G' ${TMP}/tmp-perf-noErrors.jtl  > ${TMP}/${outputF}
}


# Description: 
# $1 zip file names
function getFolderNamesFromZipFileNames() {
    local files="${2}"
    local dirsArray=() # create an emtpy temp array
    for zipFile in $files; do
        local targetFolderName=`basename "${zipFile}" | cut -d. -f1`;
        dirsArray+=("${TMP}/${targetFolderName}") # add folder to array
    done;
    # return an array of folders
    eval "${1}=(\"${dirsArray[@]}\")";
}


# Description: 
# $1 a list of graphs to generate
# $2 results file from which graphs will be generated
# $3 width of the graphs 
# $4 height of the graphs
function generateGraphsFromFile() {
    # expand passed array
    # http://stackoverflow.com/questions/1063347/passing-arrays-as-parameters-in-bash#comment12455821_4017175
    declare -a graphs=("${!1}");
    declare -a graphsWithoutRelTimeParam=("ResponseTimesDistribution" "ResponseTimesPercentiles" "TimesVsThreads" "ThroughputVsThreads");
    local resFile="${2}";
    local width="${3}";
    local height="${4}";

    local INITIAL_width="${3}";
    local INITIAL_height="${4}";

    COUNTER=0
    # generate all required graphs from the grouped results file
    for g in "${graphs[@]}"; do
        # don't add --relative-times parameter to some graphs
        insertRelativeTimeParam="--relative-times no"
        width=${INITIAL_width}; # just to make sure that values weren't overwritten
        height=${INITIAL_height};
        case "${graphsWithoutRelTimeParam[@]}" in *"${g}"*)
            insertRelativeTimeParam="";
            if [ $width -gt 1920 ]; then
                let width=1920;
            fi;
            if [ $height -gt 1080 ]; then
                let height=1080;
            fi;;
        esac;
        cLog "Generating '${g}' graph (${width}px/${height}px) from '${resFile}'"
        java -Djava.awt.headless=true -jar ${JMETER_VERSION}/lib/ext/CMDRunner.jar --tool Reporter ${insertRelativeTimeParam} --generate-png ${TARGET}/${DATETIME}/${g}-grouped.png --input-jtl "${TMP}/${resFile}" --plugin-type ${g} --width ${width} --height ${height}
        #cLog "Done"
        
        # set first graph as active
        if [ $COUNTER -eq 0 ]; then
            active="active "
            # increment counter so that we're no setting more items as active
            let COUNTER=COUNTER+1
        else
            active=""
        fi

        # add link and graph image to the report
        echo -e "
                <div class='${active}item'>
                    <h3><a href='#Define${g}'>${g} graph generated from ${resFile}</a></h3> 
                    <img class='img-polaroid' src='${DATETIME}/${g}-grouped.png' width=${width} height=${height}>
                </div>
        " >> ${TARGET}/${DATETIME}-report.html
    done
}


# Description: 
# $1 a list of graphs to generate
# $2 a lisf of folders with result files from which graphs will be generated
# $3 width of the graphs
# $4 height of the graphs
function generateGraphsFromFiles() {
    # expand passed array
    # http://stackoverflow.com/questions/1063347/passing-arrays-as-parameters-in-bash#comment12455821_4017175
    declare -a graphs=("${!1}");
    declare -a graphsWithoutRelTimeParam=("ResponseTimesDistribution" "ResponseTimesPercentiles" "TimesVsThreads" "ThroughputVsThreads");
    local zipFiles="${2}";
    local width="${3}";
    local height="${4}";
    local folders='';
    
    local INITIAL_width="${3}";
    local INITIAL_height="${4}";

    # assign return val to $folders
    getFolderNamesFromZipFileNames folders "${zipFiles}"; 

    for folderPath in ${folders[@]}; do
        local folder=`basename "${folderPath}"`
         # generate all required graphs from the grouped results file
        for g in "${graphs[@]}"; do
            # don't add --relative-times parameter to some graphs
            insertRelativeTimeParam="--relative-times no"
            width=${INITIAL_width}; # just to make sure that values weren't overwritten
            height=${INITIAL_height};
            case "${graphsWithoutRelTimeParam[@]}" in *"${g}"*)
                insertRelativeTimeParam="";
                width=1920;
                height=1080;;
            esac;
            cLog "Generating '${g}' graph from '${folder}/result.jtl' file"
            java -Djava.awt.headless=true -jar ${JMETER_VERSION}/lib/ext/CMDRunner.jar --tool Reporter ${insertRelativeTimeParam} --generate-png ${TARGET}/${DATETIME}/${g}-individual-${folder}.png --input-jtl "${folderPath}/result.jtl" --plugin-type ${g} --width ${width} --height ${height}
            
           # add link and graph image to the report
           echo -e "
                <div class='item'>
                    <h3><a href='#Define${g}'>${g} graph generated from ${folder}/result.jtl</a></h3> 
                    <img class='img-polaroid' src='${DATETIME}/${g}-individual-${folder}.png' width=${width} height=${height}>
                </div>
           " >> ${TARGET}/${DATETIME}-report.html
        done
   done;

}

# Description: 
# $1 a lisf of folders with result files from which graphs will be generated
# $2 width of the graphs
# $3 height of the graphs
function generatePerfMonGraphsFromFiles() {
    # expand passed array
    # http://stackoverflow.com/questions/1063347/passing-arrays-as-parameters-in-bash#comment12455821_4017175
    local zipFiles="${1}";
    local width="${2}";
    local height="${3}";
    local folders='';
    # assign return val to $folders
    getFolderNamesFromZipFileNames folders "${zipFiles}"; 

    for folderPath in ${folders[@]}; do
        local folder=`basename "${folderPath}"`

        # generate graphs for individual SUT Nodes
        if [[ -e ${folderPath}/PerfMon-remote.jtl ]]; then
            # generate all required graphs from the grouped results file
            cLog "Generating PerfMon graph from '${folder}/PerfMon-remote.jtl' file"
            java -Djava.awt.headless=true -jar ${JMETER_VERSION}/lib/ext/CMDRunner.jar --tool Reporter --relative-times no --generate-png ${TARGET}/${DATETIME}/PerfMon-remote-${folder}.png --input-jtl "${folderPath}/PerfMon-remote.jtl" --plugin-type PerfMon --width ${width} --height ${height}
            
            # add link and graph image to the report
            echo -e "
                <div class='item'>
                    <h3><a href='#DefinePerfMon'>Performance graph generated from ${folderPath}/PerfMon-remote.jtl</a></h3> 
                    <img class='img-polaroid' src='${DATETIME}/PerfMon-remote-${folder}.png' width=${width} height=${height}>
                </div>
            " >> ${TARGET}/${DATETIME}-report.html
        else
            cWarn "Couldn't find PerfMon-remote.jtl file in: ${folderPath}"
        fi;

        # generate graphs for individual JMeter Nodes
        if [[ -e ${folderPath}/PerfMon-local.jtl ]]; then
            # generate all required graphs from the grouped results file
            cLog "Generating PerfMon graph from '${folder}/PerfMon-local.jtl' file"
            java -Djava.awt.headless=true -jar ${JMETER_VERSION}/lib/ext/CMDRunner.jar --tool Reporter --relative-times no --generate-png ${TARGET}/${DATETIME}/PerfMon-individual-${folder}.png --input-jtl "${folderPath}/PerfMon-local.jtl" --plugin-type PerfMon --width ${width} --height ${height}
            
            # add link and graph image to the report
            echo -e "
                <div class='item'>
                    <h3><a href='#DefinePerfMon'>Performance graph generated from ${folderPath}/PerfMon-individual</a></h3> 
                    <img class='img-polaroid' src='${DATETIME}/PerfMon-individual-${folder}.png' width=${width} height=${height}>
                </div>
            " >> ${TARGET}/${DATETIME}-report.html
        else
            cWarn "Couldn't find PerfMon-local file in: ${folderPath}"
        fi;
   done;
}

# Will repeat CMD N-Times with a given Timeout time (using timeout3.sh script).
# btw. $LOCAL_HOME is a variable defined in the jmeter-ec2.sh that holds
# the absolute path to the project's folder
# $1 EXEC_MAX_TIMES
# $2 EXEC_TIMEOUT
# $3 CMD
# Example usage:
# repeatTillSucceedWithExecTimeout 3 3 "sleep 5"
# or with an optional step to execute code depending on the result
# repeatTillSucceedWithExecTimeout 2 3 "sleep 5" \
#    && {
#        echo passed
#    } || {
#        echo failed
#    }
function repeatTillSucceedWithExecTimeout() {
    if [ $# -lt 3 ] ; then
        cErr "${FUNCNAME}: Only $# parameters were provided. Expecting 3. Exiting with 0!";
        exit 0;
    fi
    local EXEC_MAX_TIMES=$1
    local EXEC_TIMEOUT=$2
    local CMD=$3
    local EXEC_COUNTER=1
    local EXEC_RESULT=''
    # run the CMD first time and get the exit code
    $LOCAL_HOME/timeout3.sh -t ${EXEC_TIMEOUT} ${CMD}
    EXEC_RESULT=`echo $?`
    # repeat until succeed or executed to many times
    while [[ "${EXEC_RESULT}" -gt "0" ]] && [[ "${EXEC_COUNTER}" -le "${EXEC_MAX_TIMES}" ]] ; do
        cWarn "Repeating last command... attempt #${EXEC_COUNTER}. Command:'${CMD}'"
        let EXEC_COUNTER=EXEC_COUNTER+1
        $LOCAL_HOME/timeout3.sh -t ${EXEC_TIMEOUT} ${CMD}
        EXEC_RESULT=`echo $?`
    done
    return ${EXEC_RESULT}
}



######################################3
#
# Parameters:
# $1 - name of the variable to which result date will be assigned
# $2 - [OPTIONAL] milisecond datetime
# $3 - [OPTIONAL] custom output format
#
# Examples:
#   #1: wihtout milisecond datetime will use the current datetime
#   msDatetimeToDate dddd
#   echo ${dddd}
#  
#   #2: convert provided datetime to date using default format "%Y-%m-%d %H:%M:%S %Z %:z"
#   msDatetimeToDate dddd 1382452212367
#   echo ${dddd}
#
#   #3: convert using custom format
#   msDatetimeToDate dddd 1382452212367 "%Y-%m-%d %H:%M:%S %Z"
#   echo ${dddd}
# 
function msDatetimeToDate(){
    if [ -z "${2}" ] ; then 
        local dt=`date +%s000`
    else
        local dt=${2-0}
    fi
    local __resultVar=$1
    local format=${3-'%Y-%m-%d %H:%M:%S %Z %:z'}
    local res=`(date -d @$( echo "(${dt} + 500) / 1000" | bc) +"${format}")`
    eval "$__resultVar="'${res}'""
}


# Three statistic functions: mean, stdev and median 
# Src: 
#   http://stackoverflow.com/a/9790156
#   http://stackoverflow.com/a/6166514
#
# Usage:
# Let's assume you have a CSV file with a header line. That looks like the one
# below: (here we use a JMeter result file)
# 
# timeStamp,elapsed,label,responseCode,responseMessage,dataType,success,bytes,grpThreads,allThreads,Latency,Hostname,IdleTime
# 1383319414875,265,Get,200,OK,text,true,23994,4,4,231,quantal64,0
# 1383319414878,264,Get,200,OK,text,true,23994,4,4,229,quantal64,0
# 1383319414878,268,Get,200,OK,text,true,23994,4,4,229,quantal64,0
# ...
# 
# then in bash:
# 
# file="results.csv"
# # use awk to extract latency column but without the header line
# # and sort the column as awk assumes one column of numerically sorted data
# latency=`awk -v OFS="," -F"," '{print $12}' ${file} | sed "1 d" | sort -n`
#
# # pass the variable to the function and save results as another variable
# latency_mean=`mean "${latency}"`
# latency_stdev=`stdev "${latency}"`
# latency_med=`med "${latency}"`
# 
# print results:
# echo "Latency: Mean=${latency_mean} ms, StDev=${latency_stdev}, Median=${latency_med}"
#
function mean() {
    local data="$1"
    echo "$data" | awk '{mean += $1} END {print mean/NR;}'
}
function stdev() {
    local data="$1"
    echo "$data" | awk '{sum+=$data; sumsq+=$data*$data;} END {print sqrt(sumsq/NR - (sum/NR)**2);}'
}
function median() {
    local data="$1"
    echo "$data" | gawk '{
        count[NR] = $1;
    }
    END {
        if (NR % 2) {
            print count[(NR + 1) / 2];
        } else {
            print (count[(NR / 2)] + count[(NR / 2) + 1]) / 2.0;
        }
    }'
}

# Finds the position of a column in a CSV header
# Params:
# $1 - searched column name
# $2 - CSV header line (please pass only one line)
#
# example usage:
#   file="path_to_file.csv"
#   cols=`head -n1 ${file}`
#   latency_pos=`findCSVColumnPostion "Latency" "${cols}"`
function findCSVColumnPostion() {
    local col_name="$1"
    local columns="$2"
    echo "${columns}" | awk -v SELECTED_FIELD=${col_name} '
    BEGIN {
      FS=",";
    }

    NR == 1 {
      for (i=1; i <= NF; ++i) {
        if ($i == SELECTED_FIELD) {
          SELECTED_COL=i;
        }
      }
    }

    END {
        print(SELECTED_COL);
    }'
}
