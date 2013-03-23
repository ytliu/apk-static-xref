class Manifest
  require 'nokogiri'
  require 'set'
  require 'pp'

  attr_reader :out, :pkg

  ROOT = "/manifest"
  APP  = ROOT + "/application"
  ACT  = "activity"
  ACTV = APP + "/" + ACT
  IFL  = "intent-filter"
  IFLT = ACTV + "/" + IFL
  ACN  = "action"
  ACTN = IFLT + "/" + ACN
  CTG  = "category"
  CATG = IFLT + "/" + CTG
  SVC = "service"
  SVCV = APP + "/" + SVC
  
  NAME = "name"
  PKG  = "package"
  ENABLED = "enabled"
  ANDNAME = "android:name"

  def initialize(file_name)
    f = File.open(file_name, 'r')
    @doc = Nokogiri::XML(f)
    f.close
    @pkg = @doc.xpath(ROOT)[0][PKG]
    @svc = Array.new
    services = @doc.xpath(SVCV)
    services.each do |service|
      svc = service[ANDNAME]
      @svc << (svc.start_with?('.') ? @pkg + svc : svc)
    end
    @out = ""

  end

  def service
    @svc
  end

  def launcher
    @out = ""
    main_acts = Set.new
    launchers = Set.new

    actions = @doc.xpath(ACTN)
    actions.each do |action|
      if action[NAME].split('.')[-1] == "MAIN"
        main_acts << action.parent.parent[NAME]
      end
    end

    categories = @doc.xpath(CATG)
    categories.each do |category|
      if category[NAME].split('.')[-1] == "LAUNCHER"
        launchers << category.parent.parent[NAME]
      end
    end

    inter = main_acts & launchers
    @out = self.class.class_name(@pkg, inter.to_a[0]) unless inter.empty?
  end

  def save_to(file_name)
    @out = ""
    f = File.open(file_name, 'w')
    @doc.write_xml_to(f)
    f.close
    @out << "saved to #{file_name}\n"
  end
  
  def sdk
    v = 3 # minSdkVersion
    sdks = @doc.xpath(ROOT + "/uses-sdk")
    sdks.each do |sdk|
      v = [v, sdk["targetSdkVersion"].to_i].max
    end
    @out = v
  end

private
  
  def self.class_name(pkg, act)
    part = act.split('.') # ".Main" or "Login"
    return act if part.length > 1 and part[0].length > 0
    return pkg + act if act.include? '.'
    return pkg + "." + act
  end
  
end
