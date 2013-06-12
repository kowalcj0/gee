#!/bin/bash

# check for user secrets file
function getAWSSecrets() {

    # will check if file with user credentials is present
    secretsFile="${USER}_secrets.properties"
    if [ ! -e "${secretsFile}" ]; then
        echo "
        Couldn't find file: '${secretsFile}' with user's AWS secret credentials!

        To avoid typing passwords manually, please create a copy of 
        'secrets.properties' file and prepend your user name to its name. 
        e.g. if your user name is 'jk', then file should be named: jk_secrets.properties
        "
    else
        echo "${secretsFile} is present. Loading its content"
        . ${secretsFile} # execute to load user's secret credentials    
    fi

    # check wheter access keys are already set as system variable
    # if not the it' will ask you to them
    if [[ -z "$AWS_ACCESS_KEY" ]] && [[ -z "$AWS_SECRET_KEY"  ]] ; then 
        echo "System variables: AWS_ACCESS_KEY and AWS_SECRET_KEY are not set!"
        echo "Obtain them from: https://portal.aws.amazon.com/gp/aws/securityCredentials"
        echo "Please type the AWS Access Key ID, followed by [ENTER]:"
        read -s acKey 
        echo "Please type the AWS Secret Access Key ID, followed by [ENTER]:"
        read -s ssKey
        export AWS_ACCESS_KEY=${acKey}
        export AWS_SECRET_KEY=${ssKey}
    else
        echo "System variables AWS_ACCESS_KEY & AWS_SECRET_KEY are present"
    fi
}
