require 'optparse'
require 'pathname'
require 'pp'
require 'graphviz'

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
graph_need = false
$verbose = false

$caller_methods = Array.new
# Create a new graph
$graph = GraphViz.new( :G, :type => :digraph )

$libapis = Hash.new

def close(apk)
  apk.clean if apk
end

def addNodes(n1, n2)
  node1 = $graph.add_nodes(n1)
  node2 = $graph.add_nodes(n2)
  $graph.add_edges(node1, node2)
end

def run_assign(apk, cls, mtd, pty, flag, ori_cls)
  match = 0
  caller = nil
  callee = nil
  vclass = nil
  filename = apk.smali + cls + ".smali"
  if File.file?(filename)
    fh = File.open(filename, "r")
  else
    if !$libapis[ori_cls].include?("#{cls}->#{mtd}#{pty}")
      if $verbose
        pp "#{cls}->#{mtd}#{pty}"
      end
      $libapis[ori_cls] << "#{cls}->#{mtd}#{pty}"
    end
    return
  end
  lines = fh.readlines
  lines.each { |line|
    line = line[0...-1]
    if line.start_with?(".class")
      vclass = line.split(' ')[-1][1...-1]
    elsif line.start_with?(".method")
      caller = Invoker.new(vclass, line)
      if (caller.mtd.eql?(mtd)) and (caller.pty.eql?(pty))
        match = 1
      end
    elsif line.start_with?(".end method")
      match = 0
    elsif line.include?("invoke-")
      callee = Invoked.new(line)
      if (match == 1) or (flag == 1)
        if $caller_methods.include?(callee.str)
          if !$caller_methods.include?(caller.str)
            addNodes(caller.str, callee.str) if $graph_need
            if $verbose
              #pp "#{caller.str} : #{callee.str}"
            end
          end
        else
          addNodes(caller.str, callee.str) if $graph_need
          if $verbose
            #pp "#{caller.str} : #{callee.str}"
          end
          $caller_methods << caller.str
          run_assign(apk, callee.cls, callee.mtd, callee.pty, 0, ori_cls)
        end
      end
    end
  }
end

def get_method_name(line)
  line.split(' ')[-1].split('(')[0]
end

def get_proto(line)
  "(#{line.split(' ')[-1].split('(')[-1]}"
end

def run_all(apk, cpt)
  if cpt.eql?("service")
    components = apk.services
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
  components.each { |component|
    if $verbose
      pp "====== process components - #{component} ======"
    end
    cls = component.gsub('.', '/')
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
  opts.on("-g", "--graph", "output graph file") do
    $graph_need = true
  end
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
    $libapis[cls] = Array.new
    if mtd == nil or pty == nil
      run_assign(apk, cls, mtd, pty, 1, cls)
    else
      run_assign(apk, cls, mtd, pty, 0, cls)
    end
  else
    run_all(apk, cpt)
  end
end

if $graph_need
  $graph.output(:png => "#{to}.png")
end

close(apk)
