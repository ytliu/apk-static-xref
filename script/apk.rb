class Apk

  require 'pp'
  HOME = File.dirname(__FILE__)
  attr_reader :out, :succ
  
  require "#{HOME}/dex"
  require "#{HOME}/manifest"

  def initialize(file_or_dir, *to_dir_or_file)
    @apk = file_or_dir
    @dir = "apk"
    if to_dir_or_file.length > 0
      @dir = to_dir_or_file[0]
    end
    @out = ""
    @succ = true
  end

  def dex
    @dir + "/classes.dex"
  end

  def xml
    @dir + "/AndroidManifest.xml"
  end

  def smali
    @dir + "/smali/"
  end

  TOOL = HOME + "/../tool"
  APKT = TOOL + "/apktool.jar"

  def unpack
    if @manifest == nil
      runcmd("java -jar #{APKT} d #{@apk} #{@dir}")
      if @succ
        @manifest = Manifest.new(xml)
      end
    end
    @succ
  end
  
  def logging()
    Dex.logging(dex, dex)
    @out << Dex.out
    @succ = Dex.succ
  end
  
  def services
    if @manifest != nil
      @manifest.service 
    end
  end

  JAR = TOOL + "/signapk.jar"
  PEM = TOOL + "/platform.x509.pem"
  PK8 = TOOL + "/platform.pk8"

  def repack(to_name = File.basename(@apk))
    unsigned = @dir + "/unsigned.apk"
    runcmd("java -jar #{APKT} b #{@dir} #{unsigned}")
    succ = @succ
    if succ
      unaligned = @dir + "/unaligned.apk"
      runcmd("java -jar #{JAR} #{PEM} #{PK8} #{unsigned} #{unaligned}")
      system("rm -f #{to_name}") # zipalign wants it not to exist
      runcmd("zipalign 4 #{unaligned} #{to_name}")
      File.delete(unaligned)
    end
    @succ = succ
  end
  
  def clean
    # if rewriting is successful, results folder will have dex and xml files
    system("rm -rf #{@dir}")
  end
  
  def launcher
    @manifest.launcher
  end
  
  def sdk
    @manifest.sdk
  end

private

  def runcmd(cmd)
    @out = "" if not @out
    @out << cmd + "\n"
    @out << `#{cmd} 2>&1`
    @succ = $?.exitstatus == 0
  end

end
