<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <!--
       Derived from the sample "Converting XML to CSV using XSLT 1.0" at
       http://fahdshariff.blogspot.com.au/2014/07/converting-xml-to-csv-using-xslt-10.html
       by Fahd Shariff under GNU GENERAL PUBLIC LICENSE Version 3.

       Copyright (c) 2021, Flinders University, South Australia. All rights reserved.
       Contributors: Library, Corporate Services, Flinders University.
       See the accompanying gpl-3.0.txt file (or http://www.gnu.org/licenses/gpl-3.0.html).

       PURPOSE
       This XSLT transforms *modified* Alma MARCXML bib metadata of a
       digitised (scanned) thesis into a corresponding *new* filename.
       - It writes MMS ID, new filename and other useful info to STDOUT
         in CSV format.
       - It processes a single bib record.

       REFERENCES
       - Exporting MARC XML bibliographic records in Alma.  See "Publishing and Inventory Enrichment" at
         https://knowledge.exlibrisgroup.com/Alma/Product_Documentation/Alma_Online_Help_%28English%29/Integrations_with_External_Systems/030Resource_Management/080Publishing_and_Inventory_Enrichment
  -->
  <xsl:output method="text" />
  <xsl:strip-space elements="*" />
 
  <!--
       %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
       We can pass these parameters into this XSLT script from the command
       line using the xsltproc "param" or "stringparam" option. Eg.
         xsltproc \-\-param add_csv_header "true()"  \-\-stringparam embargoed_str false ...
         xsltproc \-\-param add_csv_header "false()" \-\-stringparam embargoed_str true ...
  -->
  <!-- true()=First line will be a CSV header; false()=First line will be data -->
  <xsl:param name="add_csv_header" select="true()" />
  <!-- true()=Use @csv_header_name for CSV header; false()=Use element value -->
  <xsl:param name="use_array_csv_header_name" select="true()" />

  <!-- Used via translate() to convert to upper or lower case -->
  <xsl:variable name="lower_case" select="'abcdefghijklmnopqrstuvwxyz'" />
  <xsl:variable name="upper_case" select="'ABCDEFGHIJKLMNOPQRSTUVWXYZ'" />

  <!-- Later we will strip out any chars which are not listed below -->
  <xsl:variable name="legal_filename_chars" select="'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._'" />

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- Field delim for CSV EBI file -->
  <xsl:variable name="field_delim" select="','" />
  <!-- Quote fields so they may contain $field_delim -->
  <xsl:variable name="quote" select="'&quot;'" />
  <!-- This subfield generates multiple Equella fields -->
  <xsl:variable name="subfield_delim" select="'|'" />
 
  <!-- An "array" containing the XML field-names (and their associated CSV header-names) -->
  <xsl:variable name="fieldArray">

    <field csv_header_name="surname"		>surname.fixed1</field>
    <field csv_header_name="complete_year"	>publication_date.fixed1</field>
    <field csv_header_name="type"		>502.type.fixed1</field>

    <field csv_header_name="given_names"	>given_names.fixed1</field>
    <field csv_header_name="full_name"		>full_name_display.fixed1</field>
    <field csv_header_name="title"		>245.fixed1</field>

  </xsl:variable>
  <xsl:variable name="fields" select="document('')/*/xsl:variable[@name='fieldArray']/*" />
 
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- TEMPLATE-BASED FUNCTIONS - can only return text or element-sequences -->
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_cooked_fields">
    <xsl:param name="currNode" />
    <xsl:param name="is_csv_header" />


    <xsl:call-template name="do_mmsid_field">
      <xsl:with-param name="currNode" select="$currNode" />
      <xsl:with-param name="is_csv_header" select="$is_csv_header" />
    </xsl:call-template>

    <xsl:call-template name="do_filename_field">
      <xsl:with-param name="currNode" select="$currNode" />
      <xsl:with-param name="is_csv_header" select="$is_csv_header" />
    </xsl:call-template>

    <xsl:call-template name="do_filename_error_field">
      <xsl:with-param name="currNode" select="$currNode" />
      <xsl:with-param name="is_csv_header" select="$is_csv_header" />
    </xsl:call-template>

    <xsl:call-template name="do_type_warning_field">
      <xsl:with-param name="currNode" select="$currNode" />
      <xsl:with-param name="is_csv_header" select="$is_csv_header" />
    </xsl:call-template>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_mmsid_field">
    <xsl:param name="currNode" />
    <xsl:param name="is_csv_header" />


    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <xsl:value-of select="concat($quote, 'mms_id', $quote, $field_delim)" />
      </xsl:when>

      <xsl:otherwise>
        <xsl:value-of select="concat($quote, $currNode/meta[@tagcode = 'mms_id.fixed1'], $quote, $field_delim)" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_filename_field">
    <xsl:param name="currNode" />
    <xsl:param name="is_csv_header" />


    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <xsl:value-of select="concat($quote, 'newfilename', $quote, $field_delim)" />
      </xsl:when>

      <!-- Metadata corresponding to the above CSV header -->
      <!-- FIXME: Assumes fields used below are not repeated. -->
      <xsl:otherwise>
        <xsl:variable name="newfilename_raw" select="translate(
          concat(
            'thesis-',
            $currNode/meta[@tagcode = 'surname.fixed1'], '-',
            $currNode/meta[@tagcode = 'publication_date.fixed1'], '-ref',
            $currNode/meta[@tagcode = 'mms_id.fixed1'], '-0.pdf'
          ),
          $upper_case, $lower_case)" />

        <xsl:variable name="newfilename_clean" select="translate($newfilename_raw, translate($newfilename_raw, $legal_filename_chars, ''), '')"/>
        <xsl:value-of select="concat($quote, $newfilename_clean, $quote, $field_delim)" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_filename_error_field">
    <xsl:param name="currNode" />
    <xsl:param name="is_csv_header" />


    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <xsl:value-of select="concat($quote, 'error', $quote, $field_delim)" />
      </xsl:when>

      <!-- Metadata corresponding to the above CSV header -->
      <!-- FIXME: Assumes fields used below are not repeated. -->
      <xsl:otherwise>

        <xsl:variable name="surname" select="$currNode/meta[@tagcode = 'surname.fixed1']" />
        <xsl:variable name="err_surname">
          <xsl:choose>
            <xsl:when test="not($surname) or ($surname = '')">Surname is empty. </xsl:when>

            <xsl:otherwise />
          </xsl:choose>
        </xsl:variable>

        <xsl:variable name="date_lower" select="translate($currNode/meta[@tagcode = 'publication_date.fixed1'], $upper_case, $lower_case)" />
        <xsl:variable name="err_date">
          <xsl:choose>
            <xsl:when test="not($date_lower) or ($date_lower = '') or contains($date_lower, 'unknown')">Publication date is empty or invalid. </xsl:when>

            <xsl:otherwise />
          </xsl:choose>
        </xsl:variable>

        <xsl:variable name="mms_id_lower" select="translate($currNode/meta[@tagcode = 'mms_id.fixed1'], $upper_case, $lower_case)" />
        <xsl:variable name="err_mms_id">
          <xsl:choose>
            <xsl:when test="not($mms_id_lower) or ($mms_id_lower = '') or contains($mms_id_lower, 'unknown')" >MMS ID is empty or invalid. </xsl:when>
            <xsl:when test="translate($mms_id_lower, '0123456789', '') != ''">MMS ID is not an integer. </xsl:when>
            <xsl:when test="not(starts-with($mms_id_lower, '99'))">MMS ID does not start with '99'. </xsl:when>
            <xsl:when test="string-length($mms_id_lower) &lt;  8" >MMS ID is less than 8 digits. </xsl:when>
            <xsl:when test="string-length($mms_id_lower) &gt; 19" >MMS ID is greater than 19 digits. </xsl:when>

            <xsl:otherwise />
          </xsl:choose>
        </xsl:variable>

        <xsl:value-of select="concat($quote, $err_surname, $err_date, $err_mms_id, $quote, $field_delim)" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_type_warning_field">
    <xsl:param name="currNode" />
    <xsl:param name="is_csv_header" />


    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <xsl:value-of select="concat($quote, 'type_warning', $quote, $field_delim)" />
      </xsl:when>

      <!-- Metadata corresponding to the above CSV header -->
      <!-- FIXME: Assumes fields used below are not repeated. -->
      <xsl:otherwise>

        <xsl:variable name="type_lower" select="translate($currNode/meta[@tagcode = '502.type.fixed1'], $upper_case, $lower_case)" />
        <xsl:variable name="err_type">
          <xsl:choose>
            <xsl:when test="contains($type_lower, 'masters')">Thesis-type (502) is not PhD. </xsl:when>
            <xsl:when test="contains($type_lower, 'honours')">Thesis-type (502) is not PhD. </xsl:when>
            <xsl:when test="not($type_lower) or ($type_lower = '') or contains($type_lower, 'unknown')">Thesis-type (502) is empty or invalid. </xsl:when>
            <xsl:when test="not($type_lower = 'doctor of philosophy')">Thesis-type (502) is not PhD. </xsl:when>

            <xsl:otherwise />
          </xsl:choose>
        </xsl:variable>

        <xsl:value-of select="concat($quote, $err_type, $quote, $field_delim)" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- TEMPLATES -->
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->

  <!-- Root template -->
  <xsl:template match="/">
 
    <!-- Output the CSV header row -->
    <xsl:if test="$add_csv_header">

      <!-- Output cooked fields -->
      <xsl:call-template name="do_cooked_fields">
        <xsl:with-param name="currNode" select="." />
        <xsl:with-param name="is_csv_header" select="true()" />
      </xsl:call-template>

      <!-- Output the array fields -->
      <xsl:for-each select="$fields">
        <xsl:if test="position() != 1">
          <xsl:value-of select="$field_delim"/>
        </xsl:if>

        <xsl:choose>
          <xsl:when test="$use_array_csv_header_name"> <xsl:value-of select="concat($quote, @csv_header_name, $quote)" /> </xsl:when>
          <xsl:otherwise> <xsl:value-of select="concat($quote, ., $quote)" /> </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
 
      <!-- Output newline -->
      <xsl:text>&#xa;</xsl:text>
    </xsl:if>
 
    <!-- Output the CSV data rows -->
    <xsl:apply-templates select="flat_marc_record/flat1"/>
  </xsl:template>
 
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template match="flat1">
    <xsl:variable name="currNode" select="." />
 
    <!-- Output cooked fields -->
    <xsl:call-template name="do_cooked_fields">
      <xsl:with-param name="currNode" select="$currNode" />
      <xsl:with-param name="is_csv_header" select="false()" />
    </xsl:call-template>

    <!-- Output the array fields -->
    <!-- Loop over the field names and find the value of each one in the xml -->
    <xsl:for-each select="$fields">
      <xsl:if test="position() != 1">
        <xsl:value-of select="$field_delim"/>
      </xsl:if>
      <xsl:value-of select="$quote"/>

      <!-- Permit repeated fields; separate with a subfield delimiter -->
      <xsl:variable name="currName" select="current()" />
      <xsl:for-each select="$currNode/meta[@tagcode = current()]">

        <xsl:if test="position() != 1">
          <xsl:value-of select="$subfield_delim"/>
        </xsl:if>

        <xsl:value-of select="." />
      </xsl:for-each>

      <xsl:value-of select="$quote"/>
    </xsl:for-each>
 
    <!-- Output newline -->
    <xsl:text>&#xa;</xsl:text>
  </xsl:template>
</xsl:stylesheet>

