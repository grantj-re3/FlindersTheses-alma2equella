#!/usr/bin/ruby
#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# Convert ruby constants in the CommonConfig module into sh/bash
# shell environment variable assignments.
##############################################################################
# Add dirs to the library path
$: << File.expand_path("../etc", File.dirname(__FILE__))
require "common_config"

##############################################################################
class ShellVarMaker
  include CommonConfig

  DEBUG = false
  NUM_LINES_PER_GROUP = 4

  ############################################################################
  def self.show_shell_var_assignments
    puts "# This file was automatically created by #{File.basename(__FILE__)}"
    puts "# Creation timestamp: #{Time.now.strftime('%a %Y-%m-%d %H:%M:%S %z')}"

    line_count = 0
    CommonConfig.constants.sort.each do |const|
      line_count += 1
      puts if line_count % NUM_LINES_PER_GROUP == 1

      value = CommonConfig.const_get(const)
      STDERR.puts "## #{const}|#{value.class}|#{value.inspect}" if DEBUG
      puts "#{const}=#{value.inspect}" if [String, Fixnum].include?(value.class)
    end
  end
end

##############################################################################
# Main
##############################################################################
ShellVarMaker.show_shell_var_assignments

