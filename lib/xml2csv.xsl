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
       digitised (scanned) theses into a format suitable for loading
       into an Equella digital repository (http://www.equella.com/) via the
       Equella Bulk Importer (EBI). This is part of the following workflow:
       - Extract Alma MARCXML bib metadata via an export profile
       - split resulting files into one file per record
       - rename resulting files to include MMS ID
       - associate each scanned thesis (ie. attachment) with its metadata (via MMS ID)
       - modify metadata file to fix/clean various fields
       - merge attachment metadata into the metadata file
       - convert to a EBI-compatible CSV file via this XSLT file (using
         xsltproc)
       - load into an Equella thesis collection

       REFERENCES
       - Equella Bulk Importer: http://maestro.equella.com/items/eb737eb2-ac6f-4ba3-af17-321ee6c305a1/4/
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
  <xsl:param name="embargoed_str" select="''"/>

  <!-- Batch reference number; typically a timestamp -->
  <xsl:param name="batch_timestamp" select="'NO-REF'"/>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- Field delim for CSV EBI file -->
  <xsl:variable name="field_delim" select="','" />
  <!-- Quote fields so they may contain $field_delim -->
  <xsl:variable name="quote" select="'&quot;'" />
  <!-- This subfield generates multiple Equella fields -->
  <xsl:variable name="subfield_delim" select="'|'" />
  <!-- Alternative subfield for DC.Subject - does not generate multiple Equella fields -->
  <xsl:variable name="subfield_delim_alt" select="','" />
 
  <!-- An "array" containing the XML field-names (and their associated CSV header-names) -->
  <xsl:variable name="fieldArray">

    <field csv_header_name="fake.X.ref_no"                                >mms_id.fixed1</field>
    <field csv_header_name="item/curriculum/thesis/title"                 >245.fixed1</field>
    <field csv_header_name="item/curriculum/thesis/complete_year"         >publication_date.fixed1</field>
    <field csv_header_name="item/curriculum/thesis/@selected_type"        >502.type.fixed1</field>

    <field csv_header_name="item/curriculum/thesis/keywords/keyword"      >keywords.fixed1</field>
    <field csv_header_name="item/curriculum/thesis/subjects/subject"      >subjects.fixed1</field>
    <field csv_header_name="item/curriculum/thesis/language"              >language.fixed1</field>
    <field csv_header_name="item/curriculum/thesis/lib/scan_date"         >scan_date.fixed1</field>
    <field csv_header_name="item/curriculum/thesis/schools/primary"       >orig_school_seq.cleaned1</field>
<!--
    <field csv_header_name="item/curriculum/thesis/schools/current_schools/current_school/name"     >school.cleaned1</field>
    <field csv_header_name="item/curriculum/thesis/schools/current_schools/current_school/org_unit" >school_org_unit.cleaned1</field>
-->
  </xsl:variable>
  <xsl:variable name="fields" select="document('')/*/xsl:variable[@name='fieldArray']/*" />
 
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- TEMPLATE-BASED FUNCTIONS - can only return text or element-sequences -->
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_previous_identifier_url">
    <xsl:param name="is_csv_header" select="false()" />

    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/thesis/version/previous_identifier_url', $quote)" />
      </xsl:when>

      <!-- Metadata corresponding to the above CSV header -->
      <xsl:otherwise>
        <xsl:variable name="mms_id" select="/flat_marc_record/flat1/meta[@tagcode='mms_id.fixed1']" />
        <xsl:variable name="prev_id_url" select="concat('mmsid:', $mms_id)" />
        <xsl:value-of select="concat($field_delim, $quote, $prev_id_url, $quote)" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_student_name_id">
    <xsl:param name="is_csv_header" select="false()" />

    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/people/students/student/lastname_display', $quote)" />
        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/people/students/student/firstname_display', $quote)" />
        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/people/students/student/author_dates_FIXME', $quote)" />
      </xsl:when>

      <!-- Metadata corresponding to the above CSV header -->
      <xsl:otherwise>
        <xsl:variable name="surname" select="/flat_marc_record/flat1/meta[@tagcode='surname.fixed1']" />
        <xsl:variable name="given_names" select="/flat_marc_record/flat1/meta[@tagcode='given_names.fixed1']" />
        <xsl:variable name="author_dates" select="/flat_marc_record/flat1/meta[@tagcode='author_dates.fixed1']" />

        <xsl:value-of select="concat($field_delim, $quote, $surname, $quote)" />
        <xsl:value-of select="concat($field_delim, $quote, $given_names, $quote)" />
        <xsl:value-of select="concat($field_delim, $quote, $author_dates, $quote)" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_release_date">
    <xsl:param name="is_csv_header" select="false()" />

    <xsl:if test="$embargoed_str != 'false'">

    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/thesis/release/release_date', $quote)" />
      </xsl:when>

      <!-- Metadata corresponding to the above CSV header -->
      <xsl:otherwise>
        <xsl:variable name="release_date" select="/flat_marc_record/flat1/meta[@tagcode='release_date.fixed1']" />
        <xsl:value-of select="concat($field_delim, $quote, $release_date, $quote)" />
      </xsl:otherwise>
    </xsl:choose>

    </xsl:if>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_constant_fields">
    <xsl:param name="is_csv_header" select="false()" />


    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/thesis/version/thesis_version', $quote)" />
<!--
        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/thesis/lib/note', $quote)" />
-->

        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/thesis/release/status', $quote)" />
        <xsl:if test="$embargoed_str != 'false'">
          <!-- Only add this column for embargoed theses. Hence all embargoed
               theses in one CSV file and all non-embargoed theses in another.
          -->
          <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/thesis/agreements/embargo', $quote)" />
        </xsl:if>
      </xsl:when>

      <!-- Metadata corresponding to the above CSV header -->
      <xsl:otherwise>
        <xsl:value-of select="concat($field_delim, $quote, 'Batch prepared ', $batch_timestamp, '; lib import version', $quote)" />
<!--
        <xsl:value-of select="concat($field_delim, $quote, 'Future use. Eg. For overseas scholarship holder', $quote)" />
-->
        <xsl:choose>
          <xsl:when test="$embargoed_str != 'false'">
            <!-- Field: item/curriculum/thesis/release/status -->
            <xsl:value-of select="concat($field_delim, $quote, 'Restricted Access', $quote)" />
            <!-- Field: item/curriculum/thesis/agreements/embargo -->
            <xsl:value-of select="concat($field_delim, $quote, 'Yes', $quote)" />
          </xsl:when>

          <xsl:otherwise>
            <!-- Field: item/curriculum/thesis/release/status -->
            <xsl:value-of select="concat($field_delim, $quote, 'Open Access', $quote)" />
          </xsl:otherwise>
        </xsl:choose>

      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_attachment_info">
    <xsl:param name="is_csv_header" select="false()" />

    <xsl:choose>
      <xsl:when test="$is_csv_header">
        <!-- No abstract file at XPath 'item/curriculum/thesis/version/abstract/uuid' -->
        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/thesis/version/open_access/required', $quote)" />
        <xsl:value-of select="concat($field_delim, $quote, 'item/curriculum/thesis/version/examined_thesis/files/uuid', $quote)" />
      </xsl:when>

      <!-- Metadata corresponding to the above CSV header -->
      <xsl:otherwise>
        <xsl:variable name="open_access_req" select="'version of record'" />
        <xsl:variable name="thesis_files">

          <!-- Permit repeated fields -->
          <xsl:for-each select="/flat_marc_record/flat1/meta[@tagcode='attachment.fixed1']">
            <xsl:if test="position() != 1">
              <xsl:value-of select="$subfield_delim"/>
            </xsl:if>
            <xsl:value-of select="." />
          </xsl:for-each>

        </xsl:variable>

        <xsl:value-of select="concat($field_delim, $quote, $open_access_req, $quote)" />
        <xsl:value-of select="concat($field_delim, $quote, $thesis_files, $quote)" />

      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template name="do_processed_info">
    <xsl:param name="is_csv_header" select="false()" />

    <xsl:call-template name="do_student_name_id">
      <xsl:with-param name="is_csv_header" select="$is_csv_header" />
    </xsl:call-template>

    <xsl:call-template name="do_previous_identifier_url">
      <xsl:with-param name="is_csv_header" select="$is_csv_header" />
    </xsl:call-template>

    <xsl:call-template name="do_attachment_info">
      <xsl:with-param name="is_csv_header" select="$is_csv_header" />
    </xsl:call-template>

    <xsl:call-template name="do_constant_fields">
      <xsl:with-param name="is_csv_header" select="$is_csv_header" />
    </xsl:call-template>

    <xsl:call-template name="do_release_date">
      <xsl:with-param name="is_csv_header" select="$is_csv_header" />
    </xsl:call-template>

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
      <xsl:call-template name="do_processed_info">
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
    <xsl:call-template name="do_processed_info">
      <xsl:with-param name="is_csv_header" select="false()" />
    </xsl:call-template>

    <!-- Output newline -->
    <xsl:text>&#xa;</xsl:text>
  </xsl:template>
</xsl:stylesheet>

