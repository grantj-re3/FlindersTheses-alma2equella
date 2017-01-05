#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# Common config vars for ruby (and sh/bash)

module CommonConfig
  # Process files from MIN_FILE_COUNT  to MAX_FILE_COUNT inclusive
  MIN_FILE_COUNT = 1
  MAX_FILE_COUNT = 99999
  NEWLINE = "\n"

  TOP_DIR = File.expand_path("..", File.dirname(__FILE__))	# Top level dir
  BIN_DIR = "#{TOP_DIR}/bin"

  # Programs and scripts
  FLATTEN_XSLT           = "#{BIN_DIR}/flatten.xsl"
  FIXMARC_EXE            = "#{BIN_DIR}/fix_marc.rb"
  PROC_SCANNED_FILES_EXE = "#{BIN_DIR}/process_scanned_files.rb"
  ADD_EXTRAS2XML_EXE     = "#{BIN_DIR}/add_extras2xml.rb"
  XML2EBI_CSV_XSLT       = "#{BIN_DIR}/xml2csv.xsl"
  XML2CALLNUM_CSV_XSLT   = "#{BIN_DIR}/xml2csv_callnum.xsl"

  # Directories, files, file extensions, file globs, etc
  IN_SCAN_DIR     = "#{TOP_DIR}/src/digitised"
  IN_BIB_DIR      = "#{TOP_DIR}/src/bibs_indiv"
  OUT_DIR         = "#{TOP_DIR}/results/bibs_proc"
  BIB_FIX_LOG     = "#{OUT_DIR}/bibs_fix.err"	# BEWARE: File will be deleted then re-written
  EMBARGO_OUT_DIR = "#{OUT_DIR}_emb"

  FNAME_ALL_LIST       = "#{OUT_DIR}/mmsids_all.txt"
  FNAME_APPROVED_LIST  = "#{OUT_DIR}/mmsids_approved.txt"
  FNAME_EMBARGOED_LIST = "#{OUT_DIR}/mmsids_embargoed.txt"

  BIB_FNAME_EXT = ".xml"			# Include dot. Eg. ".xml"
  BIB_FNAME_GLOB = "#{IN_BIB_DIR}/rec*#{BIB_FNAME_EXT}"
  BIB_OUT_FNAME_SUFFIX = "_v1#{BIB_FNAME_EXT}"
  EXTRA_BIB_INFO_FNAME_SUFFIX = "_extra.yaml"
  OUT_CSV_BASE = "theses_ebi.csv"
  CALLNUM_CSV_BASE = "theses_callnum.csv"
end

