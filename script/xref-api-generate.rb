require 'optparse'
require 'pp'

cmds = [
	"analyse", "xref"
]

cmd = ""
$rmcmd = false
$verbose = false

def runcmd(cmd)
	out = ""
	out << `#{cmd}`
	$?.exitstatus == 0
end

dir = nil
xref_dir = "/Users/luisleo/Programs/utils_by_ruby/apk-static-xref"

ption_parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby xref-api-generate.rb --apk path-to-apps-dir [options]"
  opts.on("--cmd command", cmds, cmds.join(", ")) do |c|
    cmd = c
  end
  opts.on("--apk path-to-apk-files", "Path to the directory of apk files") do |path|
    dir = path 
  end
  opts.on("--xref path-to-xref-directory", "Path to the directory of apk-static-xref") do |path|
    xref_dir = path 
  end
  opts.on("-v", "--verbose", "print debug information") do
    $verbose = true
  end
  opts.on("-r", "--remove", "remove temp_dir directory") do
    $rmcmd = true
  end
  opts.on_tail("-h", "--help", "show this message") do
    puts opts
    exit
  end
end.parse!

if dir == nil
	p "Usage: ruby xref-api-generate.rb --apk path-to-apps-dir [options]"
	exit
end

temp_dir = "#{dir}/xref_temp"

if !File.exist?(temp_dir)
	`mkdir #{temp_dir}`
end

if !cmd.eql?("analyse")
	Dir.chdir(temp_dir)
	done_files = Dir.glob("**/*")
	Dir.chdir(dir)
	files = Dir.glob("**/*.apk")
	files.each { |file|
		if !done_files.include?(file)
			tempfile = "#{temp_dir}/#{file.split('.')[0]}"
			cmd = "ruby #{xref_dir}/script/xref.rb #{file} --cmd xref --cpt service -v >> #{tempfile}"
			if !runcmd(cmd)
				print "Error parse file #{file}"
			end
			if $verbose
				pp "Finished file #{file}"
			end
		else
			if $verbose
				pp "Skip file #{file}"
			end
		end
	}
end

xref_apis = Hash.new

Dir.chdir(temp_dir)
summarize_file = File.open("#{dir}/summary", "w")
files = Dir.glob("*")
files.each { |file|
	if $verbose
		pp "Analysing file #{file}"
	end
	lines = File.readlines(file)
	lines.each { |line|
		if xref_apis[line] == nil
			if !line.include?("======") and !line.include?("no components in") \
				and line.include?("android")
				xref_apis[line] = 1
			end
		else
			xref_apis[line] += 1
		end
	}
}
xref_apis.sort_by{|key, value| value}.reverse.each { |line|
	summarize_file.write("#{line[0].strip} : #{line[1]}\n")
}

if $rmcmd
	`rm -rf #{dir}xref_temp`
end
