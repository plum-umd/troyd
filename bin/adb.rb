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

module ADB
  require 'timeout'

  ADBS = File.dirname(__FILE__)
  require "#{ADBS}/aapt"

  def ADB.restart
    system("adb kill-server")
    system("adb start-server")
  end

  @@acmd = "adb"

  @@lcat = @@acmd + " logcat"
  ACTM = "ActivityManager"
  @@altr = @@lcat + " -d #{ACTM}:D *:S"
  PKG = "umd.troyd"
  @@fltr = @@lcat + " -d #{PKG}:D *:S"

  RUN = " broadcast -a android.intent.action.RUN"
  @@am = @@acmd + " shell am"
  @@run = @@am + RUN

  # Set the specific device to use
  def ADB.device(serial)
    @@acmd = "adb -s #{serial}"
    @@lcat = @@acmd + " logcat"
    @@altr = @@lcat + " -d #{ACTM}:D *:S"
    @@fltr = @@lcat + " -d #{PKG}:D *:S"
    @@am = @@acmd + " shell am"
    @@run = @@am + RUN
  end

  TO = 2

  # Get the list of active devices
  #
  # @return [Array<Array<String>>] two tuple of devices, emulators,
  # containing the name of the devices as identified by ADB
  def ADB.devices_list
    dvs = []
    ems = []
    `adb devices`.each_line do |line|
      dvs << line.split[0] if line =~ /.+device$/
      ems << line.split[0] if line =~ /emulator-\d+\s+device$/
    end
    return dvs, ems
  end

  # Get the number of active devices / emulators
  #
  # @return [Array<Array<Fixnum>>] number of devices, emulators
  def ADB.devices_cnt
    ADB.devices_list.map { |x| x.length }
  end

  # Check there are any available devices or emulators
  def ADB.online?
    dv_cnt, em_cnt = ADB.devices_cnt
    return false if dv_cnt == 0
    if em_cnt > 0 
      begin
        Timeout.timeout(TO) do
          sync_logcat("", @@altr) != ""
        end
      rescue Timeout::Error
        false
      end
    else # means, real device!
      true
    end
  end

  SUCC = "Success"
  FAIL = "Failure"

  # Uninstall a package
  # @param pkg [String] The package name, as identified by Android
  def ADB.uninstall(pkg=PKG)
    sync_msg("#{@@acmd} uninstall #{pkg}", [SUCC, FAIL])
  end

  # Install an APK
  # @param apk [String] Path to the APK
  def ADB.install(apk)
    sync_msg("#{@@acmd} install #{apk}", [SUCC])
  end

  # Install all APKs in a directory
  # @param dir [String] The directory from which to pull the APKs
  # @param cond [String] String to filter APKs by string inclusion.
  def ADB.instAll(dir, cond)
    Dir.glob(dir + "/*.apk").each do |file|
      if file.downcase.include? cond
        ADB.uninstall(AAPT.pkg file)
        ADB.install file
      end
    end
  end

  # Start a service on the given package
  def ADB.ignite(act)
    sync_logcat("#{@@am} startservice -n #{PKG}/.Ignite -e AUT #{act}", @@fltr)
  end

  # Execute some command on the given APK
  def ADB.cmd(cmd, opts)
    ext = ""
    opts.each do |k, v|
      ext << " -e #{k} \"#{v}\""
    end
    sync_logcat("#{@@run} -e cmd #{cmd}#{ext}", @@fltr)
  end

private

  def ADB.sync_logcat(cmd, filter)
    out = ""
    system("#{@@lcat} -c")
    ADB.runcmd(cmd)
    while out == "" do
      sleep(TO)
      out = `#{filter}`
      sanitized = ""
      out.each_line do |line|
        sanitized += line if line.include? PKG
      end # device log is different
      out = sanitized
    end
    out
  end

  def ADB.sync_msg(cmd, msgs)
    out = ""
    while out == "" do
      out = ADB.runcmd(cmd)
      msgs.each do |msg|
        return msg if out.include? msg
      end
      out = ""
      sleep(TO)
    end
  end

  def ADB.runcmd(cmd)
    if cmd != nil and cmd != ""
      # puts "shell$ #{cmd}" # to debug
      `#{cmd}`
    end
  end
end
