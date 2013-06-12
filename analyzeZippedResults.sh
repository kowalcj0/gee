#!/usr/bin/env bash


#
# JMETER="apache-jmeter-2.9" DEBUG=true FILES="hibuVoiceLongRun/2013-03-31-13_01-*-jtls.zip" WIDTH=20000 HEIGHT=1080 ./analyzeZippedResults.sh

# Get the absolute path to the directory with this script
# Source: http://stackoverflow.com/a/630387
MY_PATH="`dirname \"$0\"`";


## =============================================================================
## import other scripts
## =============================================================================
. ${MY_PATH}/helpers.sh #load all the generic helpers


# Execute the jmeter-ec2.properties file, to get access to JMETER_VERSION variable
. jmeter-ec2.properties

################################################################################
# check if all required programs are installed
################################################################################
isProgramInstalled "unzip";
isProgramInstalled "grep";
isProgramInstalled "java";


################################################################################
# GLOBALS
################################################################################
DATETIME=$(date +"%Y-%m-%d-%H_%M")  # more human readable date format, used to reporting
COUNT=
TMP=`mktemp -d` # create temp folder for processing
# declare all types of reports that you want to generate    
GRAPHS=("ResponseTimesOverTime" "LatenciesOverTime" "ResponseTimesDistribution" "ResponseTimesPercentiles" "BytesThroughputOverTime" "HitsPerSecond" "ResponseCodesPerSecond" "TimesVsThreads" "TransactionsPerSecond" "ThroughputVsThreads");



################################################################################
# STEP 1 - check all provided parameters and set defaults were possible
################################################################################
# check for JMETER
if [ -z "$JMETER_VERSION" ]; then
    cWarn "You forgot to provide path to the JMeter folder as a JMETER parameter. Please provide a valid path!!"
    exit 1;
else
    if [ -d $JMETER_VERSION ] && [[ -n $(ls $JMETER_VERSION/) ]] && [[ -e "${JMETER_VERSION}/bin/jmeter" ]] && [[ -e "${JMETER_VERSION}/lib/ext/CMDRunner.jar" ]]; then
        cLog "Jmeter with CMDRunner.jar is installed properly" ${DEBUG}
    else
        cWarn "Couldn't find either Jmeter inslled in ${JEMTER_VERSION} folder or CMDRunner.jar in ${JMETER_VERSION}/lib/ext/CMDRunner.jar"
        exit 2;
    fi;
fi;

# assume that if no count was provided, then there's only 1 file to process
if [ -z "$FILES" ] ; then 
    cErr "
    Please provide a path with the file name pattern to find all the result files, ie.:
    if you have 3 zipped result files
        2013-03-31-13_01-0-jtls.zip 2013-03-31-13_01-1-jtls.zip 2013-03-31-13_01-2-jtls.zip
    then your command should look like:
    FILES=\"hibuVoiceLongRun/2013-03-31-13_01-*-jtls.zip\" ./analyzeZippedResults.sh 

    NOTE:
    If you have only one file to process, then then type the whole filepath

    To run the script in a DEBUG mode add DEBUG=true to the command:
    DEBUG=true FILES=\"hibuVoiceLongRun/2013-03-31-13_01-*-jtls.zip\" ./analyzeZippedResults.sh
    "
    exit 1; 
else
    lsCmd="ls --format single-column ${FILES}"
    FILES=`${lsCmd} 2> /dev/null`
    COUNT=`${lsCmd} 2> /dev/null | wc -l`
    if [[ ${COUNT} -eq 1 ]]; then
        cLog "Found only '${COUNT}' file using path provided!"
    elif [[ ${COUNT} -gt 1 ]]; then
        cLog "Found ${COUNT} files using path provided!"
    else
        cErr "Couldn't find any files using path provided! Please check it!"
        exit 1;
    fi;
fi;

# disable DEBUG mode as default
if [ -z "$DEBUG" ] ; then
    DEBUG="false"; 
else
    cWan "DEBUG mode is enabled" ${DEBUG}
fi;

# assume that if no width was provided, then use the default 1920px
if [ -z "$WIDTH" ] ; then 
    cWarn "Target graph WIDTH wasn't provided, I'm using default 1920px" ${DEBUG}
    WIDTH="1920"; 
fi;

# assume that if no height was provided, then use the default 1200px
if [ -z "$HEIGHT" ] ; then 
    cWarn "Target graph HEIGHT wasn't provided, I'm using default 1200px" ${DEBUG}
    HEIGHT="1200"; 
fi;

# assume that if no target folder was provided, then use the default result folder in the current directory
if [ -z "$TARGET" ] ; then 
    cLog "Target directory wasn't provided, I'm using default ./target" ${DEBUG}
    TARGET="${MY_PATH}/target"; 
    if [[ ! -d "${TARGET}" ]]; then
        cLog "Creating target directory in the current directory" ${DEBUG}
        mkdir ${TARGET}
    fi;
    if [[ ! -d "${TARGET}/imgs" ]]; then
        mkdir ${TARGET}/imgs #create folder for images
    fi;
else
    if [[ ! -d "${TARGET}/imgs" ]]; then
        mkdir ${TARGET}/imgs #create folder for images
    fi;
fi;



################################################################################
# STEP 2 - extract all the zips
################################################################################
extractFiles "${FILES}";


################################################################################
# STEP 3 - merge selected files
################################################################################
mergeFilesUsingZipsNames "result.jtl" "${FILES}" "resultsMerged.jtl"


################################################################################
# STEP 3 - clean grouped file
################################################################################
refineGroupedFile "resultsMerged.jtl" "resultsMergedAndRefined.jtl"
 

	#***************************************************************************
    # add report header to a new report file
	#***************************************************************************
    cat reportHeader.txt > ${TARGET}/${DATETIME}-report.html


################################################################################
# STEP 4 - create graphs from the grouped file
################################################################################
# GRAPHS array is passed jsut as name, thus there is no $, it shall be 
# expanded only in the called function
# http://stackoverflow.com/questions/1063347/passing-arrays-as-parameters-in-bash#comment12455821_4017175
generateGraphsFromFile GRAPHS[@] "resultsMergedAndRefined.jtl" "${WIDTH}" "${HEIGHT}"


################################################################################
# STEP 5 - create graphs from the individual result files
################################################################################
# GRAPHS array is passed jsut as name, thus there is no $, it shall be 
# expanded only in the called function
# http://stackoverflow.com/questions/1063347/passing-arrays-as-parameters-in-bash#comment12455821_4017175
generateGraphsFromFiles GRAPHS[@] "${FILES}" "${WIDTH}" "${HEIGHT}"


################################################################################
# STEP 6 - run graph gen for perfMon
################################################################################
generatePerfMonGraphsFromFiles "${FILES}" "${WIDTH}" "${HEIGHT}"

	#***************************************************************************
    # add report header to a new report file
	#***************************************************************************
    cat reportFooter.txt >> ${TARGET}/${DATETIME}-report.html


tree $TMP
tree ${TARGET}

################################################################################
# STEP 7 - tidy up
################################################################################
cLog "Deleting TMP folder!"
rm -fr ${TMP}
