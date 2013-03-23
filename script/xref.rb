require 'optparse'
require 'pathname'
require 'pp'
require 'graphviz'

class Smali_Function

  TYPE_STR = {
    'V'=>'void',
    'Z'=>'boolean',
    'B'=>'byte',
    'S'=>'short',
    'C'=>'char',
    'I'=>'int',
    'J'=>'long',
    'F'=>'float',
    'D'=>'double'
  }

  def initialize
    @cls = nil
    @mtd = nil
    @pty = nil
    @rettype = nil
    @para = []
  end

  # Method parameters types
  def extractCallParameters(line)
    useful_parts = line.split(' ')[-1][1..-1]
    para_str = useful_parts.split('(')[1].split(')')[0]
    temp_para = Array.new
    array = false
    while para_str.length > 0
      i = 0
      if i < para_str.length
        if para_str[i] == 'L'
          while (para_str[i] != ';') and (i < para_str.length)
            i += 1
          end
          if array
            temp_para << (para_str[1...i] + "[]")
            array = false
          else
            temp_para << para_str[1...i]
          end
          para_str = para_str[i+1..-1]
        elsif para_str[i] == '['
          array = true
          while para_str[i] == '['
            i += 1
          end
          para_str = para_str[i..-1]
        else
          value = TYPE_STR[para_str[i]]
          if array
            temp_para << (value + "[]")
            array = false
          else
            temp_para << value
          end
          para_str = para_str[i+1..-1]
        end
      end
    end
    @para = temp_para 
  end

  # Method return type
  def extractReturnType(line)
    useful_parts = line.split(' ')[-1][1..-1]
    retval = line.split(')')[1]
    ## TODO: and.. what about array on return types?
    value = (retval.length == 1) ? TYPE_STR[retval] : retval[1...-1]
    @rettype = value
  end

  # Method proto
  def extractProto(line)
    useful_parts = line.split(' ')[-1]
    @pty = "(" + useful_parts.split('(')[-1]
  end

  def str
    "#{@cls}->#{@mtd}#{@pty}"
  end
end

class Invoked < Smali_Function
  attr_reader :cls, :mtd, :pty
  def initialize(smali_invoke_line)
    super()
    extractOwnerClass(smali_invoke_line)
    extractMethodName(smali_invoke_line)
    extractProto(smali_invoke_line)
    extractCallParameters(smali_invoke_line)
    extractReturnType(smali_invoke_line)
  end

  # Method class owner extractor
  def extractOwnerClass(line)
    useful_parts = line.split(' ')[-1][1..-1]
    @cls = useful_parts.split('-')[0][0...-1]
  end

  #Method name extractor
  def extractMethodName(line)
    useful_parts = line.split(' ')[-1]
    useful_parts = useful_parts.split('->')[1]
    @mtd = useful_parts.split('(')[0]
  end
end

class Invoker < Smali_Function
  attr_reader :cls, :mtd, :pty
  def initialize(cls, smali_line)
    super()
    @cls = cls
    extractMethodName(smali_line)
    extractProto(smali_line)
    extractCallParameters(smali_line)
    extractReturnType(smali_line)
  end

  #Method name extractor
  def extractMethodName(line)
    useful_parts = line.split(' ')[-1]
    @mtd = useful_parts.split('(')[0]
  end
end

THIS_FILE = Pathname.new(__FILE__).realpath.to_s
HERE = File.dirname(THIS_FILE)

require "#{HERE}/apk"

cmds = [
	"info", "xref"
]

cmd = ""
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

def close(apk)
  apk.clean if apk
end

def addNodes(n1, n2)
  node1 = $graph.add_nodes(n1)
  node2 = $graph.add_nodes(n2)
  $graph.add_edges(node1, node2)
end

def run_assign(apk, cls, mtd, pty)
  match = 0
  caller = nil
  callee = nil
  vclass = nil
  filename = apk.smali + cls + ".smali"
  if File.file?(filename)
    fh = File.open(filename, "r")
  else
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
      if match == 1
        if $caller_methods.include?(callee.str)
          if !$caller_methods.include?(caller.str)
            addNodes(caller.str, callee.str) if $graph_need
            if $verbose
              pp "#{caller.str} : #{callee.str}"
            end
          end
        else
          addNodes(caller.str, callee.str) if $graph_need
          if $verbose
            pp "#{caller.str} : #{callee.str}"
          end
          $caller_methods << caller.str
          run_assign(apk, callee.cls, callee.mtd, callee.pty)
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

def run_all(apk)
  services = apk.services
  if services.size == 0
    pp "no service in #{ARGV[0]}"
    close(apk) 
    exit
  end
  services.each { |serv|
    if $verbose
      pp "====== process service - #{serv} ======"
    end
    cls = serv.gsub('.', '/')
    methods = Hash.new
    filename = apk.smali + cls + ".smali"
    if File.file?(filename)
      fh = File.open(filename, "r")
    else
      next
    end
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
          run_assign(apk, cls, mtd, pty)
        end
        
      }
    }
  }
end

option_parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{THIS_FILE} target.(apk|xml) [options]"
  opts.on("--cmd command", cmds, cmds.join(", ")) do |c|
    cmd = c
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
	raise "--mtd is mandatory" if !mtd
	raise "--pty is mandatory" if !pty
end

if not cmds.include?(cmd)
	raise "wrong command"
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
when ".xml"
	services = parse(ARGV[0])
else
	raise "wrong file extension"
end

case cmd
when "info"
when "xref"
  if assign
    run_assign(apk, cls, mtd, pty)
  else
    run_all(apk)
  end
end

if $graph_need
  $graph.output(:png => "#{to}.png")
end

close(apk)
