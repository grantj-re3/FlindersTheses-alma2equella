#!/bin/sh
#
# Copyright (c) 2021, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# Usage:  mk_newfilenames.sh
#
# Purpose:
# To create a CSV-formatted list of (thesis) filenames based on:
# - Alma MMS ID
# - Alma metadata corresponding to the MMS ID
#
# Assumptions:
# - You have:
#   * exported MARC-XML bib records from your (thesis) Alma set
#   * converted them to individual files; one per bib record; each file
#     starting with element <record> and ending with element </record>
#   * renamed to include MMS ID in the filename (using add_mmsid2filename.rb)
#   * stored those files in folder src/bibs_indiv
# - There is only one filename (volume) per MMS ID (i.e. per Alma bib record)
#
# Algorithm:
# - Process all MARC-XML bib records (which have been exported from Alma)
# - For each MARC-XML bib record:
#   * Use a local (in-memory) copy of the XML document
#   * Extract metadata of interest into a "flat" section of the XML document
#   * Fix/clean metadata of interest within the XML document
#   * Convert XML to CSV. The important columns are MMS ID and new filename
# - Output all CSV records to STDOUT
#
##############################################################################
APP_DIR_TEMP=`dirname "$0"`		# Might be relative (eg "." or "..") or absolute
APP_DIR=`cd "$APP_DIR_TEMP" ; pwd`	# Absolute path of dir containing app
ETC_DIR=`cd "$APP_DIR/../etc" ; pwd`	# Absolute path of etc dir
LIB_DIR=`cd "$APP_DIR/../lib" ; pwd`	# Absolute path of lib dir
SH_CONFIG="$ETC_DIR/common_config.sh"

$LIB_DIR/mk_common_config_sh.rb > $SH_CONFIG	# Create shell environment vars (from ruby vars)
source $SH_CONFIG

##############################################################################
cmd_flatten="xsltproc '$FLATTEN_XSLT'"
cmd_2fname="xsltproc --param add_csv_header"

s_add_csv_header="true()"

ls -1 $BIB_FNAME_GLOB |
  while read fpath; do
    fname=`basename "$fpath"`
    #echo "### $fname -- $s_add_csv_header -- $fpath" >&2

    cmd="$cmd_flatten '$fpath' |$FIXMARC_EXE '$fname' |$cmd_2fname '$s_add_csv_header' '$XML2SCANFILENAME_CSV_XSL' -"
    echo "CMD: $cmd" >&2
    eval $cmd
    s_add_csv_header="false()"
  done

