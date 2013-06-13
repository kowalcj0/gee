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
