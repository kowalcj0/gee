#!/bin/bash
#
# Runs this script to install ec2 tools locally on your computer or
# when running on Jenkins
#
# Execute the jmeter-ec2.properties file, to get access to JMETER_VERSION variable
. jmeter-ec2.properties

pluginsVersion="JMeterPlugins-1.0.0"
pluginsLibsVersion="JMeterPlugins-libs-1.0.0"
serverAgentVersion="ServerAgent-2.2.1"

if  [ -d ./${JMETER_VERSION} ] && [[ -n $(ls ./${JMETER_VERSION}/) ]] ; then # don't try to upload any files if none present
    echo "JMETER is already present"
else
    echo "${JMETER_VERSION} folder doesn't exist or it is empty"
    echo "Downloading ${JMETER_VERSION}"
    wget -q http://mirror.rmg.io/apache//jmeter/binaries/${JMETER_VERSION}.zip -O ${JMETER_VERSION}.zip
    echo "${JMETER_VERSION} successfully downloaded"
    unzip -q ${JMETER_VERSION}.zip
    rm ${JMETER_VERSION}.zip

    echo "Downloading ${pluginsVersion}, ${pluginsLibsVersion} and ${serverAgentVersion}...."
    wget -q --progress=bar -O JMeterPlugins.zip http://jmeter-plugins.googlecode.com/files/${pluginsVersion}.zip
    wget -q --progress=bar -O JMeterPlugins-libs.zip http://jmeter-plugins.googlecode.com/files/${pluginsLibsVersion}.zip
    wget -q --progress=bar -O ServerAgent.zip http://jmeter-plugins.googlecode.com/files/${serverAgentVersion}.zip
    echo "Dowloading complete"

    unzip -q -o ServerAgent.zip -d ${JMETER_VERSION}/lib/ext # don't skip junk paths
    unzip -q -j -o JMeterPlugins.zip -d ${JMETER_VERSION}/lib/ext
    unzip -q -j -o JMeterPlugins-libs.zip -d ${JMETER_VERSION}/lib/ext

    rm ServerAgent.zip
    rm JMeterPlugins.zip
    rm JMeterPlugins-libs.zip
    echo "${pluginsVersion}, ${pluginsLibsVersion} and ${serverAgentVersion} was downloaded and extracted successfully"
fi;
