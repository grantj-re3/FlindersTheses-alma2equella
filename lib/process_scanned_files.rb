#!/usr/bin/ruby
#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# Usage:  process_scanned_files.rb
#
# Algorithm:
# - For each file in IN_SCAN_DIR
#   * Process corresponding XML bib record; write to OUT_DIR/MMS_ID.xml
#   * Copy scanned file to OUT_DIR/MMS_ID.d/meaningful_filename
##############################################################################
# Add dirs to the library path
$: << File.expand_path("../etc", File.dirname(__FILE__))
require "common_config"

require "fileutils"
require "yaml"

class ScannedFilesProcessor
  include CommonConfig

  # These parameters allow you to process a subset of theses (typically
  # for debugging purposes).
  #
  # To process only the third scan-file, set min to 3 & max to 3.
  # To process all scan-files, set min to 1 & max to something like 99999.
  #
  # Sometimes a single thesis is associated with more than one scan-file.
  # If you set min/max below to process only some of the scan-files
  # associated a particular thesis, then this program is likely to
  # generate errors.
  MIN_SCANFILE_COUNT = MIN_FILE_COUNT
  MAX_SCANFILE_COUNT = MAX_FILE_COUNT

  PERMITTED_FILE_EXTENSIONS = %w{pdf zip}
  PERMITTED_FILE_EXTENSIONS_REGEX = Regexp.new(
    "^(.*)\\.(#{PERMITTED_FILE_EXTENSIONS.join('|')})$",
    Regexp::IGNORECASE
  )

  FILENAME_SEP = "_"
  FILENAME_SEP_MIN = 3
  FILENAME_SEP_MAX = 4
  FILENAME_PARTS_RNG = (FILENAME_SEP_MIN+2)..(FILENAME_SEP_MAX+2)

  FILENAME_PARTS_REGEX = [
    /^[-' [:alpha:]]+$/,	# AUTHOR NAME
    /^[\.[:alpha:]]$/,		# AUTHOR INITIAL
    /^99\d{8,17}$/,		# MMS ID = numeric; starts with 99; len(min,max) = (?,19)
    /^\d{1,2}$/,		# SEQUENCE NUMBER
    /^[[:alpha:][:digit:]-]+$/,	# DESCRIPTION (only for non-pdf)
  ]

  SCAN_DATE_FORMAT = "%Y-%m-%d"

  RE_YEAR = /<meta tagcode="publication_date.fixed1">(\d{4})</
  RE_SURNAME = /<meta tagcode="surname.fixed1">(.+)</
  RE_GIVENNAMES = /<meta tagcode="given_names.fixed1">(.+)</
  RE_FILTER_AUTHORNAME = /[^a-z0-9]/i
  RE_IS_RESTRICTED = /<meta tagcode="(is_restricted.fixed1)"/
  MSG_BY_SYMBOL = {
    :FPARTS_WARN_no_thesis_volume_found		=> "Filename WARNING: No thesis volume found.",
    :FPARTS_WARN_1volume_not_seqnum0		=> "Filename WARNING: Single volume does NOT have SEQNUM 0",
    :FPARTS_WARN_multivolume_has_seqnum0	=> "Filename WARNING: Multi-volume DOES have SEQNUM 0",
  }

  CP_OPTS = {
    :preserve => true,
  }
  attr_reader :info_by_mms_id

  ############################################################################
  def initialize
    @target_fnames = []
    @bad_fnames = nil
    @info_by_mms_id = {}

    @bib_basenames = []
    @has_reg_at_exit_log = false

    @mms_ids_all = []
    @mms_ids_approved = []
    @mms_ids_embargoed = []
    @mms_ids_not_processed = []
  end

  ############################################################################
  def collect_target_filenames
    scanfile_count = 0
    @target_fnames = []
    Dir.entries(IN_SCAN_DIR).sort.each{|f|
      next if File.directory?("#{IN_SCAN_DIR}/#{f}")
      scanfile_count += 1

      next if scanfile_count < MIN_SCANFILE_COUNT
      break if scanfile_count > MAX_SCANFILE_COUNT
##puts "[#{scanfile_count}] f=#{f}"
      @target_fnames << f		# Process this scan-file
    }
  end

  ############################################################################
  def collect_target_fileparts
    f_invalid_exts = []; f_bad_num_sep = []; f_empty_part = []
    f_bad_name = []; f_bad_initial = []; f_bad_mms_id = []; f_bad_seq_num = []; f_bad_descr = []

    @target_fnames.each_with_index{|f,tf_index|

      if f.match(PERMITTED_FILE_EXTENSIONS_REGEX)
        basename, ext = $1, $2
        parts = basename.split(FILENAME_SEP) + [ ext ]
        has_descr = parts.length == FILENAME_PARTS_RNG.end

        if FILENAME_PARTS_RNG.include?(parts.length)
          if parts.include?("")
            f_empty_part << f
          else
            # Check each part (with regex): AUTHORNAME_AUTHORINITIAL_MMSID_SEQNUM_DESCRIPTION.EXT
            is_ok = true
            (f_bad_name    << f; is_ok = false) unless parts[0].match(FILENAME_PARTS_REGEX[0])
            (f_bad_initial << f; is_ok = false) unless parts[1].match(FILENAME_PARTS_REGEX[1])
            (f_bad_mms_id  << f; is_ok = false) unless parts[2].match(FILENAME_PARTS_REGEX[2])
            (f_bad_seq_num << f; is_ok = false) unless parts[3].match(FILENAME_PARTS_REGEX[3])
            (f_bad_descr   << f; is_ok = false) if parts[4] && !parts[4].match(FILENAME_PARTS_REGEX[4])

            if is_ok
              mms_id = parts[2]
              unless @info_by_mms_id.has_key?(mms_id)
                @info_by_mms_id[mms_id] = {}
                @info_by_mms_id[mms_id][:a_fname_parts] = []	# Array of filename-parts hashes
                @info_by_mms_id[mms_id][:sort_num] = tf_index	# Non-consecutive if multiple files per MMS ID
              end
              this_fname_parts_hash = {
                :whole		=> f,				# Whole basename (ie. filename)

                :name		=> parts[0],
                :initial	=> parts[1],
                :seq_num	=> parts[3],
                :descr		=> has_descr ? parts[4] : nil,
                :ext		=> parts.last
              }
              @info_by_mms_id[mms_id][:a_fname_parts] << this_fname_parts_hash
            end
          end
        else
          f_bad_num_sep << f
        end
      else
        f_invalid_exts << f
      end
    }
    @bad_fnames = [
      # [sort_num, key,		bad_file_list,	regex_index]
      [100, :invalid_exts,	f_invalid_exts,	nil],
      [200, :bad_num_sep,	f_bad_num_sep,	nil],
      [300, :empty_part,	f_empty_part,	nil],

      [400, :bad_name,		f_bad_name,	0],
      [410, :bad_initial,	f_bad_initial,	1],
      [420, :bad_mms_id,	f_bad_mms_id,	2],
      [430, :bad_seq_num,	f_bad_seq_num,	3],
      [440, :bad_descr,		f_bad_descr,	4],
    ]
    show_bad_target_filenames
  end

  ############################################################################
  def show_bad_target_filenames
    @bad_fnames.sort{|a,b| a[0] <=> b[0]}.each{|sort,key,a,idx|
      next if a.empty?

      debug1 = "[#{sort}, #{key}] "
      #debug1 = ""

      desc = case key
      when :invalid_exts
	<<-EO_MSG
		#{debug1}The following files have an invalid file extension.
		Valid file extensions are: #{PERMITTED_FILE_EXTENSIONS.join(', ')}
	EO_MSG

      when :bad_num_sep
		"#{debug1}The following files have the wrong number of separators '#{FILENAME_SEP}'."

      when :empty_part
	<<-EO_MSG
		#{debug1}Filenames are divided into parts by the separator '#{FILENAME_SEP}'.
		None of the parts (AUTHORNAME, AUTHORINITIAL, MMSID, SEQNUM, DESCRIPTION, EXT)
		are allowed to be empty.
	EO_MSG

      when :bad_name
		"#{debug1}AUTHORNAME is invalid! Must match: #{FILENAME_PARTS_REGEX[idx].inspect}"

      when :bad_initial
		"#{debug1}AUTHORINITIAL is invalid! Must match: #{FILENAME_PARTS_REGEX[idx].inspect}"

      when :bad_mms_id
		"#{debug1}MMSID is invalid! Must match: #{FILENAME_PARTS_REGEX[idx].inspect}"

      when :bad_seq_num
		"#{debug1}SEQNUM is invalid! Must match: #{FILENAME_PARTS_REGEX[idx].inspect}"

      when :bad_descr
		"#{debug1}DESCRIPTION is invalid! Must match: #{FILENAME_PARTS_REGEX[idx].inspect}"

      else
        "#{debug1}"
      end

      STDERR.puts "\n#{desc.gsub(/^\t*/, '')}"
      a.each{|f| STDERR.puts "- #{f}"}
    }

    unless @bad_fnames.all?{|(sort,key,a,idx)| a.empty?}
      STDERR.puts <<-EO_MSG.gsub(/^\t*/, '')

		Filename format must be one of the following:
		- AUTHORNAME_AUTHORINITIAL_MMSID_SEQNUM.EXT
		- AUTHORNAME_AUTHORINITIAL_MMSID_SEQNUM_DESCRIPTION.EXT

		Quitting: Some filenames are invalid!
	EO_MSG
      exit 1
    end
  end

  ############################################################################
  def collect_bib_basenames
    @bib_basenames = Dir.glob(BIB_FNAME_GLOB).sort.collect{|f| f=File.basename(f)}
  end

  ############################################################################
  # Bib filenames must have format "*.mmsidNNNNN.xml" where NNNNN = the MMS ID.
  # The bib files contain MARC XML for the given MMS ID.
  def collect_related_bib_files
    @info_by_mms_id.each_key{|mms_id|
      re_fname_with_this_mms_id = /\.mmsid#{mms_id}#{Regexp.quote(BIB_FNAME_EXT)}$/
      fname = @bib_basenames.find{|f| f.match(re_fname_with_this_mms_id)}
      if fname
        @info_by_mms_id[mms_id][:bib_basename] = fname
      else
        # Prevent further processing by removing this MMS ID from the list
        @info_by_mms_id.delete(mms_id)
        @mms_ids_not_processed << mms_id
        STDERR.puts "WARNING: No related bib file found for MMS ID '#{mms_id}'. Processing this record will halt."
      end
    }
  end

  ############################################################################
  def create_dest_bib_file(mms_id, info)
    bib_fbase = info[:bib_basename]
    bib_fpath = "#{IN_BIB_DIR}/#{bib_fbase}"
    xml_dest_fname = "#{OUT_DIR}/#{mms_id}#{BIB_OUT_FNAME_SUFFIX}"
    cmd = "xsltproc #{FLATTEN_XSLT} #{bib_fpath} | #{FIXMARC_EXE} #{bib_fbase} > #{xml_dest_fname} 2>> #{BIB_FIX_LOG}"
    STDERR.puts "INFO: Command: #{cmd}"

    output = %x{ #{cmd} }		# Execute OS command
    # FIXME: Does not detect "xsltproc result code (since FIXMARC_EXE is run afterwards).
    res = $?
    unless res.to_s == "0"
      STDERR.puts <<-EO_MSG.gsub(/^\t*/, "")
		ERROR in #{self.class}.#{__method__}: #{res.inspect}
		  Stdout/stderr was: #{output}
	EO_MSG
    end
  end

  ############################################################################
  # Returns the string matching the first pair of round brackets in regex.
  def self.get_1value_from_file(fpath, regex, will_suppress_warning=false)
    matches = File.foreach(fpath).inject([]){|a,line| line.match(regex); a << $1 if $1; a}
    if matches.length == 0
      STDERR.puts "WARNING: No match found for #{regex.inspect} in file\n  #{fpath}" unless will_suppress_warning
      return nil

    elsif matches.length > 1
      STDERR.puts "WARNING: More than one match found for #{regex.inspect} in file\n  #{fpath}\n  Matches: #{matches.inspect}" unless will_suppress_warning
      return nil
    end
    matches.first
  end

  ############################################################################
  def get_authorname(mms_id)
    xml_dest_fname = "#{OUT_DIR}/#{mms_id}#{BIB_OUT_FNAME_SUFFIX}"
    authorname = self.class.get_1value_from_file(xml_dest_fname, RE_SURNAME)
    unless authorname
      given_names = self.class.get_1value_from_file(xml_dest_fname, RE_GIVENNAMES)
      unless given_names
        STDERR.puts "ERROR: MMS ID #{mms_id}: Author has neither surname nor given name!"
        exit 1
      end
      given_names.sub(/^([^ ]+)( |$)/i, '')	# Extract first given name
      authorname = $1
      unless authorname
        STDERR.puts "ERROR: MMS ID #{mms_id}: Something went wrong extracting author given name!"
        exit 1
      end
    end
    authorname.gsub(RE_FILTER_AUTHORNAME, '')
  end

  ############################################################################
  def get_thesis_year(mms_id)
    xml_dest_fname = "#{OUT_DIR}/#{mms_id}#{BIB_OUT_FNAME_SUFFIX}"
    year = self.class.get_1value_from_file(xml_dest_fname, RE_YEAR)
    unless year
        STDERR.puts "ERROR: MMS ID #{mms_id}: Cannot find publication year for thesis!"
        exit 1
    end
    year
  end

  ############################################################################
  def create_dest_basename(mms_id, parts)
    # Examples of destination filenames:
    #   # 1 volume; no extra material
    #   Thesis-Surname-1987.pdf		# No sequence number if only 1 file
    #
    #   # 2 volumes; no extra material
    #   Thesis-Surname-1987-01.pdf
    #   Thesis-Surname-1987-02.pdf
    #
    #   # 1 volume; with extra material
    #   Thesis-Surname-1987-01.pdf
    #   Thesis-Surname-1987-02-cdrom.zip
    #
    #   # 2 volumes; with extra material
    #   Thesis-Surname-1987-01.pdf
    #   Thesis-Surname-1987-02.pdf
    #   Thesis-Surname-1987-03-cdrom.zip

    year = get_thesis_year(mms_id)
    authorname = get_authorname(mms_id)

    counts = @info_by_mms_id[mms_id][:filetype_counts]
    seq_num_offset = counts[:thesis_vol] == 1 ? 1 : 0
    omit_seq = counts[:thesis_vol] == 1 && counts[:extra_matl] == 0
    seq = omit_seq ? "" : sprintf("-%02d", parts[:seq_num].to_i + seq_num_offset)

    descr = parts[:descr] ? "-#{parts[:descr]}" : ""
    parts[:dest_basename] = "Thesis-#{authorname}-#{year}#{seq}#{descr}.#{parts[:ext]}"
  end

  ############################################################################
  def create_dest_basenames_for_target_files
    @info_by_mms_id.sort{|a,b| a[1][:sort_num]<=>b[1][:sort_num]}.each{|mms_id,info|
      info[:a_fname_parts].each{|parts| create_dest_basename(mms_id, parts)}
    }
  end

  ############################################################################
  def create_filetype_counts_for_target_files
    @info_by_mms_id.sort{|a,b| a[1][:sort_num]<=>b[1][:sort_num]}.each{|mms_id,info|
      extra_matl_count = 0
      thesis_vol_count = 0
      info[:a_fname_parts].each{|parts|
        # Thesis-scan files have :descr field of nil.
        # Extra-material files have a text-description in the :descr field.
        parts[:descr] ? extra_matl_count += 1 : thesis_vol_count += 1
      }
      info[:filetype_counts] = {
        :thesis_vol => thesis_vol_count,
        :extra_matl => extra_matl_count,
      }
    }
  end

  ############################################################################
  def create_dest_scan_files(mms_id, info)
    dest_dirpath_rel = "#{mms_id}.d"
    dest_dirpath_abs = "#{OUT_DIR}/#{dest_dirpath_rel}"
    Dir.mkdir(dest_dirpath_abs) unless File.directory?(dest_dirpath_abs)

    dest_files_rel = []
    src_files = []
    src_file_mod_times = []

    info[:a_fname_parts].each{|parts|
      src_fpath = "#{IN_SCAN_DIR}/#{parts[:whole]}"
      src_files << File.basename(src_fpath)
      src_file_mod_times << File.stat(src_fpath).mtime

      dest_fpath = "#{dest_dirpath_abs}/#{parts[:dest_basename]}"
      dest_files_rel << "#{dest_dirpath_rel}/#{parts[:dest_basename]}"

      STDERR.puts "INFO: Copying #{src_fpath} to #{dest_fpath}"
      FileUtils.cp(src_fpath, dest_fpath, CP_OPTS)
    }
    # Store extra info for later addition to bib xml file
    extra_bib_info = {
      :dest_files_rel     => dest_files_rel,
      :src_files          => src_files,
      :src_file_mod_times => src_file_mod_times,
      :s_scan_date => src_file_mod_times.max.strftime(SCAN_DATE_FORMAT),
    }
    store_extra_bib_info(mms_id, extra_bib_info)
  end

  ############################################################################
  def store_extra_bib_info(mms_id, extra_bib_info)
    extras_fname = "#{OUT_DIR}/#{mms_id}#{EXTRA_BIB_INFO_FNAME_SUFFIX}"
    File.open(extras_fname, 'w'){|f| YAML.dump(extra_bib_info, f)}
  end

  ############################################################################
  def create_dest_bib_files
    File.delete(BIB_FIX_LOG) if File.exists?(BIB_FIX_LOG)	# Prepare log for writing
    unless @has_reg_at_exit_log
      at_exit{ puts "Review the log file #{BIB_FIX_LOG}"}
      @has_reg_at_exit_log = true
    end
    @info_by_mms_id.sort{|a,b| a[1][:sort_num]<=>b[1][:sort_num]}.each{|mms_id,info|
      create_dest_bib_file(mms_id, info)
    }
  end

  ############################################################################
  def create_dest_scan_fileset
    @info_by_mms_id.sort{|a,b| a[1][:sort_num]<=>b[1][:sort_num]}.each{|mms_id,info|
      create_dest_scan_files(mms_id, info)
    }
  end

  ############################################################################
  def has_unique_dest_basenames(mms_id)
    num_basenames = @info_by_mms_id[mms_id][:a_fname_parts].length
    if num_basenames == 1
      true
    else
      basenames = @info_by_mms_id[mms_id][:a_fname_parts].map{|p| p[:dest_basename]}
      num_basenames == basenames.uniq.length
    end
  end

  ############################################################################
  def has_same_values(mms_id, key, ignore_case = true)
    num_basenames = @info_by_mms_id[mms_id][:a_fname_parts].length
    if num_basenames == 1
      true
    else
      @info_by_mms_id[mms_id][:a_fname_parts].each_with_index{|p,i|
        next if i == 0

        if ignore_case
          return false unless p[key].downcase == @info_by_mms_id[mms_id][:a_fname_parts].first[key].downcase
        else
          return false unless p[key] == @info_by_mms_id[mms_id][:a_fname_parts].first[key]
        end
      }
      true
    end

  end

  ############################################################################
  def get_seq_nums_warning(mms_id)
    seq_nums = @info_by_mms_id[mms_id][:a_fname_parts].
      sort{|a,b| a[:seq_num].to_i <=> b[:seq_num].to_i}.
      inject([]){|a,p| a << p[:seq_num]; a}
    return nil if seq_nums.length == 1		# OK

    offset = seq_nums.first.to_i
    seq_nums.each_with_index{|s_seq_num,i|
      i_seq_num = s_seq_num.to_i
      return :FPARTS_WARN_seqnums_not_consecutive unless i_seq_num == i + offset
    }
    nil						# OK
  end

  ############################################################################
  def get_logical_parts_warning(mms_id)
    # The array of fname parts for thesis volumes (ie. not extra materials with a :descr field)
    a_parts_vol = @info_by_mms_id[mms_id][:a_fname_parts].inject([]){|a,p| a << p unless p[:descr]; a}
    if a_parts_vol.length == 0
      return :FPARTS_WARN_no_thesis_volume_found

    elsif a_parts_vol.length == 1
      return :FPARTS_WARN_1volume_not_seqnum0 unless a_parts_vol[0][:seq_num] == "0"

    else
      return :FPARTS_WARN_multivolume_has_seqnum0 if a_parts_vol.any?{|p| p[:seq_num] == "0"}
    end
    get_seq_nums_warning(mms_id)		# nil means OK
  end

=begin
  ############################################################################
  def has_unique_dest_basenames_test1
    @info_by_mms_id["9911921501771"][:a_fname_parts] << {
      :initial=>"t", 
      :seq_num=>"00003", 
      :dest_basename=>"Thesis-Flonta-1988-03-cdrom.zip", 
      :ext=>"zip", 
      :descr=>"cdrom", 
      :name=>"flonta", 
      :whole=>"flonta_t_9911921501771_00003_cdrom.zip"
    }
  end

  ############################################################################
  def has_same_values_test1
    name = "FlontaX"
    @info_by_mms_id["9911921501771"][:a_fname_parts].first[:name] = name
    @info_by_mms_id["9911921501771"][:a_fname_parts].first[:whole] = "#{name}_t_9911921501771_1.pdf"
  end

  ############################################################################
  def has_same_values_test2
    initial = "X"
    @info_by_mms_id["9911921501771"][:a_fname_parts].first[:initial] = initial
    @info_by_mms_id["9911921501771"][:a_fname_parts].first[:whole] = "flonta_#{initial}_9911921501771_1.pdf"
  end
=end

  ############################################################################
  # Return a warning message re author name. This is non-fatal because this
  # program and the person scanning the thesis may make a different
  # judgement regarding the author surname or which special characters
  # in the name to omit in the filename.
  def get_authorname_warning_msg(mms_id)
    bib_authorname = get_authorname(mms_id).downcase
    srcfile_authorname = @info_by_mms_id[mms_id][:a_fname_parts][0][:name].downcase
    ok = bib_authorname == srcfile_authorname.gsub(RE_FILTER_AUTHORNAME, '')
    ok ? nil : "Bib authorname (#{bib_authorname}) does not match *pruned* scan-file authorname (#{srcfile_authorname})"
  end

  ############################################################################
  def verify_more_target_fileparts
    # Testing:
    # has_unique_dest_basenames_test1
    # has_same_values_test1
    # has_same_values_test2

    non_unique_basenames_info = []
    not_same_names_info = []
    not_same_initials_info = []
    logical_parts_warnings = []
    authorname_warnings = []
    will_quit = false

    @info_by_mms_id.sort{|a,b| a[1][:sort_num]<=>b[1][:sort_num]}.each{|mms_id,info|
      ok = has_same_values(mms_id, :name)
      not_same_names_info << [mms_id, info[:a_fname_parts].inject([]){|a,p|
        a << p[:whole]
        a
      }] unless ok

      ok = has_same_values(mms_id, :initial)
      not_same_initials_info << [mms_id, info[:a_fname_parts].inject([]){|a,p|
        a << p[:whole]
        a
      }] unless ok

      ok = has_unique_dest_basenames(mms_id)
      non_unique_basenames_info << [mms_id, info[:a_fname_parts].inject({}){|h,p|
        h[:orig] ||= []
        h[:dest] ||= []
        h[:orig] << p[:whole]
        h[:dest] << p[:dest_basename]
        h
      }] unless ok

      warn_sym = get_logical_parts_warning(mms_id)
      logical_parts_warnings << [mms_id, warn_sym] if warn_sym

      warn_msg = get_authorname_warning_msg(mms_id)
      authorname_warnings << [mms_id, warn_msg] if warn_msg
    }
    unless non_unique_basenames_info.empty?
      STDERR.puts "ERROR: Files for the following MMS IDs generate non-unique destination basenames:"
        non_unique_basenames_info.each{|mms_id,other| STDERR.puts "* MMS ID: #{mms_id}\n    Orig: #{other[:orig].inspect}\n    Dest: #{other[:dest].inspect}"}
      will_quit = true
    end
    unless not_same_names_info.empty?
      STDERR.puts "ERROR: Files for the following MMS IDs have different author names:"
      not_same_names_info.each{|mms_id,other| STDERR.puts "* MMS ID: #{mms_id}\n    #{other.inspect}"}
      will_quit = true
    end
    unless not_same_initials_info.empty?
      STDERR.puts "ERROR: Files for the following MMS IDs have different author initials:"
      not_same_initials_info.each{|mms_id,other| STDERR.puts "* MMS ID: #{mms_id}\n    #{other.inspect}"}
      will_quit = true
    end
    unless logical_parts_warnings.empty?
      STDERR.puts "ERROR: The following MMS IDs have a file-naming warning:"
      logical_parts_warnings.each{|mms_id,other|
        msg = MSG_BY_SYMBOL[other] ? MSG_BY_SYMBOL[other] : other.inspect
        STDERR.puts "* MMS ID: #{mms_id}\n    #{msg}"
      }
      will_quit = true
    end
    unless authorname_warnings.empty?
      STDERR.puts "WARNING: The following MMS IDs have discrepancies between bib authorname and scan-file authorname:"
      authorname_warnings.each{|mms_id,other| STDERR.puts "* MMS ID: #{mms_id}\n    #{other.inspect}"}
    end
    exit(2) if will_quit
  end

  ############################################################################
  def collect_embargoed_mms_ids
    @mms_ids_all = []
    @mms_ids_approved = []
    @mms_ids_embargoed = []
    @info_by_mms_id.sort{|a,b| a[1][:sort_num]<=>b[1][:sort_num]}.each{|mms_id,info|
      @mms_ids_all << mms_id

      xml_dest_fname = "#{OUT_DIR}/#{mms_id}#{BIB_OUT_FNAME_SUFFIX}"
      is_restricted = self.class.get_1value_from_file(xml_dest_fname, RE_IS_RESTRICTED, true)
      if is_restricted
        @mms_ids_embargoed << mms_id
      else
        @mms_ids_approved << mms_id
      end
    }
    mms_ids_str = @mms_ids_all.join(NEWLINE) + NEWLINE
    File.open(FNAME_ALL_LIST, 'w').write(mms_ids_str)

    mms_ids_str = @mms_ids_approved.join(NEWLINE) + NEWLINE
    File.open(FNAME_APPROVED_LIST, 'w').write(mms_ids_str)

    mms_ids_str = @mms_ids_embargoed.join(NEWLINE) + NEWLINE
    File.open(FNAME_EMBARGOED_LIST, 'w').write(mms_ids_str)

    mms_ids_str = @mms_ids_not_processed.join(NEWLINE) + NEWLINE
    File.open(FNAME_NOT_PROCESSED_LIST, 'w').write(mms_ids_str)
  end

  ############################################################################
  def self.main
    puts "Process all scanned files"
    puts "========================="

    f = ScannedFilesProcessor.new
    f.collect_target_filenames
    f.collect_target_fileparts
    f.create_filetype_counts_for_target_files

    # Process bib metadata
    f.collect_bib_basenames
    f.collect_related_bib_files
    f.create_dest_bib_files

    # Requires result bib-metadata (ie. MMSID.xml) to already be written
    f.create_dest_basenames_for_target_files
##puts "f.info_by_mms_id=#{f.info_by_mms_id.inspect}"
    f.verify_more_target_fileparts
    f.create_dest_scan_fileset
    f.collect_embargoed_mms_ids
  end
end

##############################################################################
# Main()
##############################################################################
ScannedFilesProcessor.main

