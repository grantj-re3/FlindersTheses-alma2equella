#!/usr/bin/ruby
#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# Typical usage:
# $ cat POSTPROC.xml |./add_extras2xml.rb POSTPROC.xml
#
# After "fixing" and processing the bib record and then copying the
# scanned files to destination directory, this program adds the
# scanned filenames to the xml bib info.
#
# The program reads the "fixed" bib record from STDIN and writes the
# updated bib record to STDOUT.
#
##############################################################################
# Add dirs to the library path
$: << File.expand_path("../etc", File.dirname(__FILE__))
require "common_config"
require "yaml"

class Extras2XmlDepositor
  include CommonConfig

  ############################################################################
  def initialize(this_file_ref)
    if this_file_ref
      @this_file_ref = this_file_ref
      @mms_id = File.basename(this_file_ref).match(/^(\d+)/)[1]
    else
      @this_file_ref = "NO_FILE_REF"
      @mms_id = nil
    end
    @extra_bib_info = nil
  end

  ############################################################################
  def process_xml_line(line)
    # Add XML elements before this closing tag
    show_new_xml_elements if line.match(/<\/flat1>/)
    puts line				# Duplicate input line
  end

  ############################################################################
  def show_new_xml_elements
    if @mms_id
      extras_fname = "#{OUT_DIR}/#{@mms_id}#{EXTRA_BIB_INFO_FNAME_SUFFIX}"
      if File.exists?(extras_fname)
        @extra_bib_info = YAML.load_file(extras_fname)

        show_source_files
        show_attachment_files
        show_scan_date

      else
        STDERR.puts "ERROR: #{rec_info} File does not exist - '#{extras_fname}'"
      end

    else
      STDERR.puts "ERROR: #{rec_info} No MMS ID found!"
    end
  end

  ############################################################################
  def show_source_files
    @extra_bib_info[:src_files].each{|fname|
      puts "    <meta tagcode=\"original_file.fixed1\">#{fname}</meta>"
    }
  end

  ############################################################################
  def show_attachment_files
    @extra_bib_info[:dest_files_rel].each{|fname_rel|
      puts "    <meta tagcode=\"attachment.fixed1\">#{fname_rel}</meta>"
    }
  end

  ############################################################################
  def show_scan_date
    scan_date = @extra_bib_info[:s_scan_date]
    puts "    <meta tagcode=\"scan_date.fixed1\">#{scan_date}</meta>"
  end

  ############################################################################
  def rec_info
    "[#{@this_file_ref} #{@mms_id}]"
  end

end

##############################################################################
# Main()
##############################################################################
args = []
while ARGV[0] : args << ARGV.shift; end		# Remove all command line args
d = Extras2XmlDepositor.new(args[0])

# Assumes input file has been formatted with: xmllint --format ...
while gets
  d.process_xml_line($_)
end

