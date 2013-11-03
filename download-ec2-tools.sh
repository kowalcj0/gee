#!/bin/bash
#
# Runs this script to install ec2 tools locally on your computer or
# when running on Jenkins
#

if  [[ -d ec2/bin ]] && [[ -n $(ls ec2/bin/) ]] && [[ -d ec2/lib ]] && [[ -n $(ls ec2/lib/) ]] ; then # don't try to upload any files if none present
    echo "EC2 tools are already present"
else
    echo "ec2/bin and/or ec2/lib folders doesn't exist or they are empty"
    echo "Installing EC2 tools"
    cd ec2 \
        && {
            wget http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip -O ./ec2-api-tools.zip \
                && {
                    echo "ec2-api-tools.zip downloaded successfully"
                    unzip -q -o ./ec2-api-tools.zip
                    rm ./ec2-api-tools.zip
                    mv ec2-api-tools-*/bin .
                    mv ec2-api-tools-*/lib .
                    rm -fr ec2-api-tools-*/
                    cd ..
                } || {
                    rm ./ec2-api-tools.zip
                    cd ..
                    echo "Failed to download http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip. Please check the log";
                    exit 777
                }
        } || {
            echo "There's no ec2 folder. Please check project folder structure! Aborting the test!!!";
            exit 888
        }
    fi;
