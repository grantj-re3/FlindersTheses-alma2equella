<?xml version="1.0" encoding="utf-8"?>
<!--
     Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
     Contributors: Library, Corporate Services, Flinders University.
     See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).

     PURPOSE
     To tranform Alma MARC-XML to a fairly flat XML structure to make it
     easier to extract information based on MARC field (FFF) and subfield (S)
     in the format FFF.S (eg. 245.a).

     XPath structure of input XML document is:
     - /record
     - /record/leader
     - /record/controlfield
     - /record/datafield
     - /record/datafield/subfield	(these are the most interesting!)
-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" version="1.0" indent="yes" />
  <xsl:strip-space elements="*" />

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- TEMPLATES -->
  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->

  <!-- Root template -->
  <xsl:template match="/">
    <xsl:apply-templates select="record" />
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- The root element which contains all other elements -->
  <xsl:template match="record">
    <flat_marc_record>
      <original>
        <xsl:copy-of select="*" />
      </original>

      <flat1>
        <xsl:apply-templates select="*" />
      </flat1>
    </flat_marc_record>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- One level below root element. The output XML doc has these as self-closing tags. -->
  <xsl:template match="controlfield|leader">
    <xsl:variable name="this_id" select="generate-id(.)" />
    <xsl:variable name="tagcode">
      <xsl:choose>
        <xsl:when test="name() = 'leader'">leader</xsl:when>
        <xsl:otherwise> <xsl:value-of select="concat('control.', @tag)" /> </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    
    <xsl:element name="meta">
      <!-- Add attribute to the element -->
      <xsl:attribute name="tagcode">
        <xsl:value-of select="$tagcode" />
      </xsl:attribute>

      <!-- Iterate through all attributes of element -->
      <xsl:for-each select="@*" >
        <xsl:attribute name="{name()}">
          <xsl:value-of select="." />
        </xsl:attribute>
      </xsl:for-each>

      <!-- Add an id attribute to the element -->
      <xsl:attribute name="id">
        <xsl:value-of select="$this_id" />
      </xsl:attribute>

      <!-- Show text of this element (if it contains text) -->
      <xsl:value-of select="text()" />
    </xsl:element>
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <xsl:template match="datafield">
    <!-- Process any child elements. Eg. for "datafield/subfield" -->
    <xsl:apply-templates select="*" />
  </xsl:template>

  <!-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% -->
  <!-- Two levels below root element, but one level below root of output XML doc. -->
  <!-- /record/datafield/subfield -->
  <xsl:template match="subfield">
    <xsl:variable name="this_id" select="generate-id(.)" />
    <xsl:variable name="tagcode" select="concat(../@tag, '.', @code)" />

    <xsl:element name="meta">
      <!-- Add attribute to the element -->
      <xsl:attribute name="tagcode">
        <xsl:value-of select="$tagcode" />
      </xsl:attribute>

      <!-- Iterate through all attributes of element -->
      <xsl:for-each select="@*" >
        <xsl:attribute name="{name()}">
          <xsl:value-of select="." />
        </xsl:attribute>
      </xsl:for-each>

      <!-- Add attribute to the element; parent id -->
      <xsl:attribute name="pid">
        <xsl:value-of select="generate-id(..)" />
      </xsl:attribute>

      <!-- Iterate through all attributes of parent element -->
      <xsl:for-each select="../@*" >
        <xsl:attribute name="{name()}">
          <xsl:value-of select="." />
        </xsl:attribute>
      </xsl:for-each>

      <!-- Add attribute to the element -->
      <xsl:attribute name="id">
        <xsl:value-of select="$this_id" />
      </xsl:attribute>

      <xsl:value-of select="text()" />
    </xsl:element>
  </xsl:template>

</xsl:stylesheet>

