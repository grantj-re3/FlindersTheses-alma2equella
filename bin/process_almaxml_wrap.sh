#!/bin/sh
#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# Usage 1:  process_almaxml_wrap.sh
# Usage 2:  process_almaxml_wrap.sh --debug
#
# Usage 1:
# - Process theses which have been scanned into PDF format; filenames must
#   conform to a particular format; metadata must exist within the Exlibris
#   Alma integrated library management system.
# - Generate XML metadata (one per thesis)
# - Copy and rename scanned theses for EBI loading
# - Generate Equella Bulk Import (EBI) CSV metadata (one for all theses in
#   the batch)
# - Generate call-number CSV for library collection maintenance.
#
# Usage 2:
# - Process all XML bib records (which have been exported from Alma)
# - Generate most of the XML metadata (one per thesis)
#
##############################################################################
APP_DIR_TEMP=`dirname "$0"`		# Might be relative (eg "." or "..") or absolute
APP_DIR=`cd "$APP_DIR_TEMP" ; pwd`	# Absolute path of dir containing app
SH_CONFIG="$APP_DIR/common_config.sh"

$APP_DIR/mk_common_config_sh.rb > $SH_CONFIG	# Create shell environment vars (from ruby vars)
source $SH_CONFIG

# FIXME: Only use --backup=numbered option for development
MV_OPTS_EMBARGO="-vf --backup=numbered"

# To process only the third bib-file, set min to 3 & max to 3.
# To process all bib-files, set min to 1 & max to something like 99999.
MIN_BIBFILE_COUNT=$MIN_FILE_COUNT
MAX_BIBFILE_COUNT=$MAX_FILE_COUNT

##############################################################################
# Process all bibs (whether associated with scanned files or not)
process_all_bibs_debug() {
  rec_count=0
  for f in $IN_BIB_DIR/*.xml; do
    rec_count=`expr $rec_count + 1`
    [ $rec_count -gt $MAX_BIBFILE_COUNT ] && break
    [ $rec_count -lt $MIN_BIBFILE_COUNT ] && continue

    fbase=`basename $f`
    outfile="$OUT_DIR/$fbase"
    echo "[$rec_count] Writing to file '$outfile'"
    xsltproc $FLATTEN_XSLT $f | $FIXMARC_EXE $fbase > "$outfile"
    # Post-process with xmllint --format for XML syntax check
  done
}

##############################################################################
# Merge attachment filenames into XML metadata
merge_attachment_metadata() {
  rec_count=0
  while read mms_id; do
    [ "$mms_id" = "" ] && continue
    rec_count=`expr $rec_count + 1`

    f="$OUT_DIR/${mms_id}_v1.xml"	# BEWARE: These files are deleted below
    outfile=`echo "$f" |sed 's/_v1.xml$/_v2.xml/'`
    echo "[$rec_count] Writing to the file '$outfile'"

    fbase=`basename $f`
    # Post-process with xmllint --format for XML syntax check
    cmd="cat $f | $ADD_EXTRAS2XML_EXE $fbase > $outfile"
    eval $cmd
    res=$?
    if [ $res != 0 ]; then
      echo "Exit code $res. Error running command: '$cmd'" >&2
      exit 1
    fi
    rm -f $f				# BEWARE: Delete source file
  done < $FNAME_ALL_LIST
}

##############################################################################
# Separate embargoed theses from non-embargoed ones
move_embargo_files() {
  num_embargoed_records=`wc -w < "$FNAME_EMBARGOED_LIST"`
  if [ $num_embargoed_records -gt 0 ]; then
    echo "Using embargo directory for $num_embargoed_records MMS IDs: $EMBARGO_OUT_DIR"
    [ ! -d "$EMBARGO_OUT_DIR" ] && mkdir -p "$EMBARGO_OUT_DIR"

    rec_count=0
    while read mms_id; do
      rec_count=`expr $rec_count + 1`
      echo "[$rec_count] Moving embargoed files (MMS ID $mms_id)"
      cmd="mv $MV_OPTS_EMBARGO \"$OUT_DIR/${mms_id}\"* \"$EMBARGO_OUT_DIR\""
      eval $cmd
    done < $FNAME_EMBARGOED_LIST
  fi
}

##############################################################################
convert_xml_to_ebi() {
  # FIXME: Add sanity checking to function arguments?
  fname_mmsids="$1"	# Filename containing list of MMS IDs
  dir_xml_csv="$2"	# Dir containing XML bib files. Will also contain resulting EBI CSV file.
  is_embargoed_s="$3"	# "true" or "false"
  appr_emb_label="$4"	# "approved" or "embargoed" (for is_embargoed_s of "false" & "true" respectively)
  batch_timestamp="$5"

  out_csv_path="$dir_xml_csv/$OUT_CSV_BASE"
  callnum_csv_path="$dir_xml_csv/$CALLNUM_CSV_BASE"
  num_records=`wc -w < "$fname_mmsids"`
  echo
  echo "Converting $num_records $appr_emb_label XML files into a single EBI CSV file ${out_csv_path}"

  if [ $num_records -gt 0 ]; then
    xsltproc_clopts_first="--stringparam embargoed_str $is_embargoed_s --param add_csv_header \"true()\"  --stringparam batch_timestamp \"$batch_timestamp\""
    xsltproc_clopts_other="--stringparam embargoed_str $is_embargoed_s --param add_csv_header \"false()\" --stringparam batch_timestamp \"$batch_timestamp\""

    rec_count=0
    while read mms_id; do
      rec_count=`expr $rec_count + 1`
      echo "[$rec_count] Converting to EBI (IsEmbargoed=$is_embargoed_s). MMS ID $mms_id"
      f="$dir_xml_csv/${mms_id}_v2.xml"

      # Generate the EBI CSV file
      cmd="xsltproc $xsltproc_clopts_other $XML2EBI_CSV_XSLT $f >> $out_csv_path"
      [ $rec_count = 1 ] && cmd="xsltproc $xsltproc_clopts_first $XML2EBI_CSV_XSLT $f > $out_csv_path"
      echo "CMD: $cmd"
      eval $cmd

      # Generate the resource-management CSV file
      cmd="xsltproc $xsltproc_clopts_other $XML2CALLNUM_CSV_XSLT $f >> $callnum_csv_path"
      [ $rec_count = 1 ] && cmd="xsltproc $xsltproc_clopts_first $XML2CALLNUM_CSV_XSLT $f > $callnum_csv_path"
      echo "CMD: $cmd"
      eval $cmd
    done < $fname_mmsids
  fi
}

##############################################################################
# Only process scanned files and their associated bibs
# (Includes FLATTEN_XSLT & FIXMARC_EXE bib processing)
process_all_scanned_files() {
  $PROC_SCANNED_FILES_EXE
  res=$?
  if [ $res != 0 ]; then
    echo "Exit code $res. Error running command: '$PROC_SCANNED_FILES_EXE'" >&2
    exit 1
  fi

  merge_attachment_metadata	# Merge attachment filenames into XML metadata

  # Move embargo files into their own dir (as they will require a separate EBI CSV file)
  move_embargo_files

  # Create EBI CSV files for both approved & embargoed records
  batch_timestamp=`date "+%F %T"`
  convert_xml_to_ebi  "$FNAME_APPROVED_LIST"  "$OUT_DIR"         false approved  "$batch_timestamp"
  convert_xml_to_ebi  "$FNAME_EMBARGOED_LIST" "$EMBARGO_OUT_DIR" true  embargoed "$batch_timestamp"
}

##############################################################################
setup() {
  echo "Using directory for non-embargoed records: $OUT_DIR"
  [ ! -d "$OUT_DIR" ] && mkdir -p "$OUT_DIR"
}

##############################################################################
# main()
##############################################################################
setup
if [ "$1" = --debug ]; then
  process_all_bibs_debug
else
  process_all_scanned_files
fi

