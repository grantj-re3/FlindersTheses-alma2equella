#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
##############################################################################
class SchoolOriginalCleaner
  DEBUG_SCHOOL = false
  DEBUG_SCHOOL_SEQ = false

  DUMMY_KEYWORD = "::"	# Replace extracted phrases with this dummy keyword

  SPECIAL_WORDS = {
    :lower_case => %w{and for in of on the},		# Force to lower case
    :upper_case => %w{crc (nceta) nt},			# Force to upper case
  }

  CLEANING_RULES = [
    # Prerequisites
    [/(Dept|Department)( |$)/,				"Dept.\\2"],
    [/&amp;/,						"and"],
    [/ \(pages 279-302\)$|, \[n.d\]$/,			""],
    [/Center/,						"Centre"],
    [/ of of /,						" of "],
    [/ \/ (Dept.)/,					", \\1"],

    # Do these after prerequisites
    [/^(Dept\.|School) of *$/,				""],
    [/Politcal/,					"Political"],
    [/Maths/,						"Mathematics"],
    [/Helaht|Helath/,					"Health"],
    [/Clincal/,						"Clinical"],
    [/adelaide/,					"Adelaide"],

    [/(School of Biological Science)$/,			"\\1s"],
    [/School of Biology/,				"School of Biological Sciences"],
    [/Compuer Science/,					"Computer Science"],
    [/(Computer), (Engineering and Mathematics)/,	"\\1 Science, \\2"],
    [/^(School of Computer Science)$/,			"\\1, Engineering and Mathematics"],

    [/ of Medicine-biotechnology$/,			" of Medical Biotechnology"],
    [/(Dept.) (Medical)/,				"\\1 of \\2"],
    [/ (Human Physiology) and (Centre for Neuroscience)/,	" \\1, \\2"],
    [/ *\(exercise Physiology\)$/,			", Exercise Physiology"],
    [/\[(and Midwifery)\]$/,				"\\1"],
    [/, and (Menzies School )/,				", \\1"],
    [/ and (School of )/,				", \\1"],

    [/^(Faculty of Health Sciences), (Orthopaedic Surgery)$/,	"\\1, Dept. of \\2"],
    [/(Faculty of Medicine, Nursing and) (Sciences)/,	"\\1 Health \\2"],
    [/(Faculty of) (Nursing and Health Science)$/,	"\\1 Medicine, \\2s"],
    [/NT (Clinical School)/,				"Northern Territory \\1"],
    [/^(Southgate)/,					"School of Medicine, \\1"],

    [/,? \(modern Greek\)/,				", Modern Greek"],
    [/^Dept. of (Modern Greek)$/,			"Dept. of Languages, \\1"],
    [/(Spanish) Dept\./,				"Dept. of \\1"],
    [/(Italian) Section$/,				"\\1"],
    [/(Languages) -/,					"\\1,"],

    [/ \[and\] (Adelaide Institute)/,			" \\1"],
    [/ and (Australian Institute of Sport)/,		" \\1"],
    [/^.*(National Institute of Labour Studies).*$/,	"\\1"],
    [/^(Institute of Public Policy and Management)/,	"Flinders \\1"],
    [/(Flinders Institute of Public Policy) (Management)/,	"\\1 and \\2"],
    [/^(English, Creative Writing and Australian Studies)$/,	"Dept. of \\1"],

    [/Education, Theology, Law and Humanities$/,	"Education, Humanities, Law and Theology"],
    [/ *[,:] *(Legal Studies)$/,			", Dept. of \\1"],

    [/^(Faculty of Social Sciences), (Women's Studies) Dept.$/,	"\\1, Dept. of \\2"],
    [/\/women's Studies Unit/,				", Women's Studies Unit"],
    [/^(Screen and Media) Studies/,			"Dept. of \\1"],
    [/^(Sociology|(Screen|Women's) Studies) Dept\.$/,	"Dept. of \\1"],
    [/^(Australian Studies)$/,				"Dept. of \\1"],
    [/^(American Studies|English) Dept\.$/,		"Dept. of \\1"],
    [/^(English) (and Australian Studies)$/,		"Dept. of \\1, Creative Writing \\2"],

  ]

  # A lower index indicates that area will be displayed before
  # (ie. to the left of) a higher index.
  SORT_INDEX = {
    # These areas seem to be mutually exclusive (in our catalog)
    :unit	=> 20,
    :institute	=> 30,
    :centre	=> 40,
    :discipline	=> 50,

    # Areas below are listed from more specific to more general in the hierarchy
    :dept	=> 60,
    :school	=> 70,
    :faculty	=> 80,
  }

  attr_reader :school_raw, :school, :mms_id

  ############################################################################
  def initialize(school, mms_id=nil)
    @school_raw = school
    @mms_id = mms_id

    @is_invalid = @school_raw.nil? || @school_raw.match(/^UNKNOWN/)
    @school = nil
    @school_phrases = {}
  end

  ############################################################################
  # Assumes clean() has already been invoked
  def clean_sequence_debug
    keywords = []
    keywords << :dept       if @school.match /Dept/
    keywords << :school     if @school.match /School/
    keywords << :faculty    if @school.match /Faculty/

    # 1a/ "Discipline of ..."; no commas; terminated by "$|, keyword"
    # 2a/ "... Unit"; no commas; extract from last comma
    # 3a/ "Centre for ..."; no commas; terminated by "$|, keyword"
    # 3b/ "Flinders ... Centre"; no commas; extract from last comma; exclude "Drama Centre"
    # 4a/ (Institute of|Flinders Institute of|National Institute of |Adelaide Institute for|Southgate Institute for);
    #     may contain commas; terminated by "$|, keyword"; issue "Australian Institute of Sport"
    # 4b/ "... Institute and ..."

    # These seem to be mutually exclusive
    keywords << :discipline if @school.match /Discipline/
    keywords << :unit       if @school.match /Unit/
    keywords << :centre     if @school.match /Centre/
    keywords << :institute  if @school.match /Institute/

    keywords.length
  end

  ############################################################################
  def clean_sequence
    return if @is_invalid
    clean
    keywords_count = clean_sequence_debug

    # Extract tricky phrases first (and replace with DUMMY_KEYWORD) before
    # phrases which are easy to extract.
    keyword_re_s = "(Dept|School|Faculty|Discipline|Unit|Centre|Institute|#{DUMMY_KEYWORD})"
    phrases = {}
    area = String.new(@school)	# Process a copy of the object

    # Unit or GGT UDRH or FCE
    area.match /, *([^,]+Unit)/
    area.match /, *(Greater Green Triangle University Dept. of Rural Health)/ unless $1
    area.match /(Flinders Clinical Effectiveness)/ unless $1
    if $1
      phrases[:unit] = $1
      area.sub!(/#{Regexp.quote(phrases[:unit])}/, DUMMY_KEYWORD)
    end

    # Discipline
    area.match /(Discipline of .*?)($|[, ]+#{keyword_re_s})/
    if $1
      phrases[:discipline] = $1
      area.sub!(/#{Regexp.quote(phrases[:discipline])}/, DUMMY_KEYWORD)
    end

    # Centre of research or Drama Centre or research group
    area.match /(Flinders [^,]+ Centre)($|[, ]+#{keyword_re_s})/
    area.match /(National Centre for .*?)($|[, ]+#{keyword_re_s})/ unless $1
    area.match /(Drama Centre)($|[, ]+#{keyword_re_s})/ unless $1
    area.match /, *([^,]+Research Group)/ unless $1
    area.match /(Centre for .*?)($|[, ]+#{keyword_re_s})/ unless $1
    if $1
      phrases[:centre] = $1
      area.sub!(/#{Regexp.quote(phrases[:centre])}/, DUMMY_KEYWORD)
    end

    # Institute of research or Australian Institute of Sport
    area.match /((Adelaide|Australian|Flinders|National|Southgate) Institute (of|for) .*?)($|[, ]+#{keyword_re_s})/
    area.match /(Child Health Research Institute .*?)($|[, ]+#{keyword_re_s})/ unless $1
    area.match /(Institute (of|for) .*?)($|[, ]+#{keyword_re_s})/ unless $1
    if $1
      phrases[:institute] = $1
      area.sub!(/#{Regexp.quote(phrases[:institute])}/, DUMMY_KEYWORD)
    end

    # Dept (multiple)
    a = []
    str = ""
    while str
      area.match /(Depts?\. of .*?)($|[, ]+#{keyword_re_s})/
      str = $1
      if str
        a << str
        area.sub!(/#{Regexp.quote(str)}/, DUMMY_KEYWORD)
      end
    end
    phrases[:dept] = a.join(", ") unless a.empty?

    # School (multiple)
    a = []
    str = ""
    while str
      area.match /(Flinders Business School)($|[, ]+#{keyword_re_s})/
      area.match /(Flinders Law School(, Criminology)?)($|[, ]+#{keyword_re_s})/ unless $1
      area.match /(Northern Territory Clinical School)($|[, ]+#{keyword_re_s})/ unless $1
      area.match /(Menzies School of .*?)($|[, ]+#{keyword_re_s})/ unless $1
      area.match /(School of .*?)($|[, ]+#{keyword_re_s})/ unless $1
      str = $1
      if str
        a << str
        area.sub!(/#{Regexp.quote(str)}/, DUMMY_KEYWORD)
      end
    end
    phrases[:school] = a.join(", ") unless a.empty?

    # Faculty
    area.match /(Faculty of .*?)($|[, ]+#{keyword_re_s})/
    if $1
      phrases[:faculty] = $1
      area.sub!(/#{Regexp.quote(phrases[:faculty])}/, DUMMY_KEYWORD)
    end

    if DEBUG_SCHOOL_SEQ
      phrases_s = phrases.values.join(", ")
      ch_warn = @school.length == phrases_s.length ? " " : "#"

      STDERR.printf("@@@ %s (%d,%d) [%2d,%2d] phrases=%-60s |%s |%s\n",
        ch_warn, keywords_count, phrases.count,
        @school.length, phrases_s.length,
        phrases.inspect, area, @school)
    end
    @school_phrases = phrases
  end

  ############################################################################
  def clean
    return if @is_invalid

    @school = self.class.capitalise_words(@school_raw, SPECIAL_WORDS)
    CLEANING_RULES.each{|pattern,repl| @school.gsub!(pattern, repl)}

    STDERR.printf("@@@  %-17s  %-10s  |%s\n",
      "#{@mms_id}", "@school=#{@school.inspect}",
      "#{@school_raw}") if DEBUG_SCHOOL
  end

  ############################################################################
  def self.capitalise_words(s, special_words=nil)
    special_words ||= {:lower_case => [], :upper_case => []}
    strings = []

    s.split(/ +/).each{|word|
      word_downcase = word.downcase
      strings << if special_words[:lower_case].include?(word_downcase)
        word_downcase

      elsif special_words[:upper_case].include?(word_downcase)
        word.upcase

      else
        word.capitalize
      end
    }
    strings.join(" ")
  end

  ############################################################################
  def show_school_attr(opts)
    if !@is_invalid || @is_invalid && opts[:will_write_if_invalid]
      value = if @is_invalid
        opts[:value_if_invalid]

      elsif opts[:attr] == :school_raw
        @school_raw

      elsif opts[:attr] == :school
        @school

      else		# :school_seq
        @school_phrases.sort{|a,b| SORT_INDEX[a[0]] <=> SORT_INDEX[b[0]]}.map{|k,v| v}.join(", ")
      end

      puts "#{opts[:value_prefix]}#{value}#{opts[:value_suffix]}"
    end
  end

end

