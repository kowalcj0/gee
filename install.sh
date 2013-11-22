#!/usr/bin/env bash
#
# jmeter-ec2 - Install Script (Runs on remote ec2 server)
#

REMOTE_HOME=$1
INSTALL_JAVA=$2
JMETER_VERSION=${3-apache-jmeter-2.10}

pluginsVersion="JMeterPlugins-Standard-1.1.2"
pluginsExtrasVersion="JMeterPlugins-Extras-1.1.2"
serverAgentVersion="ServerAgent-2.2.1"
jmeterDwnUrl="http://mirrors.enquira.co.uk/apache//jmeter/binaries/"
pluginsDwnUrl="http://jmeter-plugins.org/files/"

# Source the jmeter-ec2.properties file, establishing these constants.
. $REMOTE_HOME/jmeter-ec2.properties
echo "jmeter-ec2.properties was loaded";

function install_jmeter_plugins() {
    echo "Downloading jMeter-Plugins with dependencies"
    # download and inflate newer version of JMeterPlugins
    wget --progress=bar -O $REMOTE_HOME/JMeterPlugins.zip ${pluginsDwnUrl}${pluginsVersion}.zip \
                && {
                    echo "${pluginsVersion} successfully downloaded"
                    unzip -q -j -o $REMOTE_HOME/JMeterPlugins.zip -d $REMOTE_HOME/$JMETER_VERSION/lib/ext
                    rm $REMOTE_HOME/JMeterPlugins.zip
                } || {
                    echo "There was a problem when downloading: ${pluginsVersion}"
                    rm $REMOTE_HOME/JMeterPlugins.zip
                    exit 10
                }
    wget -q --progress=bar -O $REMOTE_HOME/JMeterPlugins-extras.zip ${pluginsDwnUrl}${pluginsExtrasVersion}.zip \
                && {
                    echo "${pluginsExtrasVersion} successfully downloaded"
                    unzip -q -j -o $REMOTE_HOME/JMeterPlugins-extras.zip -d $REMOTE_HOME/$JMETER_VERSION/lib/ext
                    rm $REMOTE_HOME/JMeterPlugins-extras.zip
                } || {
                    echo "There was a problem when downloading: ${pluginsExtrasVersion}"
                    rm $REMOTE_HOME/JMeterPlugins-extras.zip
                    exit 11
                }
    wget -q --progress=bar -O $REMOTE_HOME/ServerAgent.zip ${pluginsDwnUrl}${serverAgentVersion}.zip \
                && {
                    echo "${serverAgentVersion} successfully downloaded"
                    unzip -q -o $REMOTE_HOME/ServerAgent.zip -d $REMOTE_HOME/$JMETER_VERSION/lib/ext # don't skip junk paths
                    rm $REMOTE_HOME/ServerAgent.zip
                } || {
                    echo "There was a problem when downloading: ${serverAgentVersion}"
                    rm $REMOTE_HOME/ServerAgent.zip
                    exit 12
                }

    echo "jMeter-Plugins with dependencies were downloaded and extracted successfully"
    
}

function install_mysql_driver() {
    wget -q -O $REMOTE_HOME/mysql-connector-java-5.1.16-bin.jar https://s3.amazonaws.com/jmeter-ec2/mysql-connector-java-5.1.16-bin.jar
    mv $REMOTE_HOME/mysql-connector-java-5.1.16-bin.jar $REMOTE_HOME/$JMETER_VERSION/lib/
}

# will launch PerfMon locally
# can help track the performance of the local node
function launchPerfMonAgent() {
    pkill -f CMDRunner.jar && { echo "Killed a stale instance of Server Agent"; } 
    echo "Launching a PerfMon agent locally"
    nohup $REMOTE_HOME/$JMETER_VERSION/lib/ext/startAgent.sh --udp-port 0 --tcp-port 4444 > agent.out &
    echo "a PerfMon agent was launched locally "
}

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
#
# assign result to variable
# isZipInstalled=$(isProgramInstalled "zip")
isProgramInstalled() {
    command -v "${1}" >/dev/null 2>&1 || { local result=false; }
    echo ${result}
}


cd $REMOTE_HOME

# set the locale
# required by the apt-get to work properly
echo "setting locale-gen to en_GB.UTF-8"
sudo locale-gen en_GB.UTF-8


# update apt-get repo DB
echo "Running 'apt-get update' to resynchronize the package index files from their sources"
sudo apt-get update
echo "Resynchronizing package index files finished";


if [[ $(isProgramInstalled "zip") ]] ; then
    echo "zip is not installed"
    echo "Installing zip and unzip commands"
    sudo DEBIAN_FRONTEND=noninteractive apt-get -qqy install zip
    echo "zip command was installed properly"
fi;
if [[ $(isProgramInstalled "unzip") ]] ; then
    echo "unzip is not installed"
    sudo DEBIAN_FRONTEND=noninteractive apt-get -qqy install unzip
    echo "unzip command was installed properly"
fi;


if [ $INSTALL_JAVA -eq 1 ] ; then
    # install java
	#ubuntu
    echo "Installing java"
	sudo DEBIAN_FRONTEND=noninteractive apt-get -qqy install default-jre
    echo java -version
	wait
fi


if  [ -d $REMOTE_HOME/${JMETER_VERSION} ] && [[ -n $(ls $REMOTE_HOME/${JMETER_VERSION}/) ]] ; then # don't try to upload any files if none present
    echo "JMETER is already present"
else
    # install JMeter version 2.x
    echo "Downloading $JMETER_VERSION.tgz"
    wget -q -O $REMOTE_HOME/$JMETER_VERSION.tgz http://archive.apache.org/dist/jmeter/binaries/$JMETER_VERSION.tgz
    tar -xf $REMOTE_HOME/$JMETER_VERSION.tgz
    rm $REMOTE_HOME/$JMETER_VERSION.tgz

    # install JMeterPlugins
    if  [[ -f $REMOTE_HOME/${JMETER_VERSION}/lib/ext/JMeterPlugins.jar ]] ; then # don't try to download 
        echo "JMETER plugins are already present"
    else
        echo "installing jmeter-plugins from http://code.google.com/p/jmeter-plugins/"
        install_jmeter_plugins
    fi
    
    # install mysql jdbc driver
    install_mysql_driver
fi


echo "software installed"

# launch PerfMon locally
launchPerfMonAgent;


