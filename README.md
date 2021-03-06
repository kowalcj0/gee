# Gee / JMeter EC2 script
-----------------------------

Gee is a project based on the Oliver Lloyd's [jmeter-ec2](https://github.com/oliverlloyd/jmeter-ec2) script.
I've added few extensions and modifitcations, like:
* generate reports automatically using [JMeterPluginsCMD](http://jmeter-plugins.org/wiki/JMeterPluginsCMD/)
* generate reports manually from zipped result files using JMeterPluginsCMD
* starting PerfMon server agent on load generatign nodes
* simple integration with [Jenkins CI](http://jenkins-ci.org/)
* threshold check script that can verify test run results and mark Jenkins build as failed or unstable
* exctracting faulty URLs from JMeter CSV result files
* custom config files that are not commited to the repo

If all pre-requisits are met, script will automatically download all required
tools and plugins.


## Prerequisites
1. java 6+ with `JAVA\_HOME` sys variable set required to locally generate graphs
2. CLI tools: scp, wget, zip/bzip2, unzip, grep, awk 
3. an EC2 account, a key pair pem file and AWS Access Key ID & Secret Access Key
4. Python 2.6+ to run two scripts: genAggregateRepsTimesPercentilesReports.py & extractFaultyUrls.py


## Obtaining AWS Access Key ID & Secret Access Key
To get your :
* Key Pair pem file (it's a private key) go [here](https://console.aws.amazon.com/ec2/home?region=us-east-1#s=KeyPairs)
* Access Key ID & Secret Access Key go to the [Security Credentials](https://portal.aws.amazon.com/gp/aws/securityCredentials) page

Then:
* Save the pem file in the ./ec2 folder
* Change the pem file properties to 400. (`chmod 400 ./ec2/thisipemfile.pem`)
* Create a copy of the 'secrets.properties' file and prepend your user name to its name. (\*)
* Add your Access Key ID and Access Secret Key to that file

(\*) i.e.: if your user name is 'jk', then file should be named: jk\_secrets.properties
ps. By default all the \*\_secrets.properties files are ignored by git. 
To change this behaviour please edit .gitignore file.


## Video tutorials
I prepared a bunch og video tutorial showing how to configure and use Gee.
Here's a list of all the videos:
* [01 - cloning the project](http://www.youtube.com/watch?v=RWkJl4OXTJI&hd=1)
* [02 - initialize vagrant box](http://www.youtube.com/watch?v=cUcGvLy_Lf8&hd=1)
* [03 - running an example test on a vagrant box](http://www.youtube.com/watch?v=WrEqdKgz26Y&hd=1)
* [04 - create a first test plan, run it using Gee and a vagrant box](http://www.youtube.com/watch?v=b4aSFCRY_hs&hd=1)
* [05 - configure passwordless ssh access to a linux box](http://www.youtube.com/watch?v=fXhVTF7JJ_8&hd=1)
* [06 - automatically install JMeter with plugins on a remote machine](http://www.youtube.com/watch?v=MUJ1_PFclds&hd=1)
* [07 - run your JMeter test on remote linux hosts](http://www.youtube.com/watch?v=1rg13V6MjUI&hd=1)
* [08 - run your JMeter test on Amazon EC2](http://www.youtube.com/watch?v=y_U4BrCydF0&hd=1)

Altenatively you can watch them all here: [yt playlist](https://www.youtube.com/playlist?list=PLAUamg5VPF5HAxDQlDVItNLfTBNzhpnW4)


## How to configure it
Edit the file jmeter-ec2.properties and follow instruction inside that file.

You can also create also a custom cfg file i.e. per specific environment and use
it by passing "cfg" parameter to the jmeter-ec2.sh. This can be handy when running
tests on local machines and non on EC2

```bash
    project="drKingShultz" cfg="your_custom_cfg_file.properties" ./jmeter-ec2.sh
```

## How to set up your jmeter (jmx) project
Before you start adding your own projects, please refer to an example ones 
already present in the projects folder.

Now, in next few steps I'll try to explain how I configure my projects.

__Step 1:__
First of all I highly recommend using `Utlimate Thread Group` plugin as the thread manager.
This plugin gives you precise control over the generated traffic.


__Step 2:__
Once you've added such a thread to your project, then to produce all the nice graphs,
add four listeners to your project:
* two to the thread group
    * jp@gc LatenciesOverTime
    * Generate Summary Results
* and two outside of the thread group
    * 2 PerfMon Collector listeners (local & remote)

__Step 3:__
Having all listeners in place, the next step is to configure them.
* Generate Summary Results 
    * fortunately it doesn't require any configuration, but please leave its name unchanged :)
* jp@gc LatenciesOverTime
    * should write it's results down to a "~/result.jtl" file.
* 2 PerfMon Collector listeners (local & remote)
    * Remote one should write results in: ~/PerfMon-remote.jtl
    * and Local one should write down to: ~/PerfMon-local.jtl
* jp@gc LatenciesOverTime and PerfMon Collectors 
    * should be configured just like this:
    * ![alt text](./resources/SampleResultSaveConfiguration.png "Sample Result Save Configuration")

btw. Listener's "Configure" button is here :
![alt text](./resources/Listener-configuration.png "Listener Configure button")

__Step 4:__
In `projects` directory create a folder with the same name as the project file.
Then put your jmx in there.
Here's an example project folder structure:

    ./jmeter-ec2
        |
        \projects
            |
            \drKingShultz
                |
                \drKingShultz.jmx


### Why do we need those listeners:
__Generate Summary Results__ is used to show status updates while running your tests.  
__jp@gc Latencies Over Time__ result file is used to generate most of the graphs.  
__PerfMon Collector listeners__, will collect stat data from the:
* machines you're running your test against  
* and from the EC2 machines running your jmeter tests

To collect data from both sources we're using [server-agent](http://code.google.com/p/jmeter-plugins/wiki/PerfMonAgent).
Read the short manual how to run the server agent on the remote machines.


# How to run your project
Gee/JMeter-ec2 can be executed locally on you computer or using a CI system like Jenkins.
At the moment this script works well on tested on Linux Mint 13,14,15, Ubuntu 12.04, RedHat 5. 

## How to run it locally
Once you have everything in place, simply run:

```bash
    project="drKingShultz" count="2" ./jmeter-ec2.sh
```

"count" stands for the number of EC2 instances to be launched

To get a bit more verbose output, enable DEBUG mode :
```bash
    DEBUG=true project="drKingShultz" count="2" ./jmeter-ec2.sh
```

## How to run it locally using a comma-delimeted list of hosts
All the hosts used as load generators need to have a passwordless SSH access configured.
[Here's](http://www.debian-administration.org/articles/152) a nice article how this can be done on Debian based OSes.

Once SSH access is configured, then create a copy of an `example-local-config.properties` file and adjust it to your needs.
The most important thing is to provide the list of the IPs/Hostnames you're going to use as generators and a pem key filename.
This pem file is your private key, generated when configuring passwordless SSH access.

Then run the project providing the "cfg" parameter.

```bash
   project="drKingShultz" cfg="path/to/your/custom/local-config-file.properties" ./jmeter-ec2.sh 
```

ps. You don't have to provide the "count" parameter, as it will be automatically set to the number of hosts provided in the config file.


## Running locally with Vagrant
[Vagrant](http://vagrantup.com) allows you to test your jmeter-ec2 scripts locally before pushing them to ec2.

### Pre-requisits
* [Vagrant](http://vagrantup.com)
* [VirtualBox](https://www.virtualbox.org/)

### Usage:
Use `jmeter-ec2.properties.vagrant` as a template for local provisioning. This file is setup to use Vagrants ssh key, ports, etc.
```bash
# start vm and provision defaultjre
vagrant up
# run your project
project="drKingShultz" cfg=jmeter-ec2.properties.vagrant ./jmeter-ec2.sh
# or for a more verbose output run it with DEBUG=true
DEBUG=true project="drKingShultz" cfg=jmeter-ec2.properties.vagrant ./jmeter-ec2.sh
```

### Note
* You may need to edit the `Vagrantfile` to meet any specific networking needs. See Vagrant's [networking documentation](http://docs.vagrantup.com/v2/getting-started/networking.html) for details



## How to run it on Jenkins
Create a new job:

Mark 'This build is parameterized' as enabled.
Then:
* add 'File parameter' and set 'File location' to 'test/jmeter-ec2/ec2/jmeter-ec2.pem'
* add 'Password Parameter' named 'AWS\_ACCESS\_KEY' with no default value
* add 'Password Parameter' named 'AWS\_SECRET\_KEY' with no default value
* add 'String parameter' name 'JAVA\_HOME' with default value poitning at the JAVA dir on the Jenkins

in the "Build" section add "Execute shell" and paste the code below:
```bash
    # change permission for keys
    if [ -e ec2/jmeter-ec2.pem ]; then
        chmod 400 ec2/jmeter-ec2.pem
    fi;

    # run the tests
    project="drKingShultz" count="2" ./jmeter-ec2.sh

    # remove the unnecessary pem file
    # will prevent errors when trying to overide pem file on a new build 
    if [ -e ec2/jmeter-ec2.pem ]; then
        rm ec2/jmeter-ec2.pem
    fi;
```

To analyze result files and create a simple performance report:
Add a "Publish performance test result report" post-build action.
Then point at the $WORKSPACE/projects/drKingShultz/results/jenkins.jtl file
Add desired performance thresholds to decide when tests should pass or fail.


## Reports
Once test is finished, you can find a simple HTML report in the:

    jmeter-ec2
        |
        \drKingShultz
            |
            \results

Report file name is configurable. By default script will use:
`${DATETIME}-report.html` where ${DATETIME} is the current datetime taken on script start.
Datetime pattern is `%Y-%m-%d_-_%H-%M` so an example report filename will be:
* ie: 2013-06-13_-_09-56-report.html 


btw. If you plan to run this script on Jenkins, then it's worth setting the 
report name (cfg variable name is: cfgHtmlReportFilename) to something like index.html
Then it's easy to point at a fixed filename when using plugins like [HTML Publisher plugin](https://wiki.jenkins-ci.org/display/JENKINS/HTML+Publisher+Plugin)


## Handy Jenkins Plugins
A list of Jenkins plugins I found quite handy when working with it.
* [ANSIColor](https://wiki.jenkins-ci.org/display/JENKINS/AnsiColor+Plugin) for coloring console log :)
* [Plot Plugin](https://wiki.jenkins-ci.org/display/JENKINS/Plot+Plugin) can be used to plot performance trends from a CSV,XML,Properties files. I only use it with the aggregate CSV result files that are generated by the Gee/JMeter-EC2 script.
* [HTML Publisher Plugin](https://wiki.jenkins-ci.org/display/JENKINS/HTML+Publisher+Plugin) will publish HTML reports generated by Gee/JMeter-EC2 script
* [Locks and Latches plugin](https://wiki.jenkins-ci.org/display/JENKINS/Locks+and+Latches+plugin) prevents builds from running simultanously on the same load generators
* [Performance Plugin](https://wiki.jenkins-ci.org/display/JENKINS/Performance+Plugin) will generate a performance trend from a JMeter XML result files. Can be a real overkill to your Jenkins instance when these XML files are big!!!!
* [Site Monitor](https://wiki.jenkins-ci.org/display/JENKINS/SiteMonitor+Plugin) I'm using it to check it tested environment is up and running.


## Test run outputs
Everytime you run your tests, Gee produces few files that can:
* help you analyze the test run results 
* be used to visualize the performance trend of your application

What can be generated:
* a HTML report with multiple PNG graphs. Here's an [example HTML report](http://htmlpreview.github.io/?https://github.com/kowalcj0/gee/blob/master/docs/examples/results/index.html) [flag name: cfgCreateHTMLReport]
* an Aggregate CSV Report file [example file](./docs/examples/results/aggregate.csv) [flag name: cfgCreateAggregateCSVReport]
* an Aggregate Response Time Percentiles CSV file (for all the samplers) [example file](./docs/examples/results/aggregatedResponseTimesPercentiles.csv) [flag name: cfgCreateAggregateCSVReport]
* an Aggregate Response Time Percentiles CSV file (for each sampler)  [example file no. 1](./docs/examples/results/GetRespTimesPercentiles.csv) & [example file no. 2](./docs/examples/results/GetwithrandomfailureRespTimesPercentiles.csv) [flag name: cfgCreateAggregateCSVReport]
* a CSV with few simple stats like: min, max, mean, median, stdev calculated for: Latency, Response time, Response Size [example file](./docs/examples/results/statistics.csv) [flag name: cfgCalculateSimpleStatsFromAResultFile]
* a text file with a list of all URLs that: returned with an unexpected response code, didn't pass the assertion step etc. Check out all the *.errors files in an [example results archive](./docs/examples/results/results.tar.bz2) [flag name: cfgExctractFaultyURLs]
* a XML file composed from all jenkins.xml files downloaded from all the nodes. It can be used by ie.: [Jenkins Performance Plugin](https://wiki.jenkins-ci.org/display/JENKINS/Performance+Plugin) [flag name: cfgCreateMergedFileForJenkinsPerfPlugin]
* a CSV file composed from all result.xml files downloaded from all the nodes. It can be used by ie.: [Jenkins Plot Plugin](https://wiki.jenkins-ci.org/display/JENKINS/Plot+Plugin) [flag name: cfgCreateMergedResultFile]
* a compressed archive (zip or bzip2) containing all the test run logs, error files, result files etc. [Example results archive](./docs/examples/results/results.tar.bz2) [flag name: cfgSaveCompressedResults]

All these files can generated once enabled in your configuration file.
Btw. by default most of them are already enabled :)
Here's a list of all configuration flags, that control what is produced 
during a test run:
* cfgCreateHTMLReport
* cfgCreateAggregateCSVReport
* cfgGenerateAggregatedResponseTimePercentilesReports
* cfgCalculateSimpleStatsFromAResultFile
* cfgExctractFaultyURLs
* cfgSaveCompressedResults
* cfgCreateMergedFileForJenkinsPerfPlugin
* cfgCreateMergedResultFile

## How to generate graphs from long test runs

By default jmeter-ec2 script will generate graphs using 1920x1200px resolution.
In case you need to create a report from a very long test, and you want to change the default graph resolution, 
then you can use `analyzeZippedResults.sh` script for this purpose.

Here's an example usage:
```bash
    FILES="path/to/a/folder/with/result/files/file_name_pattern_with_an_asterisk-*.zip" WIDTH=20000 HEIGHT=1080 ./analyzeZippedResults.sh
```

Where:
* FILES -  [MANDATORY] A path to zipped result files. User can use an asterisk to process multiple files (i.e.: from multiple nodes). Just like you'd use 'ls' command to list all the files you want to process.
* WIDTH -  [OPTIONAL] sets the width of the generated graphs, default is 1920
* HEIGHT - [OPTIONAL] sets the height of the generated graphs, defaul is 1200
* JMETER - [OPTIONAL] is the path to jmeter folder with JMeterPlugins installed
* TARGET - [OPTIONAL] parameter that defines where output report with graphs will be stored. If not provided then "./target" will be used
* DEBUG -  [OPTIONAL] parameter that enables more verbose output, use DEBUG=true



## License:
Gee / JMeter-ec2 is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

Gee / JMeter-ec2 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with Gee / JMeter-ec2. If not, see http://www.gnu.org/licenses/.


## handy bash commands

find which custom workspace is used by selected Jenkins jobs
```bash
    cd /dir/with/jenkins/jobs
    find QAA* -iname config.xml -print0 | xargs -0 grep customWorkspace
```

## Original Jenkins-ec2 description:
----------------------------

Is available @ [jmeter-ec2](https://github.com/oliverlloyd/jmeter-ec2) page.

