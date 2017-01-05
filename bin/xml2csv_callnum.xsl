<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <!--
       Derived from the sample "Converting XML to CSV using XSLT 1.0" at
       http://fahdshariff.blogspot.com.au/2014/07/converting-xml-to-csv-using-xslt-10.html
       by Fahd Shariff under GNU GENERAL PUBLIC LICENSE Version 3.

       Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
       Contributors: Library, Corporate Services, Flinders University.
       See the accompanying gpl-3.0.txt file (or http://www.gnu.org/licenses/gpl-3.0.html).

       PURPOSE
       This XSLT transforms *modified* Alma MARCXML bib metadata of
       digitised (scanned) theses into corresponding call numbers and
       other useful info for collection maintenance.

       REFERENCES
       - Exporting MARC XML bibliographic records in Alma.  See "Publishing and Inventory Enrichment" at
         https://knowledge.exlibrisgroup.com/Alma/Product_Documentation/Alma_Online_Help_%28English%29/Integrations_with_External_Systems/030Resource_Management/080Publishing_and_Inventory_Enrichment
  -->
  <xsl:output method="text" />
 
  <!--
       %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
       We can pass these parameters into this XSLT script from the command
       line using the xsltproc "param" or "stringparam" option. Eg.
         xsltproc \-\-param add_csv_header "true()"  \-\-stringparam embargoed_str false ...
         xsltproc \-\-param add_csv_header "false()" \-\-stringparam embargoed_str true ...
  -->
  <!-- true()=First line will be a CSV header; false()=First line will be data -->
  <xsl:param name="add_csv_header" select="true()" />
  <!-- true()=Use @csv_header_name for CSV header; false()=Use value (eg. DC.Title)-->
  <xsl:param name="use_array_csv_header_name" select="true()" />
  <!-- Other scripts compare embargoed_str with 'false'. Do the same below. -->
<!--
  <xsl:param name="embargoed_str" select="''"/>
-->

  <!-- Batch reference number; typically a timestamp -->
  <xsl:param name="batch_timestamp" select="'NO-REF'"/>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- Field delim for CSV EBI file -->
  <xsl:variable name="field_delim" select="','" />
  <!-- Quote fields so they may contain $field_delim -->
  <xsl:variable name="quote" select="'&quot;'" />
  <!-- This subfield generates multiple Equella fields -->
  <xsl:variable name="subfield_delim" select="'|'" />
 
  <!-- An "array" containing the XML field-names (and their associated CSV header-names) -->
  <xsl:variable name="fieldArray">

    <!-- These fields were requested for resource management -->
    <field csv_header_name="rpt1.call_num"	>call_number.fixed1</field>
    <field csv_header_name="rpt1.mms_id"	>mms_id.fixed1</field>
    <field csv_header_name="rpt1.full_name"	>full_name_display.fixed1</field>

    <!-- These fields were not requested, but might be handy & are easy to extract -->
    <field csv_header_name="rpt1.complete_year"	>publication_date.fixed1</field>
    <field csv_header_name="rpt1.type"		>502.type.fixed1</field>
    <field csv_header_name="rpt1.scan_date"	>scan_date.fixed1</field>
    <field csv_header_name="rpt1.title"		>245.fixed1</field>

  </xsl:variable>
  <xsl:variable name="fields" select="document('')/*/xsl:variable[@name='fieldArray']/*" />
 
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- TEMPLATE-BASED FUNCTIONS - can only return text or element-sequences -->
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_constant_fields">
    <xsl:param name="is_csv_header" select="false()" />


    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <xsl:value-of select="concat($field_delim, $quote, 'rpt1.batch_prep_time', $quote)" />
      </xsl:when>

      <!-- Metadata corresponding to the above CSV header -->
      <xsl:otherwise>
        <xsl:value-of select="concat($field_delim, $quote, 'Batch prepared ', $batch_timestamp, $quote)" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- TEMPLATES -->
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->

  <!-- Root template -->
  <xsl:template match="/">
 
    <!-- Output the CSV header row -->
    <xsl:if test="$add_csv_header = true()">

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
 
      <!-- Output processed fields -->
      <xsl:call-template name="do_constant_fields">
        <xsl:with-param name="is_csv_header" select="true()" />
      </xsl:call-template>

      <!-- Output newline -->
      <xsl:text>&#xa;</xsl:text>
    </xsl:if>
 
    <!-- Output the CSV data rows -->
    <xsl:apply-templates select="flat_marc_record/flat1"/>
  </xsl:template>
 
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template match="flat1">
    <xsl:variable name="currNode" select="." />
 
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
 
    <!-- Output processed fields -->
    <xsl:call-template name="do_constant_fields">
      <xsl:with-param name="is_csv_header" select="false()" />
    </xsl:call-template>

    <!-- Output newline -->
    <xsl:text>&#xa;</xsl:text>
  </xsl:template>
</xsl:stylesheet>

