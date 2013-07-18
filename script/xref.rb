require 'optparse'
require 'pathname'
require 'pp'
#require 'graphviz'

THIS_FILE = Pathname.new(__FILE__).realpath.to_s
HERE = File.dirname(THIS_FILE)

require "#{HERE}/apk"
require "#{HERE}/smali"

cmds = [
	"info", "xref"
]

cpts = [
  "service", "activity"
]

cmd = ""
cpt = ""
cls = nil
mtd = nil
pty = nil
to = "_xref_cong"

apk = nil
dex = nil
manifest = nil
assign = false
#graph_need = false
$verbose = false

$caller_methods = Array.new
$calling_edge = Hash.new
# Create a new graph
#$graph = GraphViz.new( :G, :type => :digraph )

$libapis = Hash.new

$fields = Hash.new

def close(apk)
  apk.clean if apk
end

#def addNodes(n1, n2)
#  node1 = $graph.add_nodes(n1)
#  node2 = $graph.add_nodes(n2)
#  $graph.add_edges(node1, node2)
#end

def parseInvokeInit(line)
  

end
def run_assign(apk, cls, mtd, pty, flag, ori_cls)
  match = 0
  initfld = 0
  caller = nil
  callee = nil
  vclass = nil
  #if (cls.split('/')[-1] =~ /.*[A-Z].*/)
  filename = apk.smali + cls + ".smali" # it is for mac OS
  #else
  #  filename = apk.smali + cls + ".2.smali"
  #end
  #filename = apk.smali + cls + ".2.smali" # it is for mac OS
  if File.file?(filename)
    fh = File.open(filename, "r")
  else
    if !$libapis[ori_cls].include?("#{cls}->#{mtd}#{pty}")
      $libapis[ori_cls] << "#{cls}->#{mtd}#{pty}"
    end
    return
  end
  lines = fh.readlines
  get_method = false
  vbind = Hash.new
  lines.each { |line|
    line = line[0...-1]
    # assign specific file location to field like Thread, handler...
    if initfld == 1
      if line.start_with?(".end method")
        initfld = 0
      elsif line =~ /\s*new-instance.*/
        if vbind[line.split()[1]] == nil
          vbind[line.split()[1]] = Array.new
        end
		    vbind[line.split()[1]][0] = line.split()[2][1..-2]
	    elsif line =~ /\s*invoke-direct.*<init>.*/
        vars = line.split('{')[1].split('}')[0].split(',')
        pnum = vars.size - 1
      elsif line =~ /\s*iput-object.*/
        clas = line.split()[3].split('->')[0][1..-2]
        field = line.split()[3].split('->')[1].split(':')[0]
        if $fields[clas] == nil
          pp "#{cls}, #{line}, #{clas}, #{field}"
          $fields[clas] = Hash.new
        end
		    #pp "#{cls}, #{line}, #{clas}, #{field}"
        if $fields[clas][field] != nil
          $fields[clas][field] = file if file != nil
          #pp "#{clas}.#{field} <- #{$fields[clas][field]}"
        end
        file = nil
      end
    elsif line.start_with?(".class")
      vclass = line.split()[-1][1...-1]
      if $fields[vclass] == nil
        $fields[vclass] = Hash.new
      else
        initfld = -1
      end
    elsif line.start_with?(".field")
      field = line.split()[-1].split(':')
      if initfld != -1
        if field.size > 1
          if field[1].include?("Ljava/lang/Thread")
            $fields[vclass][field[0]] = "thread"
          elsif field[1].include?("Landroid/os/Handler")
            $fields[vclass][field[0]] = "handler"
          elsif field[1].include?("Landroid/content/ServiceConnection")
            $fields[vclass][field[0]] = "serviceConnection"
          elsif field[1].start_with?('L')
            $fields[vclass][field[0]] = field[1][1..-2]
          end
        end
      end
    elsif line.start_with?(".method")
      if line.split()[-1].start_with?("<init>")
        get_method = true
        initfld = 1 if initfld == 0
      else
        caller = Invoker.new(vclass, line)
        if (mtd.eql?("doInBackground")) and caller.mtd.eql?(mtd)
          match = 1
          get_method = true
        end
        if (caller.mtd.eql?(mtd)) and (caller.pty.eql?(pty))
          match = 1
          get_method = true
        end
      end
    elsif line.start_with?(".end method")
      match = 0
    elsif line =~ /\s*iget-object.*/
      if (match == 1) or (flag == 1)
        clas = line.split()[3].split('->')[0][1..-2]
        field = line.split()[3].split('->')[1].split(':')[0]
        if $fields[clas] == nil
          $fields[clas] = Hash.new
        end
        file = $fields[clas][field]
      end
    elsif line =~ /\s*new-instance.*/
      if (match == 1) or (flag == 1)
        file = line.split()[-1][1..-2]
      end
    elsif line.include?("invoke-")
      if (match == 1) or (flag == 1)
        callee = Invoked.new(line)
        if (callee.str.eql?("java/lang/Thread->start()V"))
          callee.cls = file
          callee.mtd = "run"
          callee.pty = "()V"
        elsif (callee.str.eql?("android/os/Handler->sendMessage(Landroid/os/Message;)Z"))
          callee.cls = file
          callee.mtd = "handleMessage"
          callee.pty = "(Landroid/os/Message;)V"
        elsif (callee.str.eql?("android/os/Handler->sendEmptyMessage(I)Z"))
          callee.cls = file
          callee.mtd = "handleMessage"
          callee.pty = "(Landroid/os/Message;)V"
        elsif (callee.str =~ /.*->execute\(\[Ljava\/lang\/Object;\)Landroid\/os\/AsyncTask;/)
          callee.mtd = "doInBackground"
          callee.pty = ""
        elsif (callee.str =~ /.*->execute\(Ljava\/lang\/Runnable;\)V/)
          callee.cls = file
          callee.mtd = "run"
          callee.pty = "()V"
        elsif (callee.str =~ /.*->start\(\)V/)
          callee.mtd = "run"
          callee.pty = "()V"
        end
        #pp "#{caller.str} : #{callee.str}"
        if $calling_edge[caller.str] == nil
          $calling_edge[caller.str] = Array.new
        end
        if !$calling_edge[caller.str].include?(callee.str)
          $calling_edge[caller.str] << callee.str
        end
#        addNodes(caller.str, callee.str) if $graph_need
        if $verbose
          #pp "#{caller.str} : #{callee.str}"
        end
        if !$caller_methods.include?(callee.str)
          $caller_methods << caller.str
          run_assign(apk, callee.cls, callee.mtd, callee.pty, 0, ori_cls)
        end
      end
    end
  }
  if not get_method
    if !$libapis[ori_cls].include?("#{cls}->#{mtd}#{pty}")
      $libapis[ori_cls] << "#{cls}->#{mtd}#{pty}"
    end
  end
end

def get_method_name(line)
  line.split(' ')[-1].split('(')[0]
end

def get_proto(line)
  "(#{line.split(' ')[-1].split('(')[-1]}"
end

def run_all(apk, cpt)
  pp "run_all"
  if cpt.eql?("service")
    components = apk.services
    p components
  elsif cpt.eql?("activity")
    components = apk.activities
  else
    components = apk.services
    components.concat(apk.activities)
  end
  if components.size == 0
    pp "no components in #{ARGV[0]}"
    close(apk) 
    exit
  end
  components.values.each { |component|
    if $verbose
      pp "====== process components - #{component[0]} ======"
    end
    cls = component[0]
    methods = Hash.new
    filename = apk.smali + cls + ".smali"
    if File.file?(filename)
      fh = File.open(filename, "r")
    else
      next
    end
    $libapis[cls] = Array.new
    lines = fh.readlines
    lines.each { |line|
      line = line[0...-1]
      if line.start_with?(".method")
        mtd = get_method_name(line)
        if methods[mtd] == nil
          methods[mtd] = Array.new
        end
        methods[mtd] << get_proto(line)
      end
    }
    methods.each { |mtd, ptys|
      ptys.each { |pty|
        caller = "#{cls}->#{mtd}#{pty}"
        if $caller_methods.include?(caller)
          next
        else
          run_assign(apk, cls, mtd, pty, 0, cls)
        end
        
      }
    }
  }
  pp "Associated Android or Java API"
  $libapis.each { |key, values|
    pp "Class: #{key}"
    values.each { |val|
      pp val
    }
    pp "=============================================="
  }
end

option_parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{THIS_FILE} target.apk [options]"
  opts.on("--cmd command", cmds, cmds.join(", ")) do |c|
    cmd = c
  end
  opts.on("--cpt component", cpts, cpts.join(", ")) do |c|
    cpt = c
  end
  opts.on("--cls class", "target class for xref.") do |c|
    cls = c
    p "cls is #{cls}"
  end
  opts.on("--mtd method", "target method for xref.") do |m|
    mtd = m
  end
  opts.on("--pty proto", "target prototype for xref.") do |p|
    pty = p
  end
  opts.on("--to file.png", "place output in file") do |t|
    to = t
  end
  opts.on("-a", "--assign", "assign cls, mtd and pty") do
    assign = true
  end
  opts.on("-v", "--verbose", "print debug information") do
    $verbose = true
  end
#  opts.on("-g", "--graph", "output graph file") do
#    $graph_need = true
#  end
  opts.on_tail("-h", "--help", "show this message") do
    puts opts
    exit
  end
end.parse!

if (cmd == "xref") and assign
	raise "--cls is mandatory" if !cls
	# raise "--mtd is mandatory" if !mtd
	# raise "--pty is mandatory" if !pty
end

if not cmds.include?(cmd)
	raise "wrong command"
end

if !cpt.eql?("") and !cpts.include?(cpt)
  raise "wrong component"
end

case File.extname(ARGV[0])
when ".apk"
	tmp_dir = ARGV[0].split('.')[0] + "_tmp_dir"
	apk = Apk.new(ARGV[0], tmp_dir)
  if apk.unpack
    dex = apk.dex
  else
    close(apk)
    raise "unpacking apk failed"
  end
else
	raise "wrong file extension"
end

case cmd
when "info"
  pp "services:"
  pp apk.services
  pp "activities:"
  pp apk.activities
when "xref"
  if assign
    if apk.services[cls] != nil
      cls = apk.services[cls]
    elsif apk.activities[cls] != nil
      cls = apk.activities[cls]
    else
      p "cls must be a service or an activity"
      exit
    end
    $libapis[cls[0]] = Array.new
    if mtd == nil or pty == nil
      run_assign(apk, cls[0], mtd, pty, 1, cls[0])
    else
      run_assign(apk, cls[0], mtd, pty, 0, cls[0])
    end
  else
    run_all(apk, cpt)
  end
end

#if $graph_need
#  $graph.output(:png => "#{to}.png")
#end

close(apk)
