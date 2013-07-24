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
$verbose2 = false

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

def parse_parameters(raw)
 ret = Array.new
 i = 0
 while raw.size > 0
   case raw[0]
   when 'Z', 'B', 'C', 'S', 'F', 'I', 'D', 'J'
     ret[i] = ['P']
     i += 1
     raw = raw[1..-1]
   when 'L'
     t = raw.index(';')
     ret[i] = ['L', raw[1..t-1]]
     i += 1
     raw = raw[t+1..-1]
     if raw.size == 0
       return ret
     end
   when '['
     if raw[1] == 'L'
       t = raw.index(';')
       ret[i] = ['L', raw[2..t-1]]
       i += 1
       raw = raw[t+1..-1]
     else
       ret[i] = ['P']
       i += 1
       raw = raw[2..-1]
     end
   end
 end
 return ret
end

def run_assign(apk, cls, mtd, pty, flag, ori_cls)
  match = 0
  caller = nil
  callee = nil
  vclass = nil
  filename = apk.smali + cls + ".smali" # it is for mac OS
  if File.file?(filename)
    fh = File.open(filename, "r")
  else
    if !$libapis[ori_cls].include?("#{cls}->#{mtd}#{pty}")
      $libapis[ori_cls] << "#{cls}->#{mtd}#{pty}"
    end
    return
  end
  # Start to parse smali file 
  if $verbose2
    pp "Enter file: #{filename}"
  end
  initfld = 0
  get_method = false
  vbind = Hash.new
  lines = fh.readlines
  lines.each { |line|
    line = line[0...-1]
    if line.start_with?(".class")
      vclass = line.split()[-1][1...-1]
      if $fields[vclass] == nil
        $fields[vclass] = Hash.new
      end
    elsif line.start_with?(".field")
      field = line.split()[-1].split(':')
      if field.size > 1
        if field[1].start_with?('L')
          $fields[cls][field[0]] = ['L', field[1][1..-2]]
        elsif field[1].start_with?('[')
          if field[1].start_with?('[L')
            $fields[cls][field[0]] = ['L', field[1][2..-2]]
          else
            $fields[cls][field[0]] = ['P']
          end
        else
          $fields[cls][field[0]] = ['P']
        end
      end
    elsif line.start_with?(".method")
      if line.split()[-1].start_with?("<init>")
        initfld = 1
        get_method = true
        if $verbose2
          pp "Enter Method: init"
        end
        ret = parse_parameters(line.split()[-1].split('(')[1].split(')')[0])
        if $verbose2
          pp "ret: #{ret}"
        end
        vbind["p0"] = ['L', cls]
        for i in 1..ret.size
          vbind["p#{i}"] = ret[i-1]
          if $verbose2
            pp "vbind[p#{i}]: #{vbind["p#{i}"]}"
          end
        end
      else
        caller = Invoker.new(vclass, line)
        if (mtd.eql?("doInBackground")) and caller.mtd.eql?(mtd)
          match, get_method = 1, true
        elsif (caller.mtd.eql?(mtd)) and (caller.pty.eql?(pty))
          match, get_method = 1, true
        elsif flag == 1
          match, get_method = 1, true
        end
        if match == 1
          if $verbose2
            pp "Enter Method: #{caller.mtd}"
          end
          ret = parse_parameters(line.split()[-1].split('(')[1].split(')')[0])
          if $verbose2
            pp "ret: #{ret}"
          end
          vbind["p0"] = ['L', cls]
          for i in 1..ret.size
            vbind["p#{i}"] = ret[i-1]
            if $verbose2
              pp "vbind[p#{i}]: #{vbind["p#{i}"]}"
            end
          end
        end
      end
    elsif line.start_with?(".end method")
      if mtd.eql?("<init>") and initfld == 1
        return
      end
      initfld = 0 if initfld == 1
      match = 0 if match == 1
    elsif initfld == 1 or match == 1
      if $verbose2
        pp "parse #{line}"
      end
      # new-* instruction
      if line =~ /\s*new-instance.*/
        if vbind[line.split()[1]] == nil
          vbind[line.split()[1]] = Array.new
        end
        vbind[line.split()[1]] = ['L', line.split()[2][1..-2]]
        if $verbose2
          pp "vbind[#{line.split()[1]}]: #{vbind[line.split()[1]]}"
        end
      elsif line =~ /\s*new-array.*/
        type = line.split()[3]
        if type[1] == 'L'
          vbind[line.split()[1][0..-2]] = ['L', type[2..-2]]
          if $verbose2
            pp "vbind[#{line.split()[1][0..-2]}]: #{vbind[line.split()[1][0..-2]]}"
          end
        else
          vbind[line.split()[1][0..-2]] = ['P']
        end
      # move-* instruction
      elsif line =~ /\s*move-object.*/
        vbind[line.split()[1]] = vbind[line.split()[2]]
        if $verbose2
          pp "vbind[#{line.split()[1]}]: #{vbind[line.split()[1]]}"
        end
      elsif line =~ /\s*move-result.*/
        vbind[line.split()[1]] = vbind["ret-val"]
        if $verbose2
          pp "vbind[#{line.split()[1]}]: #{vbind[line.split()[1]]}"
        end
      # const* instruction
      elsif line =~ /\s*const-class.*/
        vbind[line.split()[1][0..-2]] = ['L', line.split()[2][0..-2]]
        if $verbose2
          pp "vbind[#{line.split()[1][0..-2]}]: #{vbind[line.split()[1][0..-2]]}"
        end
      elsif line =~ /\s*const.*/ and line.split().size > 2
        vbind[line.split()[1][0..-2]] = ['P']
      # .local
      elsif line =~ /\s*.local\s.*/
        type = line.split()[2].split(':')[1]
        if type[0] == 'L'
          vbind[line.split()[1][0..-2]] = ['L', type[1..-2]]
        elsif type[0] == '[' and type[1] == 'L'
          vbind[line.split()[1][0..-2]] = ['L', type[2..-2]]
        else
          vbind[line.split()[1][0..-2]] = ['P']
        end
        if $verbose2
          pp "vbind[#{line.split()[1][0..-2]}]: #{vbind[line.split()[1][0..-2]]}"
        end
      # [isa]get-* instruction
      elsif line =~ /\s*[is]get-object.*/
        if line =~ /\s*iget-object.*/
          clas = line.split()[3].split('->')[0][1..-2]
          field = line.split()[3].split('->')[1].split(':')[0]
          type = line.split()[3].split('->')[1].split(':')[1]
        else
          clas = line.split()[2].split('->')[0][1..-2]
          field = line.split()[2].split('->')[1].split(':')[0]
          type = line.split()[2].split('->')[1].split(':')[1]
        end
        if $fields[clas] == nil
          run_assign(apk, clas, "<init>", nil, 0, ori_cls)
        end
        if $fields[clas][field] == nil
          if type[0] == 'L'
            $fields[clas][field] = ['L', type[1..-2]]
          elsif type[0] == '[' and type[1] == 'L'
            $fields[clas][field] = ['L', type[2..-2]]
          else
            $fields[clas][field] = ['P']
          end
        end
        vbind[line.split()[1][0..-2]] = $fields[clas][field]
        if $verbose2
          pp "vbind[#{line.split()[1][0..-2]}]: #{vbind[line.split()[1][0..-2]]}"
        end
      elsif line =~ /\s*aget-object.*/
        vbind[line.split()[1][0..-2]] = vbind[line.split()[2][0..-2]]
        if $verbose2
          pp "vbind[#{line.split()[1][0..-2]}]: #{vbind[line.split()[1][0..-2]]}"
        end
      elsif line =~ /\s*[asi]get.*/
        vbind[line.split()[1][0..-2]] = ['P']
        if $verbose2
          pp "vbind[#{line.split()[1][0..-2]}]: #{vbind[line.split()[1][0..-2]]}"
        end
      # [isa]put-* instruction
      elsif line =~ /\s*[is]put-object.*/
        if line =~ /\s*iput-object.*/
          clas = line.split()[3].split('->')[0][1..-2]
          field = line.split()[3].split('->')[1].split(':')[0]
        else
          clas = line.split()[2].split('->')[0][1..-2]
          field = line.split()[2].split('->')[1].split(':')[0]
          if $fields[clas] == nil
            pp "#{cls}, #{line}, #{clas}, #{field}"
            $fields[clas] = Hash.new
          end
          $fields[clas][field] = vbind[line.split()[1][0..-2]]
          if $verbose2
            pp "$filed[#{clas}][#{field}]: #{$fields[clas][field]}"
          end
        end
      elsif line =~ /\s*aput-object.*/
        vbind[line.split()[2][0..-2]] = vbind[line.split()[1][0..-2]]
        if $verbose2
          pp "vbind[#{line.split()[2][0..-2]}]: #{vbind[line.split()[2][0..-2]]}"
        end
      elsif line =~ /\s*[si]put.*/
        clas = line.split()[-1].split('->')[0][1..-2]
        field = line.split()[-1].split('->')[1].split(':')[0]
        if $fields[clas] == nil
          $fields[clas] = Hash.new
        end
        $fields[clas][field] = ['P']
        if $verbose2
          pp "$filed[#{clas}][#{field}]: #{$fields[clas][field]}"
        end
      elsif line =~ /\s*aput.*/
        vbind[line.split()[2][0..-2]] = ['P']
        if $verbose2
          pp "vbind[#{line.split()[2][0..-2]}]: #{vbind[line.split()[2][0..-2]]}"
        end
      # invoke-* instruction
      elsif line =~ /\s*invoke-.*/
        # get parameters of the method invoke
        vars = Array.new
        # specific situation for range call
        if line =~ /\s*invoke-.*\/range.*/
          vtotal = line.split('{')[1].split('}')[0].split(" .. ")
          vstart = vtotal[0][1..-1].to_i
          vend = vtotal[1][1..-1].to_i
          (vstart..vend).map {|i| vars << "v#{i}"}
        else
          vars = line.split('{')[1].split('}')[0].split(', ')
        end
        if $verbose2
          pp "vars: #{vars}"
        end
        # init method for some special method like Thread.init, Handler.init...
        if line =~ /\s*invoke-direct.*<init>.*/
          pnum = vars.size - 1
          vbind[vars[0]][2] = pnum
          for i in 1..pnum
            vbind[vars[0]][i+2] = vbind[vars[i]]
          end
          if $verbose2
            pp "vbind[#{vars[0]}]: #{vbind[vars[0]]}"
          end
        end
        # get return type for "move-result-*" instructions
        retType = line.split(')')[-1]
        if retType[0] == 'L'
          vbind["ret-val"] = ['L', retType[1..-2]]
        elsif retType[0] == '[' and retType[1] == 'L'
          vbind["ret-val"] = ['L', retType[2..-2]]
        else
          vbind["ret-val"] = ['P']
        end
        if $verbose2
          pp "vbind[ret-val]: #{vbind["ret-val"]}"
        end
        # start to analysis the method invoke
        callee = Invoked.new(line)
        if callee.str =~ /.*java\/lang\/Thread->start\(\)V.*/
          callee.cls = vbind[vars[0]][3][1]
          callee.mtd = "run"
          callee.pty = "()V"
        elsif callee.str =~ /.*android\/os\/Handler->send.*Message\(.*\)Z.*/
          callee.cls = vbind[vars[0]][1]
          callee.mtd = "handleMessage"
          callee.pty = "(Landroid/os/Message;)V"
        elsif callee.str =~ /.*->execute\(\[Ljava\/lang\/Object;\)Landroid\/os\/AsyncTask;/
          callee.mtd = "doInBackground"
          callee.pty = ""
        elsif callee.str =~ /.*->execute\(Ljava\/lang\/Runnable;\)V/
          callee.cls = vbind[vars[1]][1]
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
          pp "#{caller.str} : #{callee.str}"
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
  opts.on("-v2", "--verbose2", "print more debug information") do
    $verbose2 = true
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
