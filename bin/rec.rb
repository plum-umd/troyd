#! /usr/bin/env ruby

## Copyright (c) 2011-2012,
##  Jinseong Jeon <jsjeon@cs.umd.edu>
##  Jeff Foster   <jfoster@cs.umd.edu>
## All rights reserved.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
## 1. Redistributions of source code must retain the above copyright notice,
## this list of conditions and the following disclaimer.
##
## 2. Redistributions in binary form must reproduce the above copyright notice,
## this list of conditions and the following disclaimer in the documentation
## and/or other materials provided with the distribution.
##
## 3. The names of the contributors may not be used to endorse or promote
## products derived from this software without specific prior written
## permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
## LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.

require 'rubygems'
require 'optparse'

REC = File.dirname(__FILE__)

require "#{REC}/avd"
require "#{REC}/troyd"
require "#{REC}/uid"
require "#{REC}/cmd"
include Commands

avd_name = "testAVD"
dev_name = ""
avd_opt = "" # e.g. "-no-window"
record = true
OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{__FILE__} target.apk [options]"
  opts.on("--avd avd", "your own Android Virtual Device") do |n|
    avd_name = n
  end
  opts.on("--dev serial", "serial of device that you uses") do |s|
    dev_name = s
  end
  opts.on("--opt opt", "avd options") do |o|
    avd_opt = o
  end
  opts.on("--no-rec", "do not record commands") do
    record = false
  end
  opts.on_tail("-h", "--help", "show this message") do
    puts opts
    exit
  end
end.parse!

if ARGV.length < 1
  puts "target file is not given"
  exit
end

apk = ARGV[0]

use_emulator = false
#ADB.restart
if not ADB.online?
  # start and synchronize with emulator
  avd = AVD.new(avd_name, avd_opt)
  if not avd.exists?
    avd.create
  end
  avd.start
  use_emulator = true
  sleep(6)
end

if dev_name != ""
  ADB.device dev_name
end

# rebuild and install troyd
pkg = AAPT.pkg apk
Troyd.setenv
Troyd.rebuild pkg

# resign and install target app
ADB.uninstall pkg
shareduid = pkg + ".shareduid.apk"
Uid.change_uid(apk, shareduid)
resigned = pkg + ".resigned.apk"
Resign.resign(shareduid, resigned)
system("rm -f #{shareduid}")
ADB.install resigned
APKS = REC + "/../apks"
system("mv #{resigned} #{APKS}/#{pkg}.apk")

# start troyd
act = AAPT.launcher apk
ADB.ignite act

SOFAR = "sofar"
pattern = /\(|\s|\)/

# interact with user
cmds = ["getViews", "getActivities", "back", "down", "up", "menu",
  "edit", "clear", "search", "checked", "click", "clickLong",
  "clickOn", "clickIdx", "clickImg", "clickItem", "drag"]
rec_cmds = []
while true
  print "> "
  stop = false
  $stdin.each_line do |line|
    rec_cmds << line if record
    cmd = line.split(pattern)[0]
    case cmd
    when "finish"
      stop = true
      out = eval line
      puts out if out
    when SOFAR       # end of one testcase
      ADB.ignite act # restart the target app
    else
      begin
        out = eval line if cmds.include? cmd
        puts out if out
      rescue SyntaxError => se
        puts "unknown command: #{line}"
        rec_cmds.pop if record
      end
    end
    break
  end
  break if stop
end

# stop emulator and clean up
ADB.uninstall #troyd
ADB.uninstall pkg
avd.stop if use_emulator

# and make testcase using recorded commands
code = ""
if record
  code += <<CODE
# auto-generated via bin/rec.rb
require 'test/unit'
require 'timeout'

class TroydTest < Test::Unit::TestCase

  SCRT = File.dirname(__FILE__) + "/../bin"
  require "\#{SCRT}/cmd"
  include Commands

  def assert_text(txt)
    found = search txt
    assert(found.include? "true")
  end

  def assert_not_text(txt)
    found = search txt
    assert(found.include? "false")
  end

  def assert_checked(txt)
    check = checked txt
    assert(check.include? "true")
  end

  def assert_died
    assert_raise(Timeout::Error) {
      Timeout.timeout(6) do
        getViews
      end
    }
  end

  def assert_ads
    found = false
    views = getViews
    views.each do |v|
      found = found || (v.include? "AdView")
    end
    assert(found)
  end

  def setup
    ADB.ignite "#{act}"
  end

CODE
  partial = []
  rec_cmds.each do |cmd|
    if cmd.include? SOFAR
      tname = cmd.split(pattern)[1]
      code += <<CODE
  def test_#{tname}
CODE
      partial.each do |cmdp|
      code += <<CODE
    #{cmdp.strip}
CODE
      end
      code += <<CODE
  end

CODE
      partial = []
    else
      partial << cmd
    end
  end
  code += <<CODE
  def teardown
    Timeout.timeout(6) do
      acts = getActivities
      finish
      puts acts
    end
  end

end
CODE

  tcs = REC + "/../testcases/"
  f = File.open(tcs+pkg+".rb",'w')
  f.puts code
  f.close
end
