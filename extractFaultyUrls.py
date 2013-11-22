#!/usr/bin/env python
import csv
import logging
import re
from sys import exit
import os
from sets import Set

__author__="janusz kowalczyk"

################################################################################
# This script will exctract all URLs from JMeter CSV log file
# group all the errors by type and save them in separate "*.errors" files
# 
# NOTE: Input log file has to contain 'responseCode' & 'URL' columns
#
#
# Usage:
#   ./faultyUrlExctractor.py -i errors_csv.jtl
#   Will use current directory as the output folder
#
#   ./faultyUrlExctractor.py -i errors_csv.jtl -o ../your/specific/dir
#   will use specified directory as the outpur folder
# 
# Example CSV log file containg only errors with multiline cells
#
# timeStamp,elapsed,label,responseCode,responseMessage,failureMessage,bytes,grpThreads,allThreads,URL,Latency,Hostname
# 1384443192680,103,Get,400,Bad Request,"Test failed: code expected to equal /
# 
# ****** received  : [[[4]]]00
# 
# ****** comparison: [[[2]]]00
# 
# /",583,2,2,http://www-a.yell.com/autocomplete/autocomplete.do,102,examine
# ...
#
#
# Logging handling based on these two tutorials:
# http://docs.python.org/2/howto/logging-cookbook.html
# http://www.kylev.com/2009/07/01/start-your-python-project-with-optparse-and-logging/
#
################################################################################

def extractFaultyURLs(input):
    with open(input, 'rb') as csvfile:
        # open the CSV file with the Excel dialect support to handle cells with
        # new line in them
        # http://stackoverflow.com/questions/11146564/handling-extra-newlines-carriage-returns-in-csv-files-parsed-with-python
        parsedCSV=(line for line in csv.reader(csvfile, dialect='excel'))

        # get the header, will be used for generating output filenames
        header = parsedCSV.next()
        logger.debug("CSV header: %s" % header)

        if "responseCode" in header:
            respCodeIdx = header.index("responseCode")
            logger.debug("Found responseCode in the header at index: %s " % respCodeIdx)
            if "URL" in header:
                urlIdx = header.index("URL")
                logger.debug("Found URL in the header at index: %s" % urlIdx)

                for row in parsedCSV:
                    # check if response code is a Number
                    # or it's a Non HTTP response code like: java.net.URISyntaxException
                    # if it is a string then just exctract the exception name
                    if not row[respCodeIdx][0].isdigit():
                        colonIdx=row[respCodeIdx].index(":")+2
                        code=row[respCodeIdx][colonIdx:]
                    else:
                        code=row[respCodeIdx]

                    # add an empty Set to the new key
                    # We're using Sets to automatically delete duplicates
                    if not code in errors:
                        errors[code] = Set([])

                    # add new faulty URL to a matching response code key
                    errors[code].add(row[urlIdx])
            else:
                logger.error("This CSV file doesn't contain required 'URL' column! Exiting")
                exit(2)
        else:
            logger.error("This CSV file doesn't contain required 'responseCode' column! Exiting")
            exit(1)


def printFaultyURLs(errors):
    #print errors
    for e in errors:
        logger.info("Found: %d entries of: %s" % (len(errors[e]), e))
        for u in errors[e]:
            logger.debug("%s" % (u))


def saveToFiles(errors, output, prefix):
    for e in errors.keys():
        # remove all non aplhanumeric characters from the output filename
        outputFile=re.sub("[^a-zA-Z0-9]", "", e)
        filename=("%s%s%s%s.errors" % (output, os.sep, prefix, outputFile))
        logger.info("Saving all '%s' URLs in: %s" % (e, filename))
        # save all faulty URLs grouped by the error type in separate files
        with open(filename, 'w') as f:
            f.write('\n'.join(errors[e]))


if '__main__' == __name__:
    # Late import, in case this project becomes a library, never to be run as main again.
    import optparse

    # Populate our options, -h/--help is already there for you.
    optp = optparse.OptionParser()
    optp.add_option('-v', '--verbose', dest='verbose', action='count',
                    help="Increase verbosity (specify multiple times for more)")
    optp.add_option('-i', '--input-file', dest='input', 
                    help="Input JMeter CSV log file to read data from")
    optp.add_option('-o', '--output-directory', dest='output', 
                    help="Output directory to store faulty URLs")
    optp.add_option('-p', '--file-prefix', dest='prefix', 
                    help="Output file prefix. ie.: -p 'hostA-' will save all 400s in a file named hostA-400.errors")
    # Parse the arguments (defaults to parsing sys.argv).
    opts, args = optp.parse_args()

    # Here would be a good place to check what came in on the command line and
    # call optp.error("Useful message") to exit if all it not well.


    # create logger with '__name__'
    logger = logging.getLogger(__name__)
    logger.setLevel(logging.INFO)
    # create console handler with a higher log level
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)
    # create formatter and add it to the handlers
    formatter=logging.Formatter('[%(asctime)s] [%(levelname)s]: %(message)s', "%a %Y-%m-%d %H:%M:%S %z")
    ch.setFormatter(formatter)
    logger.addHandler(ch)


    log_level = logging.INFO # default
    if opts.verbose >= 1:
        log_level = logging.DEBUG

    if not opts.input:
        logger.error("No input file specified!")
        exit(1)
    else:
        if os.path.exists(opts.input):
            input=opts.input
        else:
            logger.error("Input file '%s' doesn't exist!" %  opts.input)
            exit(66)

    if not opts.output:
        logger.warning("Output directory wasn't specified! "
                    "Using current directory: '%s' as the output!" 
                    % os.path.join(os.sep, os.getcwd()))
        output=os.path.join(os.sep, os.getcwd())
    else:
        if os.path.exists(opts.output):
            output=opts.output
        else:
            logger.error("Output directory doesn't exist!")
            exit(77)

    if not opts.prefix:
        prefix=""
    else:
        prefix=opts.prefix

    # initialize an empty list for storing all errors
    errors={}

    extractFaultyURLs(input)
    printFaultyURLs(errors)
    saveToFiles(errors, output, prefix)

