#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# This class attempts to clean the school info by mapping it to the
# current school name.
#
##############################################################################
class NewSchoolCleaner
  DEBUG_KEY = false

  SCHOOLS_NOW_XMLFIELDS = {
    :bus  => {:org_unit => "436", :school => "Flinders Business School",                      :faculty => "Faculty of Social and Behavioural Sciences"},
    #:is   => {:org_unit => "937", :school => "School of International Studies",               :faculty => "Faculty of Social and Behavioural Sciences"},
    :ir   => {:org_unit => "",    :school => "School of History and International Relations", :faculty => "Faculty of Social and Behavioural Sciences"},
    :psy  => {:org_unit => "426", :school => "School of Psychology",                          :faculty => "Faculty of Social and Behavioural Sciences"},
    :saps => {:org_unit => "938", :school => "School of Social and Policy Studies",           :faculty => "Faculty of Social and Behavioural Sciences"},
    :nils => {:org_unit => "492", :school => "National Institute of Labour Studies",          :faculty => "Faculty of Social and Behavioural Sciences"},

    :law  => {:org_unit => "210", :school => "Flinders Law School",                           :faculty => "Faculty of Education, Humanities and Law"},
    :edu  => {:org_unit => "220", :school => "School of Education",                           :faculty => "Faculty of Education, Humanities and Law"},
    :haca => {:org_unit => "917", :school => "School of Humanities and Creative Arts",        :faculty => "Faculty of Education, Humanities and Law"},
    :bao  => {:org_unit => "203", :school => "Bachelor of Arts Office",                       :faculty => "Faculty of Education, Humanities and Law"},

    :bs   => {:org_unit => "330", :school => "School of Biological Sciences",                 :faculty => "Faculty of Science and Engineering"},
    :caps => {:org_unit => "380", :school => "School of Chemical and Physical Sciences",      :faculty => "Faculty of Science and Engineering"},
    :csem => {:org_unit => "390", :school => "School of Computer Science, Engineering and Mathematics",   :faculty => "Faculty of Science and Engineering"},
    :env  => {:org_unit => "300", :school => "School of the Environment",                     :faculty => "Faculty of Science and Engineering"},
    :sc21 => {:org_unit => "",    :school => "Flinders Centre for Science Education in the 21st Century", :faculty => "Faculty of Science and Engineering"},

    :hs   => {:org_unit => "750", :school => "School of Health Sciences",                     :faculty => "Faculty of Medicine, Nursing and Health Sciences"},
    :med  => {:org_unit => "928", :school => "School of Medicine",                            :faculty => "Faculty of Medicine, Nursing and Health Sciences"},
    :nm   => {:org_unit => "601", :school => "School of Nursing &amp; Midwifery",             :faculty => "Faculty of Medicine, Nursing and Health Sciences"},

    :none => {:org_unit => "-1",  :school => "UNKNOWN_SCHOOL-NO-MATCH",                       :faculty => "UNKNOWN_FACULTY-NO-MATCH"},
  }

  attr_reader :school, :key, :mms_id

  ############################################################################
  def initialize(school, mms_id=nil)
    @school_raw = school
    @mms_id = mms_id
    @key = nil
  end

  ############################################################################
  def clean
    return if @school_raw.nil? || @school_raw.match(/^UNKNOWN/)
    @key = nil

    # Override the regex rules below by assigning @key according to MMS ID
=begin
    s_mms_id = "#{@mms_id}"
    @key = if %w{996661093301771}.include?(s_mms_id)
      :hs
    end
=end

    unless @key
      @key = case @school_raw.downcase

      # Faculty of Social and Behavioural Sciences
      when /school.*(business|commerc)| business.*school/
        :bus
      when /((school|dept|centre|department).*((development|international|american|asian).*stud|history))|american.*stud.*dept/
        :ir
      when /(school|dept).*psychology/
        :psy
      when /((school|dept|institute|department).*(sociology|public.* policy.* management|social.* work|(social.*policy|women.s).* stud|politics))|(women.s.* stud|sociology).*(dept|department)/
        :saps
      when /national.* institute.* labour.* stud/
        :nils

      # Faculty of Education, Humanities and Law
      when /school.* law|flinders law school/
        :law
      when /(school|dept|institute).* of( special| international){0,1} +education/
        :edu
      when /((school|dept|department).*(english|theology|language|greek|spanish|french|archaeology|humanities|philos[o]?phy|drama|tourism|(australian|cultural|screen).* stud|screen.*media))|^australian stud|^english[, ]|screen.*(stud.*department|media.*stud)|australian studies unit/
        :haca

      # Faculty of Science and Engineering
      when /(school|dept).* of biolog/
        :bs
      when /((school|dept).* (chemistry|chemical|physics|physical sciences))|nanomaterials.*research.*group|^faculty of chemistry$/
        :caps
      when /(school|dept).*(informatics|compu[t]?er.*engineering.*math|computer science|mathematics)/
        :csem
      when /(school|dept|department).*(environment|earth)/
        :env

      # Faculty of Medicine, Nursing and Health Sciences
      when /((discipline|dept|department|school).* ((public|rural) health|nutrition.* dietetics|palliative.* supportive|rehabilitation|speech pathology))|rehabilitation.* unit|disability.* (community inclusion|stud)|school of health sciences/
        :hs

      when /((school|dept|department).*(medicine|medical|surgery|infectious disease|general practice|haematology|psychiatry|immunology.*allergy.*arthritis|human physiology|ophthalmology|clinical pharmacology|gastroenterology|histology|paediatric))|orthopaedic surgery|northern territory clinical school|southgate institute.* health|child health research institute|flinders clinical effectiveness/
        :med

      when /school.*nursing/
        :nm

      else
        :none
      end
    end

    STDERR.printf(">>>  %-17s  %-10s  |%s  |%s\n",
      "#{@mms_id}", "@key=#{@key.inspect}",
      "#{@school_raw}", SCHOOLS_NOW_XMLFIELDS[key].inspect) if DEBUG_KEY

    @key
  end

  ############################################################################
  def show_school_attr(opts)
    is_invalid = @key.nil? || @key == :none

    if !is_invalid || is_invalid && opts[:will_write_if_invalid]
      value = if is_invalid
        opts[:value_if_invalid]

      elsif opts[:attr] == :school_raw
        @school_raw

      elsif [:org_unit, :school, :faculty].include?(opts[:attr])
        SCHOOLS_NOW_XMLFIELDS[@key][ opts[:attr] ]

      else
        SCHOOLS_NOW_XMLFIELDS[@key][:school]
      end

      puts "#{opts[:value_prefix]}#{value}#{opts[:value_suffix]}"
    end
  end

end

