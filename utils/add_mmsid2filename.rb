#!/usr/bin/ruby
#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# Typical usage:
# $ ./add_mmsid2filename.rb
#
# Algorithm:
# - For each MARC XML file in IN_BIB_DIR
#   * Search the XML bib record file for MMS ID
#   * Rename the file from ORIG_FNAME.xml to ORIG_FNAME.mmsidNNNNNNNNNN.xml
#     where NNNNNNNNNN is the numeric MMS ID.
##############################################################################
# Add dirs to the library path
$: << File.expand_path("../etc", File.dirname(__FILE__))
require "common_config"

class AddMmsid2FilenamesFactory
  include CommonConfig

  NUM_FILES_MAX = 99999		# Max number of files to process. Use small value for debugging

  RE_FNAME_EXT = /#{Regexp.quote(BIB_FNAME_EXT)}$/	# Include dot. Eg. /\.xml$/
  RE_XML_CONTENT_MMS_ID = /<controlfield tag="001">(99\d{8,17})</	# Match MMS ID in MARC XML
  RE_FNAME_WITH_ANY_MMS_ID = /\.mmsid\d+\./

  ############################################################################
  def initialize
    @mms_ids = []		# MMS ID list - renamed by this run of this script
    @mms_ids_prev = []		# MMS ID list - previously renamed
    @num_glob_files = 0		# Number of files matching the file-glob BIB_FNAME_GLOB
    @num_warnings = 0
  end

  ############################################################################
  def final_summary_report
    num_mms_ids_uniq = (@mms_ids + @mms_ids_prev).uniq.length
    mms_ids_ok_msg = num_mms_ids_uniq == @num_glob_files ?
      "OK (because #{num_mms_ids_uniq} == #{@num_glob_files})" :
      "WARNING! No (because #{num_mms_ids_uniq} != #{@num_glob_files})"

    puts <<-EO_MSG.gsub(/^\t*/, "")

	Final summary report
	--------------------
	Number of files which match file-glob (total files):  #{sprintf "%5d", @num_glob_files}
	Number of files renamed (to include MMS ID):          #{sprintf "%5d", @mms_ids.length}
	Number of warnings:                                   #{sprintf "%5d", @num_warnings}
	Number of files previously renamed:                   #{sprintf "%5d", @mms_ids_prev.length}

	Final number of unique MMS-ID-filenames in file-glob: #{sprintf "%5d", num_mms_ids_uniq}
	Are unique MMS-ID-filenames vs total files ok?   #{mms_ids_ok_msg}
	EO_MSG
  end

  ############################################################################
  def rename_marcxml_files
    @mms_ids = []
    @mms_ids_prev = []
    @num_glob_files = 0
    @num_warnings = 0

    Dir.glob(BIB_FNAME_GLOB).sort.each{|f|
      break if @num_glob_files >= NUM_FILES_MAX

      @num_glob_files += 1
      fbase = File.basename(f)
      File.read(f).match(RE_XML_CONTENT_MMS_ID)
      mms_id = $1

      unless mms_id
        STDERR.puts "WARNING: File contains no MMS ID. Cannot rename. #{fbase.inspect}"
        @num_warnings += 1
        next
      end

      if f.match(RE_FNAME_WITH_ANY_MMS_ID)
        re_fname_with_this_mms_id = /\.mmsid#{mms_id}#{Regexp.quote(BIB_FNAME_EXT)}$/
        if f.match(re_fname_with_this_mms_id)
          STDERR.puts "INFO: Filename already contains the expected MMS ID. Will not rename. #{fbase.inspect}"
          @mms_ids_prev << mms_id
        else
          STDERR.puts "WARNING: Filename contains the *wrong* MMS ID. Will not rename. #{fbase.inspect}"
          @num_warnings += 1
        end
        next
      end

      fdest = f.sub(RE_FNAME_EXT, ".mmsid#{mms_id}#{BIB_FNAME_EXT}")
      STDERR.puts "INFO: Renaming #{fbase.inspect} to #{File.basename(fdest).inspect}"
      File.rename(f, fdest)
      @mms_ids << mms_id
    }
  end

  ############################################################################
  def self.main
    puts <<-EO_MSG.gsub(/^\t*/, "")

	Add MMS ID to each MARC XML filename
	====================================
	Target file-glob: #{BIB_FNAME_GLOB.inspect}

	EO_MSG

    factory = AddMmsid2FilenamesFactory.new
    factory.rename_marcxml_files
    factory.final_summary_report
  end
end

##############################################################################
# Main()
##############################################################################
AddMmsid2FilenamesFactory.main

