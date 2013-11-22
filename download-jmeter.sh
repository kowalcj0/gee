#!/usr/bin/env bash
#
# Runs this script to install ec2 tools locally on your computer or
# when running on Jenkins
#
# if default config file is not present, then download jmeter 2.9
if [ -f "$LOCAL_HOME/jmeter-ec2.properties" ] ; then
    . jmeter-ec2.properties
else
    JMETER_VERSION="apache-jmeter-2.10"
fi

pluginsVersion="JMeterPlugins-Standard-1.1.2"
pluginsExtrasVersion="JMeterPlugins-Extras-1.1.2"
serverAgentVersion="ServerAgent-2.2.1"
jmeterDwnUrl="http://archive.apache.org/dist/jmeter/binaries/"
pluginsDwnUrl="http://jmeter-plugins.org/files/"
jmeterLogLevel=${jmeterLogLevel-WARN}

if  [ -d ./${JMETER_VERSION} ] && [[ -n $(ls ./${JMETER_VERSION}/) ]] ; then # don't try to upload any files if none present
    echo "JMETER is already present"
else
    echo "${JMETER_VERSION} folder doesn't exist or it is empty"
    echo "Downloading ${JMETER_VERSION}"
    wget ${jmeterDwnUrl}${JMETER_VERSION}.zip -O ${JMETER_VERSION}.zip \
        && {
            echo "${JMETER_VERSION} successfully downloaded"
            unzip -q ${JMETER_VERSION}.zip \
                && {
                    chmod +x ${JMETER_VERSION}/bin/jmeter.sh
                    chmod +x ${JMETER_VERSION}/bin/jmeter
                    # change JMeter's log_level
                    sed -i.bck 's/.*log_level.jmeter=.*/log_level.jmeter='${jmeterLogLevel}'/' ${JMETER_VERSION}/bin/jmeter.properties \
                        && {
                            echo "JMeter's log_level was set to: ${jmeterLogLevel}"
                        } || {
                            echo "[ERROR] Couldn't change the JMeter's log_level!!!"
                        }
                    rm ${JMETER_VERSION}.zip
                } || {
                    echo "Couln't unpack ${JMETER_VERSION}.zip!!! Script exit now!"
                    rm ${JMETER_VERSION}.zip
                    exit 1
                }
 
            echo "Downloading ${pluginsVersion}, ${pluginsExtrasVersion} and ${serverAgentVersion}...."
            wget --progress=bar -O JMeterPlugins.zip ${pluginsDwnUrl}${pluginsVersion}.zip \
                && {
                    echo "${pluginsVersion} successfully downloaded"
                    unzip -q -j -o JMeterPlugins.zip -d ${JMETER_VERSION}/lib/ext
                    rm JMeterPlugins.zip
                } || {
                    echo "There was a problem when downloading: ${pluginsVersion}"
                    rm JMeterPlugins.zip
                    exit 10
                }
            wget --progress=bar -O JMeterPlugins-extras.zip ${pluginsDwnUrl}/${pluginsExtrasVersion}.zip \
                && {
                    echo "${pluginsExtrasVersion} successfully downloaded"
                    unzip -q -j -o JMeterPlugins-extras.zip -d ${JMETER_VERSION}/lib/ext
                    rm JMeterPlugins-extras.zip
                } || {
                    echo "There was a problem when downloading: ${pluginsExtrasVersion}"
                    rm JMeterPlugins-extras.zip
                    exit 11
                }
            wget --progress=bar -O ServerAgent.zip ${pluginsDwnUrl}${serverAgentVersion}.zip \
                && {
                    echo "${serverAgentVersion} successfully downloaded"
                    unzip -q -o ServerAgent.zip -d ${JMETER_VERSION}/lib/ext # don't skip junk paths
                    rm ServerAgent.zip
                } || {
                    echo "There was a problem when downloading: ${serverAgentVersion}"
                    rm ServerAgent.zip
                    exit 12
                }
            echo "${pluginsVersion}, ${pluginsExtrasVersion} and ${serverAgentVersion} was downloaded and extracted successfully"
        } || {
        rm ${JMETER_VERSION}.zip
        echo "Failed to download ${JMETER_VERSION}.zip! Please check the log. Possibly download mirror site changed. Aborting the test...."
        exit 777
    }
fi;
