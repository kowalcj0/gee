#!/bin/bash

# ========================================================================================
# jmeter-ec2.sh
# https://github.com/oliverlloyd/jmeter-ec2
# http://www.http503.com/2012/run-jmeter-on-amazon-ec2-cloud/
# ========================================================================================
#
# Copyright 2012 - Oliver Lloyd - GNU GENERAL PUBLIC LICENSE
#
# JMeter-ec2 is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# JMeter-ec2 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with JMeter-ec2.  If not, see <http://www.gnu.org/licenses/>.
#

# load additional scripts
. helpers.sh # contains handly console logging functions
. secrets.sh # load additional script that can check for AWS creadentials


# more human readable date format, used to reporting
DATETIME=$(date +"%Y-%m-%d_-_%H-%M") 

# set custom format for "time" command
#export TIMEFORMAT='Elapsed real time used by the last process: %E seconds!'

# First make sure we have the required params and if not print out an instructive message
if [ -z "$project" ] ; then
	echo "jmeter-ec2: Required parameter 'project' missing"
	echo
	echo 'usage: project="abc" percent=20 setup="TRUE" terminate="TRUE" count="3" env="UAT" release="3.23" comment="my notes" ./jmeter-ec2.sh'
	echo
	echo "[project]         -	required, directory and jmx name"
	echo "[count]           -	optional, default=1"
	echo "[cfg]             -	optional, Custom cfg file"
	echo "[percent]         -	optional, default=100"
	echo "[setup]           -	optional, default='TRUE'"
	echo "[terminate]       -	optional, default='TRUE'"
	echo "[env]             -	optional"
	echo "[release]         -	optional"
	echo "[comment]         -	optional"
	echo "[propfile]        -	optional, additional property file, translates into a jmeter '-q' CLI parameter "
	echo "[logfile]         -	optional, the file to log samples to, translates into a jmeter '-l' CLI parameter. Can come handy when using Jenkins Performance plugin "
	echo
	exit
fi

# Set any null parameters to '-'
if [ -z "$env" ] ; then env="-" ; fi
if [ -z "$release" ] ; then release="-" ; fi
if [ -z "$comment" ] ; then comment="-" ; fi

# default to 100 if percent is not specified
if [ -z "$percent" ] ; then percent=100 ; fi
	
# default to TRUE if setup is not specified
if [ -z "$setup" ] ; then setup="TRUE" ; fi

# default to TRUE if terminate is not specified
if [ -z "$terminate" ] ; then terminate="TRUE" ; fi

# move count to instance_count
if [ -z "$count" ] ; then count=1 ; fi
instance_count=$count

LOCAL_HOME="`pwd`";
cLog "LOCAL_HOME before processing config files is: ${LOCAL_HOME}"

# use default jmeter-ec2.properties cfg file if cfg is not specified
if [ -z "$cfg" ] ; then 
    # check if AWS Access Keys are set
    getAWSSecrets; 

    if [ -f "$LOCAL_HOME/jmeter-ec2.properties" ] ; then
        cLog "Found jmeter-ec2.properties in $LOCAL_HOME. Loading it."
        . $LOCAL_HOME/jmeter-ec2.properties
    fi

    # Execute the jmeter-ec2.properties file, establishing these constants.
    # If exists then run a local version of the properties file to allow project customisations.
    if [ -f "$LOCAL_HOME/projects/$project/jmeter-ec2.properties" ] ; then
        echo "Found a project specific jmeter-ec2.properties file. Loading it.";
        . $LOCAL_HOME/projects/$project/jmeter-ec2.properties
    fi
else
    echo "using custom cfg file: ${cfg}";
    . ${cfg}
fi

cLog "LOCAL_HOME after processing config files is: ${LOCAL_HOME}"

# if parameters are not null then map them to jmeter CLI params
# those variables are initialized here because first we have to load cfg file
# to determine the $REMOTE_HOME
if [ ! -z "$propfile" ] ; then propfile=" -q $REMOTE_HOME/${propfile}" ; fi
if [ ! -z "$logfile" ] ; then logfile=" -l $REMOTE_HOME/${logfile}" ; fi


###############################################################################
#
# Configure filenames for reports etc
# if none of those variables is not provided in the command line, then 
# default values will be used.
# by NIXCRAFT
# http://www.cyberciti.biz/faq/bash-ksh-if-variable-is-not-defined-set-default-variable/
cWarn "\n/************************************\n* Current settings"
REMOTE_PORT=${REMOTE_PORT-22} # use default SSH port 22 if not provided
cfgHtmlReportFilename=${cfgHtmlReportFilename-${DATETIME}-report.html}
cfgHtmlReportGraphsDir=${cfgHtmlReportGraphsDir-${DATETIME}}
cfgJenkinsPerfPluginResultFilename=${cfgJenkinsPerfPluginResultFilename-${DATETIME}-jenkins.xml}
cfgGraphGenerationTimeout=${cfgGraphGenerationTimeout-60} # kill the CMDRunner.jar if it takes too long to generate a PNG graph.
cfgReportGraphWidth=${cfgReportGraphWidth-1920}
cfgReportGraphHeight=${cfgReportGraphHeight-1080}
cfgReportGraphWidthForGraphsWithRelativeTime=${cfgReportGraphWidthForGraphsWithRelativeTime-1920}
cfgReportGraphHeightForGraphsWithRelativeTime=${cfgReportGraphHeightForGraphsWithRelativeTime-1080}
cfgAggregatedResponseTimePercentilesReportsGenerate=${cfgAggregatedResponseTimePercentilesReportsGenerate-false}
cfgAggregatedResponseTimePercentilesReportsInputFile=${cfgAggregatedResponseTimePercentilesReportsInputFile-$LOCAL_HOME/projects/$project/results/aggregatedResponseTimesPercentiles.csv}
cfgAggregatedResponseTimePercentilesReportsOuputFolder=${cfgAggregatedResponseTimePercentilesReportsOuputFolder-$LOCAL_HOME/projects/$project/results/}
cfgSaveCompressedResults=${cfgSaveCompressedResults-true}
cfgPython=${cfgPython-python} # define which version of python you want to use to run genAggregateRepsTimesPercentilesReports.py
cfgDeleteContentsOfResultsFolder=${cfgDeleteContentsOfResultsFolder-true}
cfgTailRemoteJmeterLogs=${cfgTailRemoteJmeterLogs-true} # show last 10 lines of downloaded JMeter's log
cfgCreateHTMLReport=${cfgCreateHTMLReport-true} # If false no PNG graphs will be generated
cfgCreateAggregateCSVReport=${cfgCreateAggregateCSVReport-true}
cfgCreateGraphsForEachLoadGenerator=${cfgCreateGraphsForEachLoadGenerator-false} # decide whether graphs from individual load generators should be created and added to the HTML report
cfgCreateMergedFileForJenkinsPerfPlugin=${cfgCreateMergedFileForJenkinsPerfPlugin-true}
cfgGenerateAggregatedResponseTimePercentilesReports=${cfgGenerateAggregatedResponseTimePercentilesReports-true}
cfgCreateMergedResultFile=${cfgCreateMergedResultFile-true}
cfgLocalJmeterLogLevel=${cfgLocalJmeterLogLevel-WARN}
cfgRemoteJmeterLogLevel=${cfgRemoteJmeterLogLevel-INFO}


# TO-DO
# add handlers to enable/disable feautres described by flags below:

( set -o posix ; set ) | grep "^cfg"
cWarn "\n* Carrying on with execution...\n************************************/"


#exit 1
#
###############################################################################


# will delete all files from the project's results folder except the .gitignore
# This step helps to avoid situations when ie. Jenkins failed to run the job
# properly and plugins like "Plot Plugin" or "Performnace Plugin" will use
# result files from the previous build to update the performance trend.
if [ ${cfgDeleteContentsOfResultsFolder} ] ; then
    cLog "Deleting all contents of ${LOCAL_HOME}/projects/$project/results folder..."
    cd ${LOCAL_HOME}/projects/$project/results \
        && {
            find '(' -name .gitignore ')' -prune -o -exec rm -rf {} \; \
                && {
                    cLog "All files from ${LOCAL_HOME}/projects/$project/results were deleted"
                } || {
                    cErr "Something went wrong when deleting files inside ${LOCAL_HOME}/projects/$project/results!!"
                }
        } || {
            cWarn "Couldn't cd into ${LOCAL_HOME}/projects/$project/results!!!"
        }
    cd ${LOCAL_HOME}
fi


# run scripts to install ec2 tools and jmeter if needed
# if something goes wrong at this stage, abort the test!
./download-ec2-tools.sh || { exit `echo $?` ; }
./download-jmeter.sh || { exit `echo $?` ; }


# change the JMeter's log_level in the jmeter.properties that will be uploaded
# onto all load generators
sed -i.bck 's/.*log_level.jmeter=.*/log_level.jmeter='${cfgRemoteJmeterLogLevel}'/' ${LOCAL_HOME}/jmeter.properties \
    && {
        cLog "JMeter's log_level for load generators was set to: ${cfgRemoteJmeterLogLevel}"
    } || {
        cErr "Couldn't modify the: '${LOCAL_HOME}/jmeter.properties' to change the log_level for load generators!!!"
    }

# change the JMeter's log_level in the locally installed JMeter
# this will allow you to controll the logging verbosity while generating graphs
sed -i.bck 's/.*log_level.jmeter=.*/log_level.jmeter='${cfgLocalJmeterLogLevel}'/' $LOCAL_HOME/${JMETER_VERSION}/bin/jmeter.properties \
    && {
        cLog "log_level of locally installed JMeter was set to: ${cfgLocalJmeterLogLevel}"
    } || {
        cErr "Couldn't modify the: '$LOCAL_HOME/${JMETER_VERSION}/bin/jmeter.properties' to change the log_level for locally installed instance of JMeter!!!"
    }


cd $EC2_HOME

# check project directry exists
if [ ! -d "$LOCAL_HOME/projects/$project" ] ; then
    echo "The directory $LOCAL_HOME/projects/$project does not exist."
    echo
    echo "Script exiting."
    exit
fi

function runsetup() {
    # if REMOTE_HOSTS is not set then no hosts have been specified to run the test on so we will request them from Amazon
    if [ -z "$REMOTE_HOSTS" ] ; then
        
        # check if ELASTIC_IPS is set, if it is we need to make sure we have enough of them
        if [ ! -z "$ELASTIC_IPS" ] ; then # Not Null - same as -n
            elasticips=(`echo $ELASTIC_IPS | tr "," "\n" | tr -d ' '`)
            elasticips_count=${#elasticips[@]}
            if [ "$instance_count" -gt "$elasticips_count" ] ; then
                echo
                echo "You are trying to launch $instance_count instance but you have only specified $elasticips_count elastic IPs."
                echo "If you wish to use Staitc IPs for each test instance then you must increase the list of values given for ELASTIC_IPS in the properties file."
                echo
                echo "Alternatively, if you set the STATIC_IPS property to \"\" or do not specify it at all then the test will run without trying to assign static IPs."
                echo
                echo "Script exiting..."
                echo
                exit
            fi
        fi

        # default to 1 instance if a count is not specified
        if [ -z "$instance_count" ] ; then instance_count=1; fi

        echo
        echo "   -------------------------------------------------------------------------------------"
        echo "       jmeter-ec2 Automation Script - Running $project.jmx over $instance_count AWS Instance(s)"
        echo "   -------------------------------------------------------------------------------------"
        echo
        echo
              
        # create the instance(s) and capture the instance id(s)
        echo -n "requesting $instance_count instance(s)..."
        attempted_instanceids=(`ec2-run-instances \
		            --key $AMAZON_KEYPAIR_NAME \
                    -t $INSTANCE_TYPE \
                    -g $INSTANCE_SECURITYGROUP \
                    -n 1-$instance_count \
		            --region $REGION \
                    --availability-zone \
                    $INSTANCE_AVAILABILITYZONE $AMI_ID \
                    | awk '/^INSTANCE/ {print $2}'`)
        
        # check to see if Amazon returned the desired number of instances as a limit is placed restricting this and we need to handle the case where
        # less than the expected number is given wthout failing the test.
        countof_instanceids=${#attempted_instanceids[@]}
        if [ "$countof_instanceids" = 0 ] ; then
            echo
            echo "Amazon did not supply any instances, exiting"
            echo
            exit
        fi
        if [ $countof_instanceids != $instance_count ] ; then
            echo "$countof_instanceids instance(s) were given by Amazon, the test will continue using only these instance(s)."
            instance_count=$countof_instanceids
        else
            echo "success"
        fi
        echo
        
        # wait for each instance to be fully operational
        status_check_count=0
        status_check_limit=45
        status_check_limit=`echo "$status_check_limit + $countof_instanceids" | bc` # increase wait time based on instance count
        echo -n "waiting for instance status checks to pass (this can take several minutes)..."
        count_passed=0
        while [ "$count_passed" -ne "$instance_count" ] && [ $status_check_count -lt $status_check_limit ]
        do
            echo -n .
            status_check_count=$(( $status_check_count + 1))
            count_passed=$(ec2-describe-instance-status --region $REGION ${attempted_instanceids[@]} | awk '/INSTANCESTATUS/ {print $3}' | grep -c passed)
            sleep 1
        done
        
        if [ $status_check_count -lt $status_check_limit ] ; then # all hosts started ok because count_passed==instance_count
            # get hostname and build the list used later in the script

			# set the instanceids array to use from now on - attempted = actual
			for key in "${!attempted_instanceids[@]}"
			do
			  instanceids["$key"]="${attempted_instanceids["$key"]}"
			done
			
			# set hosts array
            hosts=(`ec2-describe-instances --region $REGION ${attempted_instanceids[@]} | awk '/INSTANCE/ {print $4}'`)
            echo "all hosts ready"
        else # Amazon probably failed to start a host [*** NOTE this is fairly common ***] so show a msg - TO DO. Could try to replace it with a new one?
            original_count=$countof_instanceids
            # filter requested instances for only those that started well
            healthy_instanceids=(`ec2-describe-instance-status --region $REGION ${attempted_instanceids[@]} \
                                --filter instance-status.reachability=passed \
                                --filter system-status.reachability=passed \
                                | awk '/INSTANCE\t/ {print $2}'`)

            hosts=(`ec2-describe-instances --region $REGION ${healthy_instanceids[@]} | awk '/INSTANCE/ {print $4}'`)

            if [ "${#healthy_instanceids[@]}" -eq 0 ] ; then
                countof_instanceids=0
                echo "no instances successfully initialised, exiting"
				if [ "$terminate" = "TRUE" ] ; then
					echo
				    # attempt to terminate any running instances - just to be sure
			        echo "terminating instance(s)..."
					# We use attempted_instanceids here to make sure that there are no orphan instances left lying around
			        ec2-terminate-instances --region $REGION ${attempted_instanceids[@]}
			        echo
				fi
                exit
            else
                countof_instanceids=${#healthy_instanceids[@]}
            fi
            countof_failedinstances=`echo "$original_count - $countof_instanceids"|bc`
            if [ "$countof_failedinstances" -gt 0 ] ; then # if we still see failed instances then write a message
                echo "$countof_failedinstances instances(s) failed to start, only $countof_instanceids machine(s) will be used in the test"
                instance_count=$countof_instanceids
            fi
			
			# set the array of instance ids based on only those that succeeded
			for key in "${!healthy_instanceids[@]}"  # make sure you include the quotes there
			do
			  instanceids["$key"]="${healthy_instanceids["$key"]}"
			done
        fi
		echo
		
		# assign a name tag to each instance
		echo "assigning tags..."
		(ec2-create-tags --region $REGION ${attempted_instanceids[@]} --tag ProductKey=$project)
        (ec2-create-tags --region $REGION ${attempted_instanceids[@]} --tag Service=prod)
        (ec2-create-tags --region $REGION ${attempted_instanceids[@]} --tag Description=PerformanceTest)
        (ec2-create-tags --region $REGION ${attempted_instanceids[@]} --tag Owner=$EMAIL)
        (ec2-create-tags --region $REGION ${attempted_instanceids[@]} --tag ContactEmail=$EMAIL)
		(ec2-create-tags --region $REGION ${attempted_instanceids[@]} --tag Name="jmeter-ec2-$project")
		wait
        echo "complete"
		echo
		
        # if provided, assign elastic IPs to each instance
        if [ ! -z "$ELASTIC_IPS" ] ; then # Not Null - same as -n
            echo "assigning elastic ips..."
            for x in "${!instanceids[@]}" ; do
                (ec2-associate-address --region $REGION -i ${instanceids[x]} ${elasticips[x]})
                hosts[x]=${elasticips[x]}
            done
			wait
            echo "complete"

            echo
            echo -n "checking elastic ips..."
            for x in "${!instanceids[@]}" ; do
				# check for ssh connectivity on the new address
	            while ssh -o StrictHostKeyChecking=no -q -i $PEM_PATH/$PEM_FILE \
	                $USER@${hosts[x]} -p $REMOTE_PORT true && test; \
	                do echo -n .; sleep 1; done
	            # Note. If any IP is already in use on an instance that is still running then the ssh check above will return
	            # a false positive. If this scenario is common you should put a sleep statement here.
            done
			wait
            echo "complete"
            echo
        fi
        
        # Tell install.sh to attempt to install JAVA
        attemptjavainstall=1
    else # the property REMOTE_HOSTS is set so we wil use this list of predefined hosts instead
        hosts=(`echo $REMOTE_HOSTS | tr "," "\n" | tr -d ' '`)
        instance_count=${#hosts[@]}
        # Tell install.sh to not attempt to install JAVA
        attemptjavainstall=0
        echo
        echo "   -------------------------------------------------------------------------------------"
        echo "       jmeter-ec2 Automation Script - Running $project.jmx over $instance_count predefined host(s)"
        echo "   -------------------------------------------------------------------------------------"
        echo
        echo
    
	    # Check if remote hosts are up
	    for host in ${hosts[@]} ; do
	        if [ ! "$(ssh -q -q \
	            -o StrictHostKeyChecking=no \
	            -o "BatchMode=yes" \
	            -o "ConnectTimeout 15" \
	            -i $PEM_PATH/$PEM_FILE \
	            -p $REMOTE_PORT \
	            $USER@$host echo up 2>&1)" == "up" ] ; then
	            echo "Host $host is not responding, script exiting..."
	            echo
	            exit
	        fi
	    done
    fi


    # if we are using a predefined list of load generators
    # then delete all remote crap before starting the test
    # should help to avoid situation when we were downloading files from 
    # the previous runs
    if [ ! -z "$REMOTE_HOSTS" ]; then
        for i in ${!hosts[@]} ; do
            # had to split it in multiple lines to avoid situation when one of the
            # RMs fails and prevents remaining commands from execution
            ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
            rm -f *.jtl)
            ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
            rm -f *.zip)
            ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
            rm -f *.jmx)
            ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
            rm -f *.log)
            ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
            rm -f *.out)
            ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
            rm -f install.sh)
            ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
            rm -f *.properties)
            ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
            rm -fr $REMOTE_HOME/data)
            ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
            rm -fr $REMOTE_HOME/cfg)
            cLog "All remote files were deleted before copying anything and starting JMeter on: ${hosts[$i]}"
        done
    fi


    # scp install.sh
    if [ "$setup" = "TRUE" ] ; then
    	echo -n "copying install.sh to $instance_count server(s)..."
        #sleep 20s
	    for host in ${hosts[@]} ; do

            # scp default jmeter-ec2.properties cfg file or a custom one
            if [ -z "$cfg" ] ; then 
                echo -e "\nscp install.sh & jmeter-ec2.properties file to ${host}\n"
                (scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                          -i $PEM_PATH/$PEM_FILE \
                                          -P $REMOTE_PORT \
                                          $LOCAL_HOME/install.sh \
                                          $LOCAL_HOME/jmeter-ec2.properties \
                                          $USER@$host:$REMOTE_HOME \
                                          && echo "done" > $LOCAL_HOME/projects/$project/$DATETIME-$host-scpinstall.out)
            else
                echo -e "\nSCP custom cfg file: ${cfg} to: ${host}\n";
                (scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                          -i $PEM_PATH/$PEM_FILE \
                                          -P $REMOTE_PORT \
                                          $LOCAL_HOME/${cfg} \
                                          $USER@$host:$REMOTE_HOME/jmeter-ec2.properties \
                                          && echo "done" > $LOCAL_HOME/projects/$project/$DATETIME-$host-scpinstall.out)
                echo -e "\nSCP install.sh file to: ${host}\n";
                (scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                          -i $PEM_PATH/$PEM_FILE \
                                          -P $REMOTE_PORT \
                                          $LOCAL_HOME/install.sh \
                                          $USER@$host:$REMOTE_HOME \
                                          && echo "done" > $LOCAL_HOME/projects/$project/$DATETIME-$host-scpinstall.out)
            fi;
	    done

	    # check to see if the scp call is complete (could just use the wait command here...)
	    res=0
	    while [ "$res" != "$instance_count" ] ;
	    do
	        echo -n .
	        res=$(grep -c "done" $LOCAL_HOME/projects/$project/$DATETIME*scpinstall.out \
	            | awk -F: '{ s+=$NF } END { print s }') # the awk command here sums up the output if multiple matches were found
	        sleep 3
	    done
	    echo "complete"
	    echo
    
	    # Install test software
	    echo "running install.sh on $instance_count server(s)..."
        echo "attemptjavainstall = ${attemptjavainstall}";
	    for host in ${hosts[@]} ; do
	        (ssh -nq -o StrictHostKeyChecking=no \
	            -i $PEM_PATH/$PEM_FILE $USER@$host -p $REMOTE_PORT \
	            "$REMOTE_HOME/install.sh $REMOTE_HOME $attemptjavainstall $JMETER_VERSION"\
	            > $LOCAL_HOME/projects/$project/$DATETIME-$host-install.out) &
	    done
    
	    # check to see if the install scripts are complete
	    res=0
	    while [ "$res" != "$instance_count" ] ; do # Installation not complete (count of matches for 'software installed' not equal to count of hosts running the test)
	        echo -n .
	        res=$(grep -c "software installed" $LOCAL_HOME/projects/$project/$DATETIME*install.out \
	            | awk -F: '{ s+=$NF } END { print s }') # the awk command here sums up the output if multiple matches were found
	        sleep 3
	    done
	    echo "complete"
	    echo
    fi
    
    # Create a working jmx file and edit it to adjust thread counts and filepaths (leave the original jmx intact!)
    cp $LOCAL_HOME/projects/$project/$project.jmx $LOCAL_HOME/projects/$project/working
    working_jmx="$LOCAL_HOME/projects/$project/working"
    temp_jmx="$LOCAL_HOME/projects/$project/temp"
    
    # first filepaths (this will help with things like csv files)
    # edit any 'stringProp filename=' references to use $REMOTE_DIR in place of whatever local path was being used
    # we assume that the required dat file is copied into the local /data directory
    filepaths=$(awk 'BEGIN { FS = ">" } ; /<stringProp name=\"filename\">[^<]*<\/stringProp>/ {print $2}' $working_jmx | cut -d'<' -f1) # pull out filepath
    i=1
    while read filepath ; do
        if [ -n "$filepath" ] ; then # this entry is not blank
            # extract the filename from the filepath using '/' separator
            filename=$( echo $filepath | awk -F"/" '{print $NF}' )
            endresult="$REMOTE_HOME"/data/"$filename"
            if [[ $filepath =~ .*\$.* ]] ; then
                echo "The path $filepath contains a $ char, this currently fails the awk sub command."
                echo "You'll have to remove these from all filepaths. Sorry."
                echo
                echo "Script exiting"
                #exit
            fi
            awk '/<stringProp name=\"filename\">[^<]*<\/stringProp>/{c++;if(c=='"$i"') \
                                   {sub("filename\">'"$filepath"'<","filename\">'"$endresult"'<")}}1'  \
                                   $working_jmx > $temp_jmx
            rm $working_jmx
            mv $temp_jmx $working_jmx
        fi
        # increment i
        i=$((i+1))
    done <<<"$filepaths"
    
    # now we use the same working file to edit thread counts
    # to cope with the problem of trying to spread 10 threads over 3 hosts (10/3 has a remainder) the script creates a unique jmx for each host
    # and then passes out threads to them on a round robin basis
    # as part of this we begin here by creating a working jmx file for each separate host using _$y to isolate
    for y in "${!hosts[@]}" ; do
        # for each host create a working copy of the jmx file
        cp "$working_jmx" "$working_jmx"_"$y"   
    done
    # loop through each threadgroup and then use a nested loop within that to edit the file for each host
       # pull out the current values for each thread group
       threadgroup_threadcounts=(`awk 'BEGIN { FS = ">" } ; /ThreadGroup\.num_threads\">[^<]*</ {print $2}' $working_jmx | cut -d'<' -f1`) # put the current thread counts into variable
       threadgroup_names=(`awk 'BEGIN { FS = "\"" } ; /ThreadGroup\" testname=\"[^\"]*\"/ {print $6}' $working_jmx`) # capture each thread group name
       
       # first we check to make sure each threadgroup_threadcounts is numeric
       for n in ${!threadgroup_threadcounts[@]} ; do
           case ${threadgroup_threadcounts[$n]} in
               ''|*[!0-9]*)
                   echo "Error: Thread Group: ${threadgroup_names[$n]} has the value: ${threadgroup_threadcounts[$n]}, which is not numeric - Thread Count must be numeric!"
                   echo
                   echo "Script exiting..."
                   echo
                   exit;;
                   *);;
           esac
       done
       
       # get count of thread groups, show results to screen
       countofthreadgroups=${#threadgroup_threadcounts[@]}
       echo "editing thread counts..."
	echo
	echo " - $project.jmx has $countofthreadgroups threadgroup(s) - [inc. those disabled]"
	
	# sum up the thread counts
	sumofthreadgroups=0
       for n in ${!threadgroup_threadcounts[@]} ; do
		# populate an array of the original thread counts (used in the find and replace when editing the jmx)
		orig_threadcounts[$n]=${threadgroup_threadcounts[$n]}
		# create a total of the original thread counts
		sumofthreadgroups=$(echo "$sumofthreadgroups+${threadgroup_threadcounts[$n]}" | bc)
       done

	# adjust each thread count based on percent
	sumofadjthreadgroups=0
	for n in "${!orig_threadcounts[@]}" ; do
		# get a new thread count to 2 decimal places
		float=$(echo "scale=2; ${orig_threadcounts[$n]}*($percent/100)" | bc)
		# round to integer
		new_threadcounts[$n]=$(echo "($float+0.5)/1" | bc)
		if [ "${new_threadcounts[$n]}" -eq "0" ] ; then
			echo " - Thread group ${threadgroup_names[$n]} has ${orig_threadcounts[$n]} threads, $percent percent of this is $float which rounds to 0, so we're going to set it to 1 instead."
			new_threadcounts[$n]=1
			sumofadjthreadgroups=$(echo "$sumofadjthreadgroups+1" | bc)
		fi
	done
	
	# Now we sum up the thread counts and print a total
	for n in ${!new_threadcounts[@]} ; do
		sumofadjthreadgroups=$(echo "$sumofadjthreadgroups+${new_threadcounts[$n]}" | bc)
	done

	echo " - There are $sumofthreadgroups threads in the test plan, this test is set to execute $percent percent of these, so will run using $sumofadjthreadgroups threads"

	# now we loop through each thread group, editing a separate file for each host each iteration (nested loop)
	for i in ${!threadgroup_threadcounts[@]} ; do
		# using modulo we distribute the threads over all hosts, building the array 'threads'
		# taking 10(threads)/3(hosts) as an example you would expect two hosts to be given 3 threads and one to be given 4.
		for (( x=1; x<=${new_threadcounts[$i]}; x++ )); do
			: $(( threads[$(( $x % ${#hosts[@]} ))]++ ))
		done

		# here we loop through every host, editing the jmx file and using a temp file to carry the changes over
		for y in "${!hosts[@]}" ; do
			# we're already in a loop for each thread group but awk will parse the entire file each time it is called so we need to
			# use an index to know when to make the edit
			# when c (awk's index) matches i (the main for loop's index) then a substitution is made

			# first check for any null values (caused by lots of hosts and not many threads)
			threadgroupschanged=0
			if [ -z "${threads[$y]}" ] ; then
				threads[$y]=1
				threadgroupschanged=$(echo "$threadgroupschanged+1" | bc)
			fi
			if [ "$threadgroupschanged" == "1" ] ; then
				echo " - $threadgroupschanged thread groups were allocated zero threads, this happens because the total allocated threads to a group is less than the $instance_count instances being used."
				echo "   To get around this the script gave each group an extra thread, a better solution is to revise the test configuration to use more threads / less instances"
			fi
			findstr="threads\">"${orig_threadcounts[$i]}
			replacestr="threads\">"${threads[$y]}
			awk -v "findthis=$findstr" -v "replacewiththis=$replacestr" \
				'BEGIN{c=0} \
				/ThreadGroup\.num_threads\">[^<]*</ \
				{if(c=='"$i"'){sub(findthis,replacewiththis)};c++}1' \
				"$working_jmx"_"$y" > "$temp_jmx"_"$y"

			# using awk requires the use of a temp file to save the results of the command, update the working file with this file
			rm "$working_jmx"_"$y"
			mv "$temp_jmx"_"$y" "$working_jmx"_"$y"
		done

		# write update to screen - removed 23/04/2012
		# echo "...$i) ${threadgroup_names[$i]} has ${threadgroup_threadcounts[$i]} thread(s), to be distributed over $instance_count instance(s)"

		unset threads
	done
	echo
	echo "...thread counts updated"
	echo
    
    # scp the test files onto each host
    echo -n "copying test files to $instance_count server(s)..."
    
    # scp jmx dir
    echo -n "jmx files.."
    for y in "${!hosts[@]}" ; do
        (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
                                      -i $PEM_PATH/$PEM_FILE -P $REMOTE_PORT \
                                      $LOCAL_HOME/projects/$project/working_$y \
                                      $USER@${hosts[$y]}:$REMOTE_HOME/execute.jmx) &
    done
    wait
    echo -n "done...."
    
    # scp data dir
    if [ "$setup" = "TRUE" ] ; then
    	if [ -r $LOCAL_HOME/projects/$project/data ] ; then # don't try to upload this optional dir if it is not present
	        echo -n "data dir.."
	        for host in ${hosts[@]} ; do
	            (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
	                                          -i $PEM_PATH/$PEM_FILE -P $REMOTE_PORT \
	                                          $LOCAL_HOME/projects/$project/data \
	                                          $USER@$host:$REMOTE_HOME/) &
	        done
	        wait
	        echo -n "done...."
	    fi
   
	    # scp jmeter.properties
	    if [ -r $LOCAL_HOME/jmeter.properties ] ; then # don't try to upload this optional file if it is not present
	        echo -n "jmeter.properties.."
	        for host in ${hosts[@]} ; do
	            (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
	                                          -i $PEM_PATH/$PEM_FILE -P $REMOTE_PORT \
	                                          $LOCAL_HOME/jmeter.properties \
	                                          $USER@$host:$REMOTE_HOME/$JMETER_VERSION/bin/) &
	        done
	        wait
	        echo -n "done...."
	    fi
    
	    # scp jmeter execution file
	    if [ -r $LOCAL_HOME/jmeter ] ; then # don't try to upload this optional file if it is not present
	        echo -n "jmeter execution file..."
	        for host in ${hosts[@]} ; do
	            (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
	                                          -i $PEM_PATH/$PEM_FILE -P $REMOTE_PORT \
	                                          $LOCAL_HOME/jmeter $LOCAL_HOME/jmeter \
	                                          $USER@$host:$REMOTE_HOME/$JMETER_VERSION/bin/) &
	        done
	        wait
	        echo -n "done...."
	    fi
 
        # scp cfg dir
        if [[ -d $LOCAL_HOME/projects/$project/cfg ]] && [[ -n $(ls $LOCAL_HOME/projects/$project/cfg/) ]]; then # don't try to upload this optional dir if it is not present
	        echo -n "cfg dir.."
	        for host in ${hosts[@]} ; do
	            (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
	                                          -i $PEM_PATH/$PEM_FILE -P $REMOTE_PORT \
	                                          $LOCAL_HOME/projects/$project/cfg \
	                                          $USER@$host:$REMOTE_HOME/) &
	        done
	        wait
	        echo -n "done...."
	    fi
    
		# scp any custom jar files
	    if [[ -d $LOCAL_HOME/plugins ]] && [[ -n $(ls $LOCAL_HOME/plugins/) ]] ; then # don't try to upload any files if none present
	        echo -n "custom jar file(s)..."
	        for host in ${hosts[@]} ; do
	            (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
	                                          -i $PEM_PATH/$PEM_FILE -P $REMOTE_PORT \
	                                          $LOCAL_HOME/plugins/*.jar \
	                                          $USER@$host:$REMOTE_HOME/$JMETER_VERSION/lib/ext/) &
	        done
	        wait
	        echo -n "done...."
	    fi
	
	    # scp any project specific custom jar files
	    if [[ -d $LOCAL_HOME/projects/$project/plugins ]] && [[ -n $(ls $LOCAL_HOME/projects/$project/plugins/) ]]; then # don't try to upload any files if none present
	        echo -n "project specific jar file(s)..."
	        for host in ${hosts[@]} ; do
	            (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
	                                          -i $PEM_PATH/$PEM_FILE -P $REMOTE_PORT \
	                                          $LOCAL_HOME/projects/$project/plugins/*.jar \
	                                          $USER@$host:$REMOTE_HOME/$JMETER_VERSION/lib/ext/) &
	        done
	        wait
	        echo -n "done...."
	    fi
	
		if [ ! -z "$DB_HOST" ] ; then
			# upload import-results.sh
		    echo -n "copying import-results.sh to database..."
		    (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
		                                  -i $DB_PEM_PATH/$DB_PEM_FILE -P $DB_SSH_PORT \
		                                  $LOCAL_HOME/import-results.sh \
		                                  $DB_PEM_USER@$DB_HOST:$REMOTE_HOME) &
			wait
		
			# set permissions
		    (ssh -n -o StrictHostKeyChecking=no \
		        -i $DB_PEM_PATH/$DB_PEM_FILE $DB_PEM_USER@$DB_HOST -p $DB_SSH_PORT \
				"chmod 755 $REMOTE_HOME/import-results.sh")
			wait
			echo -n "done...."
		fi

		echo "all files uploaded"
	    echo   
	fi
	
	if [ ! -z "$DB_HOST" ] ; then
		# Add an entry to the tests table in the database
		echo -n "creating new test in database..."
		updateTest 0 x x "$release" "$project" "$env" "$comment" 
		echo "testid $newTestid created"
		echo
	fi
	
    echo
    
    cLog "Checking for stale jmeter instances on:"
    for host in ${hosts[@]} ; do
        cLog $host
        # check if we're running a list of pre-defined hosts to run tests
        # if so, then make sure that there are no other instances of JMeter running
        if [ ! -z "$REMOTE_HOSTS" ]; then
            #echo -e "\nMaking sure that no other JMeter instance is running on ${host}... \n"
            ( ssh -nq -o StrictHostKeyChecking=no \
            -i $PEM_PATH/$PEM_FILE $USER@${host} -p $REMOTE_PORT \
            pkill -f ApacheJMeter.jar && { echo "Killed stale instance of JMeter running on ${host}"; } > $LOCAL_HOME/projects/$project/kill.txt )
            if [ -e $LOCAL_HOME/projects/$project/kill.txt ]; then
                cWarn "$(cat $LOCAL_HOME/projects/$project/kill.txt)"
                rm $LOCAL_HOME/projects/$project/kill.txt
            fi
        fi
    done
    #
    #    ssh -nq -o UserKnownHostsFile=/dev/null \
    #         -o StrictHostKeyChecking=no \
    #        -i $PEM_PATH/$PEM_FILE $USER@${host[$counter]} \               # ec2 key file
    #        $REMOTE_HOME/$JMETER_VERSION/bin/jmeter.sh -n \               # execute jmeter - non GUI - from where it was just installed
    #        -t $REMOTE_HOME/execute.jmx \                                      # run the jmx file that was uploaded
    #        -l $REMOTE_HOME/$project-$DATETIME-$counter.jtl \                  # write results to the root of remote home
    #        > $LOCAL_HOME/$project/$DATETIME-${host[$counter]}-jmeter.out      # redirect output from Generate Summary Results to a local temp file (read to present real time results to screen)
    #
    # TO DO: Temp files are a poor way to track multiple subshells - improve?
    #
    # run jmeter test plan
    cLog "Starting jmeter on:"
    for counter in ${!hosts[@]} ; do
        cLog ${hosts[$counter]}
        # all none empty optional parameters (like propfile, logfile etc) 
        # will be appended to the command
        # if they're empty then nothing will apear in the command
        ( ssh -nq -o StrictHostKeyChecking=no \
        -p $REMOTE_PORT \
        -i $PEM_PATH/$PEM_FILE $USER@${hosts[$counter]} \
        $REMOTE_HOME/$JMETER_VERSION/bin/jmeter.sh -n \
        -t $REMOTE_HOME/execute.jmx \
        -l $REMOTE_HOME/$project-$DATETIME-$counter.jtl \
        $propfile \
        >> $LOCAL_HOME/projects/$project/$DATETIME-${hosts[$counter]}-jmeter.out ) &
    done
    echo
    echo
}

function runtest() {
    # sleep_interval - how often we poll the jmeter output for results
    # this value should be the same as the Generate Summary Results interval set in jmeter.properties
    # to be certain, we read the value in here and adjust the wait to match (this prevents lots of duplicates being written to the screen)
    sleep_interval=$(awk 'BEGIN { FS = "\=" } ; /summariser.interval/ {print $2}' $LOCAL_HOME/jmeter.properties)
    runningtotal_seconds=$(echo "$RUNNINGTOTAL_INTERVAL * $sleep_interval" | bc)
	# $epoch is used when importing to mysql (if enabled) because we want unix timestamps, not datetime, as this works better when graphing.
	epoch_seconds=$(date +%s) 
	epoch_milliseconds=$(echo "$epoch_seconds* 1000" | bc) # milliseconds since Mick Jagger became famous
	start_date=$(date) # warning, epoch and start_date do not (absolutely) equal each other!
	if [ ! -z "$DB_HOST" ] ; then
		# mark test as running in database
		updateTest 1 "$newTestid" 0 "$release" "$project" "$env" "$comment" "$epoch_milliseconds"
	fi
    echo "JMeter started at $start_date"
    echo "===================================================================== START OF JMETER-EC2 TEST ================================================================================"
    echo "> [updates: every $sleep_interval seconds | running total: every $runningtotal_seconds seconds]"
    echo ">"
    echo "> waiting for the test to start...to stop the test while it is running, press CTRL-C"
    teststarted=1
    # TO DO: Are thse required?
    count_total=0
    avg_total=0
    count_overallhosts=0
    avg_overallhosts=0
    tps_overallhosts=0
    errors_overallhosts=0
    i=1
    firstmodmatch="TRUE"
    res=0
    # changed the condition from '!=' to '-lt'
    # due to modified grep in the last line of the while loop, that looks
    # for either the regular "...end of run" or the "Fatal error"
    # This modified grep can return $res greater than $instance_count
    # which was causing script to continue
    while [ $res -lt $instance_count ] ; do # test not complete (count of matches for 'end of run' not equal to count of hosts running the test)
        # gather results data and write to screen for each host
        #while read host ; do
        for host in ${hosts[@]} ; do
            check=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $1}') # make sure the test has really started to write results to the file
            if [[ -n "$check" ]] ; then # not null
                if [ $check == "Generate" ] ; then # test has begun
                    screenupdate=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1)
                    echo "> $(date +%T): $screenupdate | host: $host" # write results to screen
                    
                    # get the latest values
                    count=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $5}') # pull out the current count
                    avg=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $11}') # pull out current avg
                    tps_raw=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $9}') # pull out current tps
                    errors_raw=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $17}') # pull out current errors
                    tps=${tps_raw%/s} # remove the trailing '/s'
                    
                    # get the latest summary values
                    count_total=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $5}')
                    avg_total=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $11}')
                    tps_total_raw=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $9}')
                    tps_recent_raw=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $9}')
                    tps_total=${tps_total_raw%/s} # remove the trailing '/s'
                    tps_recent=${tps_recent_raw%/s} # remove the trailing '/s'
                    errors_total=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $17}')
                    
                    count_overallhosts=$(echo "$count_overallhosts+$count_total" | bc) # add the value from this host to the values from other hosts
                    avg_overallhosts=$(echo "$avg_overallhosts+$avg" | bc)
                    tps_overallhosts=$(echo "$tps_overallhosts+$tps_total" | bc) 
                    tps_recent_overallhosts=$(echo "$tps_recent_overallhosts+$tps_recent" | bc)
                    errors_overallhosts=$(echo "$errors_overallhosts+$errors_total" | bc) # add the value from this host to the values from other hosts
                fi
            fi
        done #<<<"${hosts_str}" # next host
        
        # calculate the average respone time over all hosts
        avg_overallhosts=$(echo "$avg_overallhosts/$instance_count" | bc)
        
        # every RUNNINGTOTAL_INTERVAL loops print a running summary (if each host is running)
        mod=$(echo "$i % $RUNNINGTOTAL_INTERVAL"|bc)
        if [ $mod == 0 ] ; then
            if [ $firstmodmatch == "TRUE" ] ; then # don't write summary results the first time (because it's not useful)
                firstmodmatch="FALSE"
            else
                # first check the results files to make sure data is available
                wait=0
                for host in ${hosts[@]} ; do
                    result_count=$(grep -c "Results =" $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out)
                    if [ $result_count = 0 ] ; then
                        wait=1
                    fi
                done
                
                # now write out the data to the screen
                if [ $wait == 0 ] ; then # each file is ready to summarise
                    for host in ${hosts[@]} ; do
                        screenupdate=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1)
                        echo "> $(date +%T): $screenupdate | host: $host" # write results to screen
                    done
                    echo ">"
                    echo "> $(date +%T): [RUNNING TOTALS] total count: $count_overallhosts, current avg: $avg_overallhosts (ms), average tps: $tps_overallhosts (p/sec), recent tps: $tps_recent_overallhosts (p/sec), total errors: $errors_overallhosts"
                    echo ">"
                fi
            fi
        fi
        i=$(( $i + 1))
        
        sleep $sleep_interval
        
        # we rely on JM to keep track of overall test totals (via Results =) so we only need keep count of values over multiple instances
        # there's no need for a running total outside of this loop so we reinitialise the vars here.
        count_total=0
        avg_total=0
        count_overallhosts=0
        avg_overallhosts=0
        tps_overallhosts=0
        tps_recent_overallhosts=0
        errors_overallhosts=0


        # check to see if the test is complete or the was a Fatal Error
        # the awk command here sums up the output if multiple matches were found
        res=$(grep -c "end of run\|Fatal error" $LOCAL_HOME/projects/$project/$DATETIME*jmeter.out | awk -F: '{ s+=$NF } END { print s }')
    done # test complete


    # check if test didn't stop in a 'fatal' way. 
    # if it happens then there will be no "end of run" in the jmeter log 
    # and script will be running in an infinite loop while JMeter already stopped
    # Expected error msg: "Fatal error, could not stop test, exitting"
    fatalErrors=$(grep -c "Fatal error" $LOCAL_HOME/projects/$project/$DATETIME*jmeter.out | awk -F: '{ s+=$NF } END { print s }')
    if [ $fatalErrors -gt 0 ] ; then
        cErr "JMeter unexpectedly stopped with a fatal error on one of the nodes (check all *jmeter.out files)."
        cErr "Number of fatal errors: ${fatalErrors}"
        # check if we're running a list of pre-defined hosts to run tests
        # if so, then make sure that there are no other instances of JMeter running
        if [ ! -z "$REMOTE_HOSTS" ]; then
            cLog "Checking if JMeter and Server Agent is still running on any of the hosts..."
            for host in ${hosts[@]} ; do
                ( ssh -nq -o StrictHostKeyChecking=no \
                -i $PEM_PATH/$PEM_FILE $USER@${host} -p $REMOTE_PORT \
                pkill -f ApacheJMeter.jar && { echo "Killed JMeter running on ${host}"; } > $LOCAL_HOME/projects/$project/kill.txt )

                # show on which node jmeter was killed
                if [ -e $LOCAL_HOME/projects/$project/kill.txt ]; then
                    cWarn "$(cat $LOCAL_HOME/projects/$project/kill.txt)"
                    rm $LOCAL_HOME/projects/$project/kill.txt
                fi

                ( ssh -nq -o StrictHostKeyChecking=no \
                -i $PEM_PATH/$PEM_FILE $USER@${host} -p $REMOTE_PORT \
                "pkill -f CMDRunner.jar")
            done
        fi;
    fi


    # now the test is complete calculate a final summary and write to the screen
    for host in ${hosts[@]} ; do
        # get the final summary values
        count_total=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $5}')
        avg_total=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $11}')
        tps_total_raw=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $9}')
        tps_total=${tps_total_raw%/s} # remove the trailing '/s'
        tps_recent_raw=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $9}')
        tps_recent=${tps_recent_raw%/s} # remove the trailing '/s'
        errors_total=$(tail -10 $LOCAL_HOME/projects/$project/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $17}')
        
        # running totals
        count_overallhosts=$(echo "$count_overallhosts+$count_total" | bc) # add the value from this host to the values from other hosts
        avg_overallhosts=$(echo "$avg_overallhosts+$avg_total" | bc)
        tps_overallhosts=$(echo "$tps_overallhosts+$tps_total" | bc) # add the value from this host to the values from other hosts
		tps_recent_overallhosts=$(echo "$tps_recent_overallhosts+$tps_recent" | bc)
        errors_overallhosts=$(echo "$errors_overallhosts+$errors_total" | bc) # add the value from this host to the values from other hosts
    done
    
    # calculate averages over all hosts
    avg_overallhosts=$(echo "$avg_overallhosts/$instance_count" | bc)
}


function runcleanup() {
	# Turn off the CTRL-C trap now that we are already in the runcleanup function
	trap - INT 
	
    if [ "$teststarted" -eq 1 ] ; then
        # display final results
        echo ">"
        echo ">"
        echo "> $(date +%T): [FINAL RESULTS] total count: $count_overallhosts, overall avg: $avg_overallhosts (ms), overall tps: $tps_overallhosts (p/sec), recent tps: $tps_recent_overallhosts (p/sec), errors: $errors_overallhosts"
        echo ">"
        echo "===================================================================== END OF JMETER-EC2 TEST =================================================================================="
        echo
        echo
    fi

      
    # download the results
    for i in ${!hosts[@]} ; do
        cLog "\nkilling server agent on ${hosts[$i]}... \n"
        ( ssh -nq -o StrictHostKeyChecking=no \
        -i $PEM_PATH/$PEM_FILE $USER@${hosts[$i]} \
        -p $REMOTE_PORT \
        "pkill -f CMDRunner.jar")

        cLog "downloading results from ${hosts[$i]}..."
        scp -q -C -o UserKnownHostsFile=/dev/null \
                                     -o StrictHostKeyChecking=no \
                                     -i $PEM_PATH/$PEM_FILE \
                                     -P $REMOTE_PORT \
                                     $USER@${hosts[$i]}:$REMOTE_HOME/$project-$DATETIME-$i.jtl \
                                     $LOCAL_HOME/projects/$project/ \
        && {
            cLog "Successfully downloaded $project-$DATETIME-$i.jtl to $LOCAL_HOME/projects/$project/$project-$DATETIME-$i.jtl"
        } || {
            cWarn "There was a problem with downloading $project-$DATETIME-$i.jtl !"
        }

        # remotely zip result files
        # -j - Store just the name of a saved file (junk the path), and do  not
        #      store  directory names. By default, zip will store the full path
        #      (relative to the current directory).
        cLog "Attempting to remotely zip all result files on ${hosts[$i]}"
        ( ssh -nq -o StrictHostKeyChecking=no \
        -i $PEM_PATH/$PEM_FILE $USER@${hosts[$i]} -p $REMOTE_PORT \
        zip -j -r $REMOTE_HOME/$DATETIME-$i-jtls.zip $REMOTE_HOME/data/*.jtl) \
        && {
            cLog "Result files were remotely zipped on ${hosts[$i]}"
        } || {
            cWarn "Something went wrong with remotely zipping results on ${hosts[$i]}"
        }

        # download zipped results
        scp -q -C -o UserKnownHostsFile=/dev/null \
                                     -o StrictHostKeyChecking=no \
                                     -i $PEM_PATH/$PEM_FILE \
                                     -P $REMOTE_PORT \
                                     $USER@${hosts[$i]}:$REMOTE_HOME/$DATETIME-$i-jtls.zip \
                                     $LOCAL_HOME/projects/$project/$DATETIME-$i-jtls.zip \
        && {
            cLog "$DATETIME-$i-jtls.zip was downloaded successfully from ${hosts[$i]}"
        } || {
            cWarn "There was a problem with downloading: $DATETIME-$i-jtls.zip from ${hosts[$i]}!"
        }


        # deleteting all remote crap
        # had to split it in multiple lines to avoid situation when one of the
        # RMs fails and prevents remaining commands from execution
        ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
        rm -f $REMOTE_HOME/*.jtl)
        ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
        rm -f $REMOTE_HOME/*.zip)
        ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
        rm -f $REMOTE_HOME/*.jmx)
        ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
        rm -f $REMOTE_HOME/*.log)
        ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
        rm -f $REMOTE_HOME/*.out)
        ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
        rm -f $REMOTE_HOME/install.sh)
        ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
        rm -f $REMOTE_HOME/*.properties)
        ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
        rm -fr $REMOTE_HOME/data)
        ( ssh -nq -o StrictHostKeyChecking=no -i $PEM_PATH/$PEM_FILE -p $REMOTE_PORT $USER@${hosts[$i]} \
        rm -fr $REMOTE_HOME/cfg)
        cLog "All remote files were deleted"

    done
    
    
    # terminate any running instances created
    if [ -z "$REMOTE_HOSTS" ]; then
		if [ "$terminate" = "TRUE" ] ; then
	        cLog "terminating instance(s)..."
			# We use attempted_instanceids here to make sure that there are no orphan instances left lying around
	        ec2-terminate-instances --region $REGION ${attempted_instanceids[@]}
	        echo
		fi
    fi
    

    # tail last 10 lines of remote JMeter logs
    # this is helpful to determine the reason when test stops abruptly
    if ${cfgTailRemoteJmeterLogs} ; then
        for i in ${!hosts[@]} ; do
            if [ -e ${LOCAL_HOME}/projects/${project}/${DATETIME}-${hosts[$i]}-jmeter.out ] ; then
                cLog "/--------------------------------------------------------"
                cLog "-"
                cLog "-"
                cLog "- Tailing last 10 lines of remote JMeter log: ${LOCAL_HOME}/projects/${project}/${DATETIME}-${hosts[$i]}-jmeter.out"
                cLog "-"
                cLog "-"
                # set nice color for the output :)
                tput setaf 6; tput bold;
                tail -n10 ${LOCAL_HOME}/projects/${project}/${DATETIME}-${hosts[$i]}-jmeter.out
                # revert colors to default
                tput setaf default; tput sgr0; 
                cLog "-"
                cLog "-"
                cLog "/--------------------------------------------------------"
            fi
        done
    else
        cWarn "Tailing last 10 lines of remote JMeter logs is disabled!"
    fi

    ###########################################################################
    # Process the result files into one jtl results file.
    # This combined result file is used to calculate the test run time and
    # for injecting results into a database
    #
    # Steps:
    # 0 - concatenate all result files into one
    # 1 - sort the file
    # 2 - insert new TESTID
    # 3 - Remove blank lines
    # 4 - Remove any lines containing "0,0,Error:"
    # 5 - Calclulate test duration
    # 6 - mark test as complete in database
    #
    #
    cLog "Processing result files to calculate test duration etc..."
    for (( i=0; i<$instance_count; i++ )) ; do
        cat $LOCAL_HOME/projects/$project/$project-$DATETIME-$i.jtl >> $LOCAL_HOME/projects/$project/$project-$DATETIME-grouped.jtl
        rm $LOCAL_HOME/projects/$project/$project-$DATETIME-$i.jtl # removes the individual results files (from each host) - might be useful to some people to keep these files?
    done	
	#
	# Sort File
    sort -u $LOCAL_HOME/projects/$project/$project-$DATETIME-grouped.jtl >> $LOCAL_HOME/projects/$project/$project-$DATETIME-sorted.jtl
    #
    # Insert TESTID
    if [ ! -z "$DB_HOST" ] ; then
        awk -v v_testid="$newTestid," '{print v_testid,$0}' $LOCAL_HOME/projects/$project/$project-$DATETIME-sorted.jtl >> $LOCAL_HOME/projects/$project/$project-$DATETIME-appended.jtl
	else
        mv $LOCAL_HOME/projects/$project/$project-$DATETIME-sorted.jtl $LOCAL_HOME/projects/$project/$project-$DATETIME-appended.jtl
    fi
    #
	# Remove blank lines
	sed '/^$/d' $LOCAL_HOME/projects/$project/$project-$DATETIME-appended.jtl >> $LOCAL_HOME/projects/$project/$project-$DATETIME-noblanks.jtl
    #
	# Remove any lines containing "0,0,Error:" - which seems to be an intermittant bug in JM where the getTimestamp call fails with a nullpointer
	sed '/^0,0,Error:/d' $LOCAL_HOME/projects/$project/$project-$DATETIME-noblanks.jtl >> $LOCAL_HOME/projects/$project/$project-$DATETIME-complete.jtl
    #
	# Calclulate test duration
	start_time=$(head -1 $LOCAL_HOME/projects/$project/$project-$DATETIME-complete.jtl | cut -d',' -f1)
	end_time=$(tail -1 $LOCAL_HOME/projects/$project/$project-$DATETIME-complete.jtl | cut -d',' -f1)
    # because jmeter is using a milisecond timestamp we have to divide
    # the timedifference by 1000
    duration=$(echo "($end_time-$start_time)/1000" | bc)
    #
	if [ ! $duration > 0 ] ; then
		duration=0;
	fi
    #
    msDatetimeToDate start_date ${start_time}
    msDatetimeToDate end_date ${end_time}
    cLog ""
    cLog "Test was started: ${start_date}"
    cLog "Test ended: ${end_date}"
    cLog "Test duration: ${duration} seconds"
    cLog ""
	#
	if [ ! -z "$DB_HOST" ] ; then
		# mark test as complete in database
		updateTest 2 "$newTestid" "$duration"
	fi
    #
    # end of proccessing jtl result files
    ############################################################################
	

    ############################################################################
    # Process downloaded compressed result files.
    # In next few steps we're combinining all result files downloaded 
    # from the load generators to create a single result file, which will be
    # used to generate graphs using CMDRunner.jar 
    # http://jmeter-plugins.org/wiki/JMeterPluginsCMD/
    # 
    #
    # Steps:
    # 0 - create temporary "jtls" folder for unpacked files from each result file
    # 1 - extract all downloaded result files
    # 2 - merge all the result files
    # 3 - sort the result file
    # 4 - remove blank lines
    # 5 - Remove lines with some intermittant errors
    # 6 - Move last line to the beggining (it's due to the sort from step 3)
    #
    if ${cfgCreateMergedResultFile} ; then
        cLog "Creating merged result file..."
        #
        # create folder for merged JTLs
        mkdir $LOCAL_HOME/projects/$project/jtls
        #
        cLog "Extracting zipped result files"
        for (( i=0; i<$instance_count; i++ )) ; do
            #unzip $LOCAL_HOME/projects/$project/$DATETIME-$i-jtls.zip -d $LOCAL_HOME/projects/$project/$i
            # retry unzippin results file if it takes too long
            CMD="unzip $LOCAL_HOME/projects/$project/$DATETIME-$i-jtls.zip -d $LOCAL_HOME/projects/$project/$i"
            repeatTillSucceedWithExecTimeout 5 60 "${CMD}" \
                || {
                    cErr "Failed to unzip $LOCAL_HOME/projects/$project/$DATETIME-$i-jtls.zip !!!!!!!!!!!!1"
                }
        done
        #
        cLog "Merging all the result files"
        for (( i=0; i<$instance_count; i++ )) ; do
            # I'm merging only the "result" files, because all of the jp@gc listeners are generating the same files
            cat $LOCAL_HOME/projects/$project/$i/result.jtl >> $LOCAL_HOME/projects/$project/${DATETIME}-results-grouped.jtl
        done
        #
        cLog "Processing grouped result file"
        cLog "Sorting ${DATETIME}-results-grouped.jtl > ${DATETIME}-results-sorted.jtl"
        sort -u $LOCAL_HOME/projects/$project/${DATETIME}-results-grouped.jtl > $LOCAL_HOME/projects/$project/${DATETIME}-results-sorted.jtl
        #
        cLog "Removing blank lines from ${DATETIME}-results-sorted.jtl > ${DATETIME}-results-noblanks.jtl"
        sed '/^$/d' $LOCAL_HOME/projects/$project/${DATETIME}-results-sorted.jtl  > $LOCAL_HOME/projects/$project/${DATETIME}-results-noblanks.jtl
        #
        cLog "Removing lines with some intermittant errors from ${DATETIME}-results-noblanks.jtl > ${DATETIME}-results-sorted.jtl"
        sed '/^0,0,Error:/d' $LOCAL_HOME/projects/$project/${DATETIME}-results-noblanks.jtl  > $LOCAL_HOME/projects/$project/${DATETIME}-results-noErrors.jtl
        #
        cLog "Moving last line to the beggining from ${DATETIME}-results-noErrors.jtl > ${DATETIME}-results-complete.jtl"
        sed '1h;1d;$!H;$!d;G' $LOCAL_HOME/projects/$project/${DATETIME}-results-noErrors.jtl  > $LOCAL_HOME/projects/$project/jtls/${DATETIME}-results-complete.jtl \
            && {
                cLog "Merged result file was successfully created"
            }
    else
        cWarn "Creating merged result file is disabled!"
    fi
    #
    # end of processing result files
    #
    ############################################################################

   
    ############################################################################
    # Prepare a merged XML result file that will be processed by the 
    # Jenkins Performance Plugin. For merging we're going to use mergex tool:
    # https://code.google.com/p/mergex/ by bbeirnaert
    #
    # Steps:
    # 0 - check if jenkins.jtl file exists in the node 0 folder
    # 1 - create merged folder
    # 2 - remove first and last 2 lines and save output to merged dir
    # 3 - merge'em into one XML file using cat
    # 4 - create final result file by adding XML tags and appending merged.jtl
    # 5 - delete merged folder
    if ${cfgCreateMergedFileForJenkinsPerfPlugin} ; then
        if [ -e $LOCAL_HOME/projects/$project/0/jenkins.jtl ]; then
            mkdir $LOCAL_HOME/projects/$project/merged
            for (( i=0; i<$instance_count; i++ )) ; do
                # remove first two lines and last 2 lines
                tail -n +3 $LOCAL_HOME/projects/$project/$i/jenkins.jtl | head -n -2 > $LOCAL_HOME/projects/$project/merged/jenkins-${i}.jtl
                # append '>>' file to merged.jtl file
                cat $LOCAL_HOME/projects/$project/merged/jenkins-${i}.jtl >> $LOCAL_HOME/projects/$project/merged/merged.jtl
            done
            cLog "All JTL files were merged successfully into: $LOCAL_HOME/projects/$project/merged/merged.jtl"
            # create final result file and add opening XML tags
            echo '<?xml version="1.0" encoding="UTF-8"?><testResults version="1.2">' > $LOCAL_HOME/projects/$project/results/${cfgJenkinsPerfPluginResultFilename}
            # append merged JTLs files
            cat $LOCAL_HOME/projects/$project/merged/merged.jtl >> $LOCAL_HOME/projects/$project/results/${cfgJenkinsPerfPluginResultFilename}
            # append closing tag
            echo '</testResults>' >> $LOCAL_HOME/projects/$project/results/${cfgJenkinsPerfPluginResultFilename}
            cLog "Final result file for Jenkins Performance Plugin was saved to: $LOCAL_HOME/projects/$project/results/${cfgJenkinsPerfPluginResultFilename}"
            rm -fr $LOCAL_HOME/projects/$project/merged
        else
            cWarn "Couldn't find jenkins.jtl file in the $LOCAL_HOME/projects/$project/0/ folder!!!!"
        fi;
    else
        cWarn "Merging all jenkins.xml files is disabled!"
    fi;
    #
    # end of creating merged result file for jenkins performance plugin
    ############################################################################
  

    ############################################################################
    # tar+bzip2 or zip separate result file into a single archive that will be
    # stored in the results folder as a part of a Jenkins build artifact
    #
    # Steps:
    # 0 - check if cfgSaveCompressedResults flag is true
    # 1 - depending which compression tool is available (bzip2 or zip) use it to archive all the result files of your interest
    #
    if ${cfgSaveCompressedResults} ; then
        if `isInstalled "bzip2"` ; then
            cLog "BZipping separate result files and remote Jmeter log files into a single archive ${LOCAL_HOME}/projects/${project}/results/results.tar.bz2"
            cd ${LOCAL_HOME}/projects/$project \
                && {
                    time tar cvfj ./results/results.tar.bz2 $DATETIME-*.zip $DATETIME*.out $project-$DATETIME-complete.jtl
                    cd ${LOCAL_HOME}
                } || {
                    cWarn "Something went wrong when compressing result files!"
                }
            cd ${LOCAL_HOME}
        else 
            cLog "Zipping separate result files and remote JMeter log files into a single archive ${LOCAL_HOME}/projects/${project}/results/results.zip"
            cd ${LOCAL_HOME}/projects/$project \
                && {
                    time zip -9 -j -r results/results.zip $DATETIME-*.zip $DATETIME*.out $project-$DATETIME-complete.jtl
                    cd ${LOCAL_HOME}
                } || {
                    cWarn "Something went wrong when compressing result files!"
                }
            cd ${LOCAL_HOME}
        fi
    else
        cWarn "Saving compressed result file is disabled!"
    fi
    #
    #
    ############################################################################




    ########################################################################
    # Generates CSV files representing aggregate response time percentiles reports
    ## Such file can be then easily processed by Jenkins' Plot Plugin
    ########################################################################
    if ${cfgGenerateAggregatedResponseTimePercentilesReports} ; then
        cLog "Generating CSV Response Times Percentiles report..."
        CMD="java -Djava.awt.headless=true -jar $LOCAL_HOME/${JMETER_VERSION}/lib/ext/CMDRunner.jar --loglevel WARN --tool Reporter --generate-csv $LOCAL_HOME/projects/$project/aggregatePercentiles.tmp --input-jtl $LOCAL_HOME/projects/$project/jtls/${DATETIME}-results-complete.jtl --plugin-type ResponseTimesPercentiles"
        repeatTillSucceedWithExecTimeout 5 ${cfgGraphGenerationTimeout} "${CMD}" \
        && {
            cLog "Extracting values for 50th,60th,70th,80th,90th & 95th percentiles..."
            head -n 1 $LOCAL_HOME/projects/$project/aggregatePercentiles.tmp > ${cfgAggregatedResponseTimePercentilesReportsInputFile} ;
            grep ^50.0 $LOCAL_HOME/projects/$project/aggregatePercentiles.tmp >> ${cfgAggregatedResponseTimePercentilesReportsInputFile} ;
            grep ^60.0 $LOCAL_HOME/projects/$project/aggregatePercentiles.tmp >> ${cfgAggregatedResponseTimePercentilesReportsInputFile} ;
            grep ^70.0 $LOCAL_HOME/projects/$project/aggregatePercentiles.tmp >> ${cfgAggregatedResponseTimePercentilesReportsInputFile} ;
            grep ^80.0 $LOCAL_HOME/projects/$project/aggregatePercentiles.tmp >> ${cfgAggregatedResponseTimePercentilesReportsInputFile} ;
            grep ^90.0 $LOCAL_HOME/projects/$project/aggregatePercentiles.tmp >> ${cfgAggregatedResponseTimePercentilesReportsInputFile} ;
            grep ^95.0 $LOCAL_HOME/projects/$project/aggregatePercentiles.tmp >> ${cfgAggregatedResponseTimePercentilesReportsInputFile} ;

            # process the file from previous step
            cLog "Generating aggregate response time percentiles for each endpoint from : ${cfgAggregatedResponseTimePercentilesReportsInputFile}" ;
            cLog "Transposing columns and values from: ${cfgAggregatedResponseTimePercentilesReportsInputFile} into: ${cfgAggregatedResponseTimePercentilesReportsOuputFolder}" ;

            #${cfgPython} $LOCAL_HOME/genAggregateRepsTimesPercentilesReports.py -i ${cfgAggregatedResponseTimePercentilesReportsInputFile} -o ${cfgAggregatedResponseTimePercentilesReportsOuputFolder} -d \
            CMD="${cfgPython} $LOCAL_HOME/genAggregateRepsTimesPercentilesReports.py -i ${cfgAggregatedResponseTimePercentilesReportsInputFile} -o ${cfgAggregatedResponseTimePercentilesReportsOuputFolder} -d"
            repeatTillSucceedWithExecTimeout 5 10 "${CMD}" \
                && {
                    cLog "Response Times Percentiles Report was successfully transposed and saved in: ${cfgAggregatedResponseTimePercentilesReportsOuputFolder}"
                } || {
                    cLog "Something went wrong when transposing ${cfgAggregatedResponseTimePercentilesReportsInputFile}!!!!!"
                }

            # delete tmp file
            rm $LOCAL_HOME/projects/$project/aggregatePercentiles.tmp ;
        } || {
            cErr "Failed to create an aggregate response time percentiles CSV report!" ;
        }
    else
        cWarn "Generating Aggregate Response Times Percentile CSV report is disabled!"
    fi;


    ########################################################################
    # Generate aggregated CSV report
    # which can be then easily used by Jenkins' Plot plugin to generate
    # a perfromance trend graph.
    # For more details please refer to:
    # http://jmeter-plugins.org/wiki/JMeterPluginsCMD/#Plugin-Type-Classes
    # http://jmeter.apache.org/usermanual/component_reference.html#Aggregate_Report
    ########################################################################
    if ${cfgCreateAggregateCSVReport} ; then
        cLog "Generating an Aggregate CSV report from '${DATETIME}-results-complete.jtl' file"
        CMD="java -Djava.awt.headless=true -jar $LOCAL_HOME/${JMETER_VERSION}/lib/ext/CMDRunner.jar --loglevel WARN --tool Reporter --generate-csv $LOCAL_HOME/projects/$project/aggregate.tmp --input-jtl $LOCAL_HOME/projects/$project/jtls/${DATETIME}-results-complete.jtl --plugin-type AggregateReport"
        repeatTillSucceedWithExecTimeout 5 ${cfgGraphGenerationTimeout} "${CMD}" \
        && { 
            # Removing unwanted "aggregate_report_" field name prefix from the 
            # Aggregate Report generated by the CMDRunner.jar
            cLog "Fixing field names in the Aggregated report..."
            sed 's/aggregate_report_//g' $LOCAL_HOME/projects/$project/aggregate.tmp > $LOCAL_HOME/projects/$project/results/aggregate.csv
            cLog "Current aggregate CSV report: $LOCAL_HOME/projects/$project/results/aggregate.csv"
            # set nice color for the output :)
            tput setaf 6; tput bold;
            cat $LOCAL_HOME/projects/$project/results/aggregate.csv
            # revert colors to default
            tput setaf default; tput sgr0; 
            rm $LOCAL_HOME/projects/$project/aggregate.tmp
        } || { 
            cErr "Failed to create an aggregate CSV report!" 
        }
    else
        cWarn "Generating aggregate CSV report is disabled!"
    fi;
   

	############################################################################
    # Generate HTML repot with all the PNG graphs
    # 
    #
    # Steps:
    # 
    # 0 - 
    # 1 - 
    # 2 - 
    # 3 - 
    # 4 - 
    # 5 - 
    # 6 - 
    # 7 - 
    # 8 - 
    #
    # declare all types of reports that we want to generate    
    declare -a results=('ResponseTimesOverTime' 'LatenciesOverTime' 'ResponseTimesDistribution' 'ResponseTimesPercentiles' 'BytesThroughputOverTime' 'HitsPerSecond' 'ResponseCodesPerSecond' 'TimesVsThreads' 'TransactionsPerSecond' 'ThroughputVsThreads' 'ThreadsStateOverTime');
    declare -a graphsWithoutRelTimeParam=("ResponseTimesDistribution" "ResponseTimesPercentiles" "TimesVsThreads" "ThroughputVsThreads");
    #
    #
    # 
    if ! ${cfgCreateHTMLReport} ; then
        cWarn "Generating HTML report is disabled"
    else
        cLog "Generating HTML Report"
        if  [ -d $LOCAL_HOME/${JMETER_VERSION} ] && [[ -n $(ls $LOCAL_HOME/${JMETER_VERSION}/) ]] ; then
         
            # if folder for graphs doesn't exist, create it
            if [ ! -d "$LOCAL_HOME/projects/$project/results/${cfgHtmlReportGraphsDir}" ] ; then
                mkdir -p $LOCAL_HOME/projects/$project/results/${cfgHtmlReportGraphsDir}
            fi

            #***************************************************************************
            # copy bootstrap folder to report folder
            # replace all template keywords with variable
            #***************************************************************************
            cp -R $LOCAL_HOME/resources/bootstrap $LOCAL_HOME/projects/$project/results/${cfgHtmlReportGraphsDir}
            cat $LOCAL_HOME/resources/reportHeader.txt \
            | sed "s/*WIDTH\*/${cfgReportGraphWidth}/g" \
            | sed "s/*HEIGHT\*/${cfgReportGraphHeight}/g" \
            | sed "s/*FOLDER\*/${cfgHtmlReportGraphsDir}/g" \
            | sed "s/*TITLE\*/JMeter report for project: ${project} generated on: ${DATETIME}/g" \
            > $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename}

            # counter to define which carousel item is active
            # because slide index in the carousel starts from 0
            # and we want to mark only first slide as active 
            # we have to start the counter from "-1"
            # so that the slide numbers displayer before the name of the slide
            # are correct!!!!
            COUNTER=-1;
            # store initial graph resolution
            local INITIAL_width="${cfgReportGraphWidth}";
            local INITIAL_height="${cfgReportGraphHeight}";
            # generate all required graphs from the grouped results file
            for res in "${results[@]}"; do
                cfgReportGraphWidth=${INITIAL_width}; # just to make sure that values weren't overwritten
                cfgReportGraphHeight=${INITIAL_height};
                # don't add --relative-times parameter to some graphs
                insertRelativeTimeParam="--relative-times no"
                case "${graphsWithoutRelTimeParam[@]}" in *"${res}"*)
                    insertRelativeTimeParam=""
                    cfgReportGraphWidth=${cfgReportGraphWidthForGraphsWithRelativeTime}
                    cfgReportGraphHeight=${cfgReportGraphHeightForGraphsWithRelativeTime}
                    ;;
                esac;

                # set first graph as active
                if [ $COUNTER -eq -1 ]; then
                    active="active "
                    # increment counter so that we're no setting more items as active
                    let COUNTER=COUNTER+1
                else
                    active=""
                    # increment counter to add it to the graph name.
                    # can be used as the carousel index indicatr
                    let COUNTER=COUNTER+1
                fi

                cLog "Generating '${res}' graph from the '${DATETIME}-results-complete.jtl' file"
                CMD="java -Djava.awt.headless=true -jar $LOCAL_HOME/${JMETER_VERSION}/lib/ext/CMDRunner.jar --loglevel WARN --tool Reporter ${insertRelativeTimeParam} --generate-png $LOCAL_HOME/projects/$project/results/${cfgHtmlReportGraphsDir}/${res}.png --input-jtl $LOCAL_HOME/projects/$project/jtls/${DATETIME}-results-complete.jtl --plugin-type ${res} --width ${cfgReportGraphWidth} --height ${cfgReportGraphHeight}"
                repeatTillSucceedWithExecTimeout 5 ${cfgGraphGenerationTimeout} "${CMD}" \
                && {
                    # add link and graph image to the report
                    echo -e "
                    <div class='${active}item'>
                        <h3><a href='#${COUNTER}'>#${COUNTER}</a> <a href='#Define${res}'>${res}</a></h3> 
                        <img class='img-polaroid' src='${cfgHtmlReportGraphsDir}/${res}.png' width=${cfgReportGraphWidth} height=${cfgReportGraphHeight}>
                    </div>
                    " >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename} ;
                } || {
                    cErr "Failed to generate ${res} graph! It will be replaced by a placeholder image!" ;
                    echo -e "
                    <div class='${active}item'>
                        <h3><a href='#${COUNTER}'>#${COUNTER}</a> <a href='#Define${res}'>${res}</a></h3> 
                        <img class='img-polaroid' src='${cfgHtmlReportGraphsDir}/bootstrap/img/failedToGenerateGraph.png' width=${cfgReportGraphWidth} height=${cfgReportGraphHeight}>
                    </div>
                    " >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename} ;
                }
            done


            
            # process PerfMon result files for both remote nodes (SUT - System Under Test)
            # and also from "local" jmeter nodes to monitor their performance while
            # generating the traffic
            for (( i=0; i<$instance_count; i++ )) ; do

                # check if PerfMon-remote.jtl is available
                if [ -e $LOCAL_HOME/projects/$project/${i}/PerfMon-remote.jtl ]; then
                    # increment counter to add it to the graph name.
                    # can be used as the carousel index indicatr
                    let COUNTER=COUNTER+1
                    cLog "Generating a SUT 'PerfMon' graph from the node '${i}' from '${i}/PerfMon-remote.jtl' file"
                    CMD="java -Djava.awt.headless=true -jar $LOCAL_HOME/${JMETER_VERSION}/lib/ext/CMDRunner.jar --loglevel WARN --tool Reporter --relative-times no --generate-png $LOCAL_HOME/projects/$project/results/${cfgHtmlReportGraphsDir}/PerfMon-node${i}-remote.png --input-jtl $LOCAL_HOME/projects/$project/${i}/PerfMon-remote.jtl --plugin-type PerfMon --width ${cfgReportGraphWidth} --height ${cfgReportGraphHeight}"
                    repeatTillSucceedWithExecTimeout 5 ${cfgGraphGenerationTimeout} "${CMD}" \
                    && {
                        echo -e "
                        <div class='item'>
                            <h3><a href='#${COUNTER}'>#${COUNTER}</a> <a href='#DefinePerfMon'>Performance graph of the System Unded Test. Data collected from the jmeter node: ${i}</a></h3> 
                            <img class='img-polaroid' src='${cfgHtmlReportGraphsDir}/PerfMon-node${i}-remote.png' width=${cfgReportGraphWidth} height=${cfgReportGraphHeight}>
                        </div>
                        " >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename} ;
                    } || {
                        cErr "Failed to generate PerfMon graph! It will be replaced by a placeholder image!" ;
                        echo -e "
                        <div class='item'>
                            <h3><a href='#${COUNTER}'>#${COUNTER}</a> <a href='#DefinePerfMon'>FAILED TO GENERATE REMOTE PERF.MON GRAPH !!! </a></h3> 
                            <img class='img-polaroid' src='${cfgHtmlReportGraphsDir}/bootstrap/img/failedToGenerateGraph.png' width=${cfgReportGraphWidth} height=${cfgReportGraphHeight}>
                        </div>
                        " >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename} ;
                    }
                else
                    # increment counter to add it to the graph name.
                    # can be used as the carousel index indicatr
                    let COUNTER=COUNTER+1
                    cWarn "Node ${i} didn't return a PerfMon-remote.jtl file!!!"
                    echo -e "
                    <div class='item'>
                        <h2><a href='#${COUNTER}'>#${COUNTER}</a> <a class='text-error' href='#DefinePerfMon'>Performance graph for the SUT is MISSING</a></h2>
                        <div class='emptyCarouselItem'>
                            <blockquote class='text-error'>because jmeter-ec2 node no: ${i} did not return a PerfMon-remote.jtl file!!!</blockquote>
                        </div>
                    </div>
                    " >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename}
                fi;

                # check if PerfMon-local.jtl is available
                if [ -e $LOCAL_HOME/projects/$project/${i}/PerfMon-local.jtl ]; then
                    # increment counter to add it to the graph name.
                    # can be used as the carousel index indicatr
                    let COUNTER=COUNTER+1
                    cLog "Generating a 'PerfMon' graph for the jmeter node '${i}' from '${i}/PerfMon-local.jtl' file"
                    CMD="java -Djava.awt.headless=true -jar $LOCAL_HOME/${JMETER_VERSION}/lib/ext/CMDRunner.jar --loglevel WARN --tool Reporter --relative-times no --generate-png $LOCAL_HOME/projects/$project/results/${cfgHtmlReportGraphsDir}/PerfMon-node${i}-local.png --input-jtl $LOCAL_HOME/projects/$project/${i}/PerfMon-local.jtl --plugin-type PerfMon --width ${cfgReportGraphWidth} --height ${cfgReportGraphHeight}"
                    repeatTillSucceedWithExecTimeout 5 ${cfgGraphGenerationTimeout} "${CMD}" \
                    && {
                        echo -e "
                        <div class='item'>
                            <h3><a href='#${COUNTER}'>#${COUNTER}</a> <a href='#DefinePerfMon'>Performance graph of the jmeter node: ${i}</a></h3> 
                            <img src='${cfgHtmlReportGraphsDir}/PerfMon-node${i}-local.png' width=${cfgReportGraphWidth} height=${cfgReportGraphHeight}>
                        </div>
                        " >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename} ;
                    } || {
                        cErr "Failed to generate PerfMon graph! It will be replaced by a placeholder image!" ;
                        echo -e "
                        <div class='item'>
                            <h3><a href='#${COUNTER}'>#${COUNTER}</a> <a href='#DefinePerfMon'>FAILED TO GENERATE LOCAL PERF.MON GRAPH !!! </a></h3> 
                            <img class='img-polaroid' src='${cfgHtmlReportGraphsDir}/bootstrap/img/failedToGenerateGraph.png' width=${cfgReportGraphWidth} height=${cfgReportGraphHeight}>
                        </div>
                        " >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename} ;
                    }
                else
                    # increment counter to add it to the graph name.
                    # can be used as the carousel index indicatr
                    let COUNTER=COUNTER+1
                    cWarn "Node ${i} didn't return a Perf-Mon-local.jtl file!!!"
                    echo -e "
                    <div class='item'>
                        <h2><a href='#${COUNTER}'>#${COUNTER}</a> <a class='text-error' href='#DefinePerfMon'>Performance graph of the jmeter-ec2 node is MISSING</a></h2>
                        <div class='emptyCarouselItem'>
                            <blockquote class='text-error'>because jmeter-ec2 node no: ${i} did not return a PerfMon-local.jtl file!!!</blockquote>
                        </div>
                    </div>
                    " >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename}
                fi;

            done

            # add carousel's end to the report        
            cat $LOCAL_HOME/resources/reportCarouselEnd.txt >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename}



            #***************************************************************************
            # Generate graphs for each of the load generators
            #***************************************************************************
            if ${cfgCreateGraphsForEachLoadGenerator} ; then
                # add the opening DIV to the report        
                cat $LOCAL_HOME/resources/individualGraphsBegining.txt >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename}

                # process single result files
                # apart from PerfMon results (see loop above)
                for (( i=0; i<$instance_count; i++ )) ; do
                    for res in "${results[@]}"; do
                        # don't add --relative-times parameter to some graphs
                        insertRelativeTimeParam="--relative-times no"
                        case "${graphsWithoutRelTimeParam[@]}" in *"${res}"*)
                            insertRelativeTimeParam="";;
                        esac;
                        cLog "Generating '${res}' graph from node '${i}' from '${i}/${res}.jtl' file"
                        CMD="java -Djava.awt.headless=true -jar $LOCAL_HOME/${JMETER_VERSION}/lib/ext/CMDRunner.jar --loglevel WARN --tool Reporter ${insertRelativeTimeParam} --generate-png $LOCAL_HOME/projects/$project/results/${cfgHtmlReportGraphsDir}/node${i}-${res}.png --input-jtl $LOCAL_HOME/projects/$project/${i}/result.jtl --plugin-type ${res} --width ${cfgReportGraphWidth} --height ${cfgReportGraphHeight}"
                        repeatTillSucceedWithExecTimeout 5 ${cfgGraphGenerationTimeout} "${CMD}" \
                        && {
                            echo -e "\t\tNode: ${i}: <a href='${cfgHtmlReportGraphsDir}/node${i}-${res}.png' target='_blank'>${res}</a><br/>" >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename}
                        } || {
                            cErr "Failed to generate ${res} graph! It will be replaced by a placeholder image!" ;
                            echo -e "\t\tNode: ${i}: <a href='${cfgHtmlReportGraphsDir}/bootstrap/img/failedToGenerateGraph.png' target='_blank'>FAILED TO GENERATE: ${res}</a><br/>" >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename}
                        }
                    done
                done

                # add the closing DIV to the report        
                cat $LOCAL_HOME/resources/individualGraphsEnd.txt >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename}
            else
                cWarn "Generating individual graphs for each of the load generators is disabled!"
            fi; # end of: if ${cfgCreateGraphsForEachLoadGenerator} ...


            #***************************************************************************
            # add closing tags to the report
            #***************************************************************************
            cat $LOCAL_HOME/resources/reportFooter.txt >> $LOCAL_HOME/projects/$project/results/${cfgHtmlReportFilename}


        # end of IF checking whether JMeter is installed
        else
            cErr "JMeter is NOT installed, please run ./download-jmeter.sh"
        fi;
    fi; 
    #
    # end of generate graphs
    ############################################################################



	
	#***************************************************************************
	# IMPORT RESULTS TO MYSQL DATABASE - IF SPECIFIED IN PROPERTIES
	# scp import-results.sh
	if [ ! -z "$DB_HOST" ] ; then
	    echo -n "copying import-results.sh to database..."
	    (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
	                                  -i $DB_PEM_PATH/$DB_PEM_FILE -P $DB_SSH_PORT \
	                                  $LOCAL_HOME/import-results.sh \
	                                  $DB_PEM_USER@$DB_HOST:$REMOTE_HOME) &
		wait
		echo -n "done...."
	
	    # scp results to remote db
	    echo -n "uploading jtl file to database.."
	    (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
	                                  -i $DB_PEM_PATH/$DB_PEM_FILE -P $DB_SSH_PORT \
	                                  $LOCAL_HOME/projects/$project/$project-$DATETIME-complete.jtl \
	                                  $DB_PEM_USER@$DB_HOST:$REMOTE_HOME/import.csv) &
	    wait
	    echo -n "done...."

		# set permissions
	    (ssh -n -o StrictHostKeyChecking=no \
	        -i $DB_PEM_PATH/$DB_PEM_FILE $DB_PEM_USER@$DB_HOST -p $DB_SSH_PORT \
			"chmod 755 $REMOTE_HOME/import-results.sh")

	    # Import jtl to database...
	    echo -n "importing jtl file..."
	    (ssh -nq -o StrictHostKeyChecking=no \
	        -i $DB_PEM_PATH/$DB_PEM_FILE $DB_PEM_USER@$DB_HOST -p $DB_SSH_PORT \
	        "$REMOTE_HOME/import-results.sh \
						'localhost' \
						'$DB_NAME' \
						'$DB_USER' \
						'$DB_PSWD' \
						'$REMOTE_HOME/import.csv' \
						'$epoch_milliseconds' \
						'$release' \
						'$project' \
						'$env' \
						'$comment' \
						'$duration' \
						'$newTestid'" \
	        > $LOCAL_HOME/projects/$project/$DATETIME-import.out) &
    
	    # check to see if the install scripts are complete
	    res=0
		counter=0
	    while [ "$res" = 0 ] ; do # Import not complete 
	        echo -n .
	        res=$(grep -c "import complete" $LOCAL_HOME/projects/$project/$DATETIME-import.out)
			counter=$(($counter+1))
	        sleep $counter # With large files this step can take considerable time so we gradually increase wait times to prevent excess screen dottage
	    done
	    echo "done"
    	echo
	fi
	#***************************************************************************
    


    ############################################################################
    # Tidy up
	#
    # delete all tmp folder were we inflated all the zipped files with results
    for (( i=0; i<$instance_count; i++ )) ; do
        cLog "Removing folder: $LOCAL_HOME/projects/$project/$i"
        rm -fr $LOCAL_HOME/projects/$project/$i
    done

    # move combined results file to the results folder
    # this file will be processed by the Jenkins Performance plugin
    #mv $LOCAL_HOME/projects/$project/jtls/${DATETIME}-results-complete.jtl $LOCAL_HOME/projects/$project/results/

    # remove jtls folder with temporary grouped files used for generating graphs
    rm -fr $LOCAL_HOME/projects/$project/jtls/


    cLog "Removing all tmp merged files"
    rm $LOCAL_HOME/projects/$project/*.jtl

    # delete all the remote zipped result files
    rm $LOCAL_HOME/projects/$project/$DATETIME-*-jtls.zip \
        && {
            cLog "Deleted all zipped result files: $DATETIME-*-jtls.zip. You can still find them in the results archive in: results/results.zip or results/results.tar.bz2"
        } || {
            cWarn "Something went wrong when deleting $LOCAL_HOME/projects/$project/$DATETIME-*-jtls.zip"
        }
   
    # tidy up working files
    # for debugging purposes you could comment out these lines
    rm $LOCAL_HOME/projects/$project/$DATETIME*.out
    rm $LOCAL_HOME/projects/$project/working*
    #
    # end of tidying up step
    ############################################################################


    echo
    echo "   -------------------------------------------------------------------------------------"
    echo "                  jmeter-ec2 Automation Script - COMPLETE"
    echo
    echo "   Test Result file $project-$DATETIME-complete.jtl is in the: $LOCAL_HOME/projects/$project/results/results(tar.bz2/zip) archive"
    echo "   -------------------------------------------------------------------------------------"
    echo
}

function updateTest() {
	
	sqlstr="mysql -u $DB_USER -p$DB_PSWD $DB_NAME"
	
	function dosql {
		#echo "sqlstmt = '"$1"'"
		#echo "sqlstr = '"$sqlstr"'"
		sqlresult=$(ssh -nq -o StrictHostKeyChecking=no \
	        -i $DB_PEM_PATH/$DB_PEM_FILE $DB_PEM_USER@$DB_HOST -p $DB_SSH_PORT \
			"$sqlstr -e '$1'")
			
		#echo "sqlresult = '"$sqlresult"'"
	}
	
	case $1 in
		
		0)	#pending
			
			sqlcreate="CREATE TABLE IF NOT EXISTS  tests ( \
			  testid int(11) NOT NULL AUTO_INCREMENT, \
			  buildlife varchar(45) DEFAULT NULL, \
			  project varchar(45) DEFAULT NULL, \
			  environment varchar(45) DEFAULT NULL, \
			  duration varchar(45) DEFAULT NULL, \
			  comment varchar(45) DEFAULT NULL, \
			  startdate varchar(45) DEFAULT NULL, \
			  accepted varchar(45) DEFAULT NULL, \
			  status int(11) DEFAULT NULL, \
			  value9 varchar(45) DEFAULT NULL, \
			  value10 varchar(45) DEFAULT NULL, \
			  PRIMARY KEY (testid) \
			) ENGINE=MyISAM AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;"

			dosql "$sqlcreate"
			
			# Insert a new row in tests table,
					
			sqlInsertTestid="INSERT INTO $DB_NAME.tests (buildlife, project, environment, duration, comment, startdate, accepted, status) VALUES (\"$4\", \"$5\", \"$6\", \"0\", \"$7\", \"0\", \"N\", \"0\")"
			
			dosql "$sqlInsertTestid"
			
			# Get last testid
			sqlGetMaxTestid="SELECT max(testid) from $DB_NAME.tests"

			dosql "$sqlGetMaxTestid"

			newTestid=$(echo $sqlresult | cut -d ' ' -f2)
			;;
			
		1)	#running
			
			# Update status in tests
			sqlUpdateStatus="UPDATE $DB_NAME.tests SET status = 1, startdate = $8 WHERE testid = $2"		

			dosql "$sqlUpdateStatus"
			;;
			
		2)	#complete
			
			# Update status in tests
			sqlUpdateStatus="UPDATE $DB_NAME.tests SET status = 2, duration = $3 WHERE testid = $2"

			dosql "$sqlUpdateStatus"			
			;;
	esac
}

function control_c(){
	# Turn off the CTRL-C trap now that it has been invoked once already
	trap - INT
	
    # Stop the running test on each host
    echo
    echo "> Stopping test..."
    for f in ${!hosts[@]} ; do
        ( ssh -nq -o StrictHostKeyChecking=no \
        -i $PEM_PATH/$PEM_FILE $USER@${hosts[$f]} -p $REMOTE_PORT \
        $REMOTE_HOME/$JMETER_VERSION/bin/stoptest.sh ) &
    done
    wait
    echo ">"
    
    runcleanup
    exit
}

# trap keyboard interrupt (control-c)
trap control_c SIGINT

runsetup
runtest
runcleanup


