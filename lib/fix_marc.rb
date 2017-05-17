#!/usr/bin/ruby
#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# Typical usage:
# $ ./fix_marc.rb < thesisBib1rec.flat2.xml
# $ cat thesisBib1rec.flat2.xml |./fix_marc.rb [thesisBib1rec.flat2.xml]
#
# Add new fields to the (already flattened) XML bib record. The new fields
# are fixed (ie. enhanced) versions of existing fields. Eg.
# - Extract MMS ID from MARC 001.
# - Combine the desired MARC 245 "Title Statement" subfields. 245 is a
#   non-repeating field. Add a new XML element with the combined subfields.
# - Extract publication date from MARC 260.c & 264.c. 260 & 264 are
#   repeating fields.
# - Etc.
##############################################################################
# Add dirs to the library path
$: << File.expand_path("../lib", File.dirname(__FILE__))
$: << File.expand_path("../etc", File.dirname(__FILE__))
require "school_new_cleaner.rb"
require "school_orig_cleaner"

class MarcXmlEnricher
  DEBUG_KEYWORDS = false

  FORCE_SURNAME = true		# If author has 1 name, force it to be a surname

  EMB_YEAR_MIN = 1900
  EMB_YEAR_MAX = 2040		# Max embargo year

  PUB_YEAR_RANGE = 1960..2016
  AUTHOR_DATES_REGEX = /^(19|20)\d{2}-((19|20)\d{2})?$/	# Eg. "1950-" or "1950-2010"
  NAME_TRAILING_INITIAL_MAYBE = /([^A-Z])\.$/

  MONTH_PARAMS = [
    {:regex => /^january$/i,	:max_days => 31},
    {:regex => /^february$/i,	:max_days => 29},	# FIXME: Improve accuracy?
    {:regex => /^march$/i,	:max_days => 31},
    {:regex => /^april$/i,	:max_days => 30},

    {:regex => /^may$/i,	:max_days => 31},
    {:regex => /^june$/i,	:max_days => 30},
    {:regex => /^july$/i,	:max_days => 31},
    {:regex => /^august$/i,	:max_days => 31},

    {:regex => /^september$/i,	:max_days => 30},
    {:regex => /^october$/i,	:max_days => 31},
    {:regex => /^november$/i,	:max_days => 30},
    {:regex => /^december$/i,	:max_days => 31},
  ]

  # Excerpt from http://www.loc.gov/marc/languages/language_code.html
  LANGUAGES = {
    #Code => Language
    "dak" => "Dakota",
    "eng" => "English",
    "gre" => "Greek, Modern (1453-)",
    "ind" => "Indonesian",
    "ita" => "Italian",
    "spa" => "Spanish",
  }

  DEGREE_CATEGORIES = %w{Doctorate Masters}

  OPTS_CLEAN_ORIG_SCHOOL = {
    :attr			=> :school,
    :value_prefix		=> "    <meta tagcode=\"orig_school.cleaned1\">",
    :value_suffix		=> "</meta>",
    :will_write_if_invalid	=> false,
    :value_if_invalid		=> "UNKNOWN_CLEANED_ORIG_SCHOOL",
  }

  OPTS_CLEAN_ORIG_SCHOOL_SEQ = {
    :attr			=> :school_seq,
    :value_prefix		=> "    <meta tagcode=\"orig_school_seq.cleaned1\">",
    :value_suffix		=> "</meta>",
    :will_write_if_invalid	=> false,
    :value_if_invalid		=> "UNKNOWN_CLEANED_ORIG_SCHOOL_SEQ",
  }

  OPTS_CLEAN_NEW_SCHOOL = {
    :attr			=> :school,
    :value_prefix		=> "    <meta tagcode=\"new_school.cleaned1\">",
    :value_suffix		=> "</meta>",
    :will_write_if_invalid	=> false,
    :value_if_invalid		=> "UNKNOWN_CLEANED_NEW_SCHOOL",
  }

  OPTS_CLEAN_NEW_ORG_UNIT = {
    :attr			=> :org_unit,
    :value_prefix		=> "    <meta tagcode=\"new_school_org_unit.cleaned1\">",
    :value_suffix		=> "</meta>",
    :will_write_if_invalid	=> false,
    :value_if_invalid		=> "UNKNOWN_CLEANED_NEW_ORG_UNIT",
  }

  ############################################################################
  def initialize(this_file_ref)
    @this_file_ref = this_file_ref || "NO_FILE_REF"

    @titles = {}				# Storage for field values
    @pub_dates = []
    @diss_notes = []

    @kw_list = []				# List of keywords (so we can avoid duplicates)
    @kw600 = {}
    @kw600_keys = []				# Keys for @kw600 (in the order they were read)
    @kw650 = {}
    @kw650_keys = []				# Keys for @kw650 (in the order they were read)

    @is_embargoed = false
    @release_date = nil
    @mms_id = nil
    @marc008 = nil
    @marc100a = nil
    @marc100d = nil
    @marc100q = nil

    @degree_categories = []
    @are_degree_categories_processed = false
    @call_num = nil
  end

  ############################################################################
  def process_xml_line(line)
    # Process MARC 001
    if line.match(/<meta.* tagcode="control\.001".*">(.*)<\/meta>/)
      @mms_id = $1

    # Process MARC 008
    elsif line.match(/<meta.* tagcode="control\.008".*">(.*)<\/meta>/)
      @marc008 = $1

    # Process MARC 100
    elsif line.match(/<meta.* tagcode="100\.(a|d|q)".* ind1="(.)" .*">(.*?),*<\/meta>/)
      code, ind1, value = Regexp.last_match[1..3]
      STDERR.puts "WARNING: #{rec_info} MARC 100 Indicator1 or name is empty!" unless ind1 && value
      if code == "a"
        STDERR.puts "WARNING: #{rec_info} MARC 100.a processing more than once for same record" if @marc100a
        @marc100a = {:ind1 => ind1, :name => value}

      elsif code == "d"
        STDERR.puts "WARNING: #{rec_info} MARC 100.d processing more than once for same record" if @marc100d
        @marc100d = value

      else
        STDERR.puts "WARNING: #{rec_info} MARC 100.q processing more than once for same record" if @marc100q
        @marc100q = value
      end

    # Process MARC 245
    elsif line.match(/<meta.* tagcode="245\.([^c])".*">(.*)<\/meta>/)
      @titles[$1] = $2

    # Process MARC 260.c & 264.c
    elsif line.match(/<meta.* tagcode="(26[04]\.c)".*">(.*)<\/meta>/)
      @pub_dates << {:tagcode => $1, :value => $2}

    # Process MARC 50X.a
    elsif line.match(/<meta.* tagcode="50[0-9]\.a"/)
      # Process MARC 502.a
      if line.match(/<meta.* tagcode="502\.a".*">(.*)<\/meta>/)
        @diss_notes << $1
      end

      # Process MARC 50X.a with a restriction (ie. probably an embargo)
      if line.match(/^.*tagcode="50[0-9]\.a".*restricted/i)
        STDERR.puts "WARNING: #{rec_info} Embargo processing more than once for same record" if @is_embargoed
        @is_embargoed = true
        @release_date = self.class.extract_release_date(line)
      end

    # Process MARC 6XX
    elsif line.match(/<meta.* tagcode="(6..)\.(.)"/)
      s6xx = $1 + "." + $2

      # Process MARC 600, 610, 611, 630, 653
      if line.match(/<meta.* tagcode="(600|610|611|630|653)\.(.)".* pid="([^"]+)".*">(.*?)[ :,]*<\/meta>/)
        tag, code, pid, value = Regexp.last_match[1..4]
        key = [pid, tag]				# The key for this MARC field
        unless @kw600_keys.include?(key)
          @kw600_keys << key
          @kw600[key] = []				# An array of values for all MARC subfields
        end
        @kw600[key] << value.sub(/([^A-Z])\.$/, "\\1")	# Discard trailing period unless /[A-Z]\.$/

      # Process MARC 650, 651, 695
      elsif line.match(/<meta.* tagcode="(650|651|695)\.(.)".* pid="([^"]+)".*">(.*?)[,\.]*<\/meta>/)
        tag, code, pid, value = Regexp.last_match[1..4]
        key = [pid, tag]				# The key for this MARC field
        unless @kw650_keys.include?(key)
          @kw650_keys << key
          @kw650[key] = {}
        end
        @kw650[key][code] ||= []			# An array of values for this MARC subfield
        @kw650[key][code] << value

      # Process MARC 655
      elsif line.match(/<meta.* tagcode="(655).*">(.*)<\/meta>/)
        STDERR.puts "WARNING: #{rec_info} Ignoring MARC #{s6xx} keywords: '#{$2}'"

      else
        # FIXME: Masters - check
        STDERR.puts "WARNING: #{rec_info} MARC #{s6xx} exists but not processed!"
      end

    # Process MARC 984
    elsif line.match(/<meta.* tagcode="984\.c".*">(.*)<\/meta>/)
      @call_num = $1

    # Add the enriched XML elements before this closing tag
    elsif line.match(/<\/flat1>/)
      show_new_xml_elements
    end

    puts line				# Duplicate input line
  end

  ############################################################################
  def show_new_xml_elements
    show_mms_id
    show_title
    show_publication_date

    show_language
    show_thesis_type
    show_degree_categories
    show_restriction_info

    show_school
    show_author
    show_keywords_subjects

    show_call_number
  end

  ############################################################################
  def show_call_number
    # Required for resource management. Not needed for Equella.
    call_num = @call_num ? @call_num : "UNKNOWN_BIB_CALL_NUMBER"
    puts "    <meta tagcode=\"call_number.fixed1\">#{call_num}</meta>"
  end

  ############################################################################
  def show_mms_id
    mms_id = @mms_id ? @mms_id : "UNKNOWN_MMS_ID"
    if @mms_id
      puts "    <meta tagcode=\"mms_id.fixed1\">#{@mms_id}</meta>"
    else
      STDERR.puts "WARNING: #{rec_info} MMS ID not found"
      puts "    <meta tagcode=\"mms_id.fixed1\">UNKNOWN_MMS_ID</meta>"
    end
  end

  ############################################################################
  def show_title
    # FIXME: strip out "[manuscript]" in 245$a or 245$b string?
    # Suspect error as this should be in field 245$h (which I am not extracting).
    if @titles.empty?
      STDERR.puts "WARNING: #{rec_info} Title not found"
      puts "    <meta tagcode=\"245.fixed1\">UNKNOWN_TITLE</meta>"
    else
      h_val = @titles["h"]
      if h_val
        # Typically:
        # - true if h_val like "...[manuscript] :" or "...[manuscript] /"
        # - false if alpha-numeric text appears after "[manuscript]"
        ok = h_val.match(/
          [\[\(\{]			# Open bracket char
          [^\]\)\}]+			# Text for MARC 245.h (medium)
          [\]\)\}]			# Close bracket char
          [:;\ \/\.\-]*			# Trailing non-alpha chars
          $				# End of string
        /x)
        STDERR.puts "WARNING: #{rec_info} Unexpected format or extra info in 245.h: '#{h_val}'" unless ok

        if h_val.match(/:/) && @titles["a"]
          a_val = @titles["a"].strip
          @titles["a"] = "#{a_val} :" if a_val.match(/[\w"'\)]$/i)
        end
        @titles.delete("h")
      end

      title = @titles.sort.map{|a| a[1]}.join(' ').sub(/[\/ ,:;]*$/, '')

      # FIXME: Use quote2()?
      # Escape double-quote for CSV compatibility. RFC 4180 says:
      #   If double-quotes are used to enclose fields, then a double-quote
      #   appearing inside a field must be escaped by preceding it with
      #   another double quote.  For example:  "aaa","b""bb","ccc"
      # NOTE: ruby(&quot;&quot;) -> xml(&quot;&quot;) -> CSV-text("")
      title.gsub!(/"/, "&quot;&quot;")
      puts "    <meta tagcode=\"245.fixed1\">#{title}</meta>"
    end
  end

  ############################################################################
  def show_keywords_subjects
    show_keywords_600
    show_keywords_650
    show_subjects
  end

  ############################################################################
  # Show keywords for MARC 600 and similar 6XX fields
  def show_keywords_600
    @kw600_keys.each{|key|	# Iterate thru tags in the same order we read them
      # For this instance (parent ID) of this tag...
      values = @kw600[key]
      pid, tag = key

      # Process all tags
      s = values.join(', ').gsub(/, \(/, " (")
      unless @kw_list.include?(s) || s == ""
        @kw_list << s
        dbug_s = DEBUG_KEYWORDS ? "#{tag}:" : ""
        puts "    <meta tagcode=\"keywords.fixed1\">#{dbug_s}#{s}</meta>"
      end
    }
  end

  ############################################################################
  # Show keywords for MARC 650, 651
  def show_keywords_650
    @kw650_keys.each{|key|	# Iterate thru tags in the same order we read them
      # For this instance (parent ID) of this tag...
      pid, tag = key
      next if tag == "695"

      # Process all subfields
      h_tag = @kw650[key]
      h_tag.sort.each{|code, values|
        next if code == "x"	# We will process subfield "x" with "a"
        s = values.join(', ')
        s = s + ", " + h_tag['x'].join(', ') if code == "a" && h_tag['x']
        unless @kw_list.include?(s) || s == ""
          @kw_list << s
          dbug_s = DEBUG_KEYWORDS ? "#{tag}.#{code}:" : ""
          puts "    <meta tagcode=\"keywords.fixed1\">#{dbug_s}#{s}</meta>"
        end
      }
    }
  end

  ############################################################################
  # Show subjects for MARC 695
  def show_subjects
    @kw650_keys.each{|key|	# Iterate thru tags in the same order we read them
      # For this instance (parent ID) of this tag...
      pid, tag = key
      next unless tag == "695"

      h_tag = @kw650[key]
      next unless h_tag['a']

      h_tag['a'].each{|s|
        subject = s.sub(/ *thesis *$/i, '')	# Remove "thesis" from end of 695.a
        puts "    <meta tagcode=\"subjects.fixed1\">#{subject}</meta>"
      }
    }
  end

  ############################################################################
  def show_author
    ind1 = @marc100a[:ind1]
    name = @marc100a[:name].sub(NAME_TRAILING_INITIAL_MAYBE, "\\1") # Discard trailing period unless it is an initial
    surname = nil
    given_names = nil
    full_name_display = nil
    STDERR.puts "WARNING: #{rec_info} Ind1=#{ind1} but 100.q is present! 100.a=#{name}" if ind1!="1" && @marc100q

    case ind1
    when "1"
      # Expect "Surname, Givennames" or "Surname"
      fields = name.split(",")
      if fields.length == 2
        name.match(/^(.*), *(.*)$/)
        surname = $1
        given_names = $2.strip.squeeze(" ")
        if @marc100q
          # Discard trailing period unless it is an initial
          ff_names = @marc100q.gsub(/^\(*|\)*\.?$/, '').strip.squeeze(" ").sub(NAME_TRAILING_INITIAL_MAYBE, "\\1")
          # Assume fuller-form names are "better" than given names if string is longer
          given_names = ff_names if ff_names.gsub(/\W/, '').length > given_names.gsub(/\W/, '').length
        end
        full_name_display = "#{given_names} #{surname}"

      elsif fields.length == 1
        STDERR.puts "WARNING: #{rec_info} Ind1=#{ind1} & 1 name. Assuming surname. Name=#{name}"
        surname = name
        given_names = ""
        full_name_display = surname

      else
        STDERR.puts "ERROR: #{rec_info} Ind1=#{ind1}. Unexpected number of CSV fields (#{fields.length}). No XML name elements will be written. Name=#{name}"
      end

    when "0"
      # Expect "Givennames Surname" or "Givennames"
      num_csv_fields = name.split(",").length
      fields = name.split(" ")
      if num_csv_fields != 1
        # FIXME: Masters
        STDERR.puts "ERROR: #{rec_info} Ind1=#{ind1} but #{num_csv_fields} CSV fields detected! No XML name elements will be written. Name=#{name}"

      elsif fields.length == 1
        if FORCE_SURNAME
          STDERR.puts "WARNING: #{rec_info} Ind1=#{ind1} & 1 name. Forcing surname. Name=#{name}"
          surname = fields[0]
          given_names = ""
          full_name_display = surname

        else
          STDERR.puts "WARNING: #{rec_info} Ind1=#{ind1} & 1 name. Assuming given name. Name=#{name}"
          surname = ""
          given_names = fields[0]
          full_name_display = given_names
        end

      else	# >1 name
        # FIXME: Gives bad result (an initial?) for Masters
        STDERR.puts "WARNING: #{rec_info} Ind1=#{ind1} & >1 name. Assuming surname on right. Name=#{name}"
        name.match(/^(.*) (.*)$/)
        surname = $2
        given_names = $1
        full_name_display = "#{given_names} #{surname}"
      end

    else	# MARC indicator 1 has other value
      STDERR.puts "ERROR: #{rec_info} Ind1=#{ind1}. No XML name elements will be written. Name=#{name}"
    end
    puts "    <meta tagcode=\"surname.fixed1\">#{surname}</meta>" if surname
    puts "    <meta tagcode=\"given_names.fixed1\">#{given_names}</meta>" if given_names
    puts "    <meta tagcode=\"full_name_display.fixed1\">#{full_name_display}</meta>" if full_name_display

    dates = @marc100d.to_s.strip
    unless dates.empty?
      has_expected_dates = dates.match(AUTHOR_DATES_REGEX)
      STDERR.puts "WARNING: %s Unexpected author dates '%s'. Does not match %s" %
        [rec_info, dates, AUTHOR_DATES_REGEX.inspect] unless has_expected_dates
      puts "    <meta tagcode=\"author_dates.fixed1\">#{dates}</meta>"
    end
  end

  ############################################################################
  def show_language
    # Language at 008 pos 35-37 (applicable for all Material Types).
    # Do NOT use 040.b as this is for *Language of cataloging*.
    pos = 35..37
    lang = "UNKNOWN_LANGUAGE" unless @marc008 && @marc008[pos]

    lang_code = @marc008[pos]
    lang = LANGUAGES[lang_code]
    lang = "UNKNOWN_LANGUAGE_CODE" unless lang
    puts "    <meta tagcode=\"lang_code.fixed1\">#{lang_code}</meta>"
    puts "    <meta tagcode=\"language.fixed1\">#{lang}</meta>"
  end

  ############################################################################
  def show_publication_date
    # If there is more than one publication date in 260.c or 264.c,
    # we will only consider the first one.
    h = @pub_dates.empty? ? nil : @pub_dates[0]
    if h && h[:value].match(/^[\[c]*([0-9]{4})[\]\.]*$/)
      pub_date = $1
      is_pub_date_range_ok = PUB_YEAR_RANGE.include?(pub_date.to_i)
    else
      pub_date = nil
      is_pub_date_range_ok = nil
    end

    if is_pub_date_range_ok
      # Extract year from 260.c or 264.c.
      puts "    <meta tagcode=\"#{h[:tagcode]}.fixed1\">#{pub_date}</meta>"
      puts "    <meta tagcode=\"publication_date.fixed1\">#{pub_date}</meta>"

    elsif @marc008 && %w{s m}.include?(@marc008[6..6]) && PUB_YEAR_RANGE.include?(@marc008[7..10].to_i)
      # This is a last resort if cannot extract year from 260.c or 264.c.
      # Extract year from 008 pos 07-10 if pos 06 is "s" or "m".
      puts "    <meta tagcode=\"control.008.fixed1\">#{@marc008[7..10]}</meta>"
      puts "    <meta tagcode=\"publication_date.fixed1\">#{@marc008[7..10]}</meta>"

    else
      STDERR.puts "ERROR: #{rec_info} Cannot extract publication date from #{@pub_dates.length} 260.c/264.c fields or MARC 008"
      puts "    <meta tagcode=\"publication_date.fixed1\">UNKNOWN_PUBLICATION_DATE</meta>"
    end
  end

  ############################################################################
  # MARC 695.d, eg. Doctorate, Masters
  def process_degree_categories
    return if @are_degree_categories_processed	# Already processed

    @degree_categories = []
    @kw650_keys.each{|key|	# Iterate thru tags in the same order we read them
      # For this instance (parent ID) of this tag...
      pid, tag = key
      next unless tag == "695"

      h_tag = @kw650[key]
      next unless h_tag['d']

      h_tag['d'].each_with_index{|dc,i|
        unless @degree_categories.include?(dc)
          @degree_categories << dc
          STDERR.puts "WARNING: #{rec_info} Invalid degree-category: '#{dc}'" unless DEGREE_CATEGORIES.include?(dc)
        end
      }
      num_unique_dcats = @degree_categories.uniq.length
      STDERR.puts "WARNING: #{rec_info} No degree-categories found!" if num_unique_dcats == 0
      STDERR.puts "WARNING: #{rec_info} Too many degree-categories: #{@degree_categories.inspect}" if num_unique_dcats > 1
      @are_degree_categories_processed = true
    }
  end

  ############################################################################
  def show_degree_categories
    process_degree_categories
    @degree_categories.each{|dc|
      puts "    <meta tagcode=\"degree_category.fixed1\">#{dc}</meta>"
    }
  end

  ############################################################################
  def show_thesis_type
    # FIXME: Test @degree_categories against type
    process_degree_categories
    thesis_type = nil

    @diss_notes.each{|dnote|
      thesis_type = case dnote
      when /\(doctor| ph\.d\.[ \)]|\((ph\.?d|m\.d|d\.ed|d\.sc|ed\. *d|d\. ed|edd|dr\.?p\.?h|d\.pub\.hlth)[\.\)]|\(dr of |\/phd\.d\)/i
        expected_dc = "Doctorate"
        type = "Doctor of Philosophy"
        ##STDERR.puts "WARNING: #{rec_info} Type (#{type}) does not match expected degree category (#{expected_dc})" unless @degree_categories.include?(expected_dc)
        STDERR.puts "WARNING: #{rec_info} Type (#{type}) does not match expected degree category (#{@degree_categories.inspect})" unless @degree_categories.include?(expected_dc)
        type

      when /\(m\.a\. .*\(research\)/i
        expected_dc = "Masters"
        type = "Masters by Research"
        STDERR.puts "WARNING: #{rec_info} Type (#{type}) does not match expected degree category (#{expected_dc})" unless @degree_categories.include?(expected_dc)
        type

      # FIXME: Incomplete!
      when /\(master of |\(M\. *(A|Biotech|Ec|Ed|Pol|Psych|Sc|Soc)\./i
        expected_dc = "Masters"
        type = "Masters by UNKNOWN_METHOD"
        STDERR.puts "WARNING: #{rec_info} Type (#{type}) does not match expected degree category (#{expected_dc})" unless @degree_categories.include?(expected_dc)
        type
      end
      break if thesis_type
    }
    thesis_type ||= "UNKNOWN_TYPE"
    puts "    <meta tagcode=\"502.type.fixed1\">#{thesis_type}</meta>"
  end

  ############################################################################
  def show_school
    len = @diss_notes.length
    # FIXME: Non-Flinders theses will be omitted
    puts "    <meta tagcode=\"school.fixed1\">UNKNOWN_SCHOOL-#{len}-Dissertation-Notes</meta>" if len == 0

    school = nil
    school_is_found = false	# Is a school found corresponding to this thesis?
    is_this_uni = false		# Only process theses published at this university
    @diss_notes.each{|note|
      is_this_uni = true if note.match(/^(thesis|research|project|dissertation|theses|typescript).*\(.+\).*-{1,2}.*flinders +(univ|institute)/i)

      # Perform a broad match (before extracting the school-string)
      # FIXME: scool?
      if !school && note.match(/scho|facu|dept|department|institute|discipline|studies|unit|scool/i)
        # Match keyword at the beginning
        note.match(/(Australia|University) ?,? *((school of|department of|dept\.? |faculty of|discipline of|institute of|centre ).*?)(, *\d{4})?[,\.]?$/i)
        # Match keyword at the end
        note.match(/(Australia|University) ?, *(.* (studies|dept\.?|department))(, *\d{4})?\.?$/i) unless $2
        # Match keyword in the middle
        note.match(/(Australia|University) ?,? *(((flinders|child|national|southgate|rehabilitation|social) .*(institute|centre|school)).*?)(, *\d{4})?\.?$/i) unless $2

        # Special cases (unexpected formatting)
        ### 9999183901771; Thesis (Ph.D.) -- Flinders Institute of Public Policy and Management.
        note.match(/(-- )(Flinders Institute of .*?)(, *\d{4})?\.?$/i) unless $2
        school = $2
        school_is_found = true
      end
    }

    if school_is_found
      school ||= "UNKNOWN_SCHOOL-CHECK"
      puts "    <meta tagcode=\"school.fixed1\">#{school}</meta>"

    else
      puts "    <meta tagcode=\"school.fixed1\">UNKNOWN_SCHOOL-NONE-FOUND</meta>"
    end

    if is_this_uni
      # Generate clean original school
      ocleaner = SchoolOriginalCleaner.new(school, @mms_id)
      ocleaner.clean_sequence
      ocleaner.show_school_attr(OPTS_CLEAN_ORIG_SCHOOL)
      ocleaner.show_school_attr(OPTS_CLEAN_ORIG_SCHOOL_SEQ)

      # Generate clean new/current school
      ncleaner = NewSchoolCleaner.new(school, @mms_id)
      ncleaner.clean
      ncleaner.show_school_attr(OPTS_CLEAN_NEW_SCHOOL)
      ncleaner.show_school_attr(OPTS_CLEAN_NEW_ORG_UNIT)

      puts "    <meta tagcode=\"university.fixed1\">Flinders University</meta>"

    else
      STDERR.puts "WARNING: #{rec_info} Unknown or unexpected university"
      puts "    <meta tagcode=\"university.fixed1\">UNKNOWN_OR_UNEXPECTED_UNIVERSITY</meta>"
    end
  end

  ############################################################################
  def show_restriction_info
    if @is_embargoed
      puts "    <meta tagcode=\"is_restricted.fixed1\" />"

      if @release_date
        puts "    <meta tagcode=\"release_date.fixed1\">#{@release_date}</meta>"
      else
        STDERR.puts "WARNING: #{rec_info} Unknown release date for an embargoed thesis"
        puts "    <meta tagcode=\"release_date.fixed1\">UNKNOWN_RELEASE_DATE</meta>"
      end
    end
  end

  ############################################################################
  # Extract embargo/restriction release-date from MARC note.
  # Return "YYYY-MM-DD" or return nil if invalid date or if no date.
  # FIXME: Perhaps override if MARC 263 exists. No 263 in the first set of 2436 records.
  def self.extract_release_date(marc_subfield_element)
    matchdata = marc_subfield_element.match(/tagcode="50[0-9]\.a".*restricted.*until ([^ ]+) +([^ ,]+)[ ,]+([^ \.]+)\.?<\/meta>$/i)
    return nil unless matchdata						# No date detected

    s_dd, s_month_name, s_yyyy = matchdata[1..3]
    # i_dd, i_mm, i_yyyy = integer equivalents of strings: s_dd, s_month_name, s_yyyy
    i_yyyy = s_yyyy.to_i
    return nil unless i_yyyy >= EMB_YEAR_MIN && i_yyyy <= EMB_YEAR_MAX	# Invalid year
    s_dd, s_month_name = [s_month_name, s_dd] unless s_dd.to_i >=1	# Swap month & day fields

    i_dd = s_dd.to_i
    i_mm = nil
    i_dd_max = 0
    MONTH_PARAMS.each_with_index{|m,i|
      if s_month_name.match(m[:regex])
        i_dd_max = m[:max_days]
        i_mm = i + 1
        break
      end
    }
    return nil unless i_mm && i_dd >=1 && i_dd <= i_dd_max		# Invalid month or day
    sprintf "%04d-%02d-%02d", i_yyyy, i_mm, i_dd			# Valid date
  end

  ############################################################################
  def rec_info
    sprintf "[%-62s %15s]", @this_file_ref.to_s, @mms_id.to_s
  end

end

##############################################################################
# Main()
##############################################################################
args = []
while ARGV[0] : args << ARGV.shift; end		# Remove all command line args
mxe = MarcXmlEnricher.new(args[0])

# Assumes input file has been formatted with: xmllint --format ...
while gets
  mxe.process_xml_line($_)
end

