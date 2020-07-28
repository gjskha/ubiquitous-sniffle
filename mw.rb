#!/home/jujee/.rvm/rubies/ruby-2.6.5/bin/ruby

require 'uri'
require 'net/http'
require 'getopt/std'
require 'json'

# TODO: put all images and sounds at the end, then delete there if needed

###############################################################################
# how to use the program 
# params: nothing
# returns: exit
def help

	puts <<-eohelp
		#{$0} -- get a definition from the Merriam-Webster dictionary
		Usage:
		$ #{$0} -h
		$ #{$0} [-s -p -x -c [-C file]] -w [word]
		
		Where :
		
		-h prints this message
		-w is followed by the word to look up
		-c cache_dir the results
		-C use specified config file
		-x check cache_dir first for definition
		-s play associated sound file, if available
		-p display associated image, if available
	eohelp
	
	exit

end

###############################################################################
# parses a config file
# params: a file location
# returns: config data structure
def parse_config(location)

	config = {}

	if File.exists?(location)
		config = JSON.parse(IO.read(location))
	end

	# for several parameters, use reasonable defaults
	if config["player"].nil? 
		config["player"] = "mplayer" 
	end

	if config["viewer"].nil? 
		config["viewer"] = "gthumb" 
	end

	if config["cache_dir"].nil? 
		config["cache_dir"] = ENV["HOME"] + "/.mw"
	end

	# We cannot continue without a key
	if config["key"].nil?
		puts "Merriam-Webster API key is missing, exiting."
		exit
	end

	config
end

###############################################################################
# 
# params: 
# returns: 
def fetch_resource(file,url,config)

	resource = nil

	# methods are ordered by preference via the -x flag
	for method in config["methods"]

		if method == "disk"

			# read the fully qualified file
			if File.exist?(file)
				resource = file
			end
		end

		if method == "net"
	
			res = Net::HTTP.get_response(URI(url))
			if res.code == "200"
				File.write(file, res.body)

				resource = file
			end
		end

	end

	resource	
end

###############################################################################
# If a word has an illustration we can fetch it
# params: filename string, config
# returns: nil
def display_image(filename, config)

	filename += ".gif"

	art_url = "https://www.merriam-webster.com/assets/mw/static/art/dict/" 
	art_url += filename

	# XXX fix this do I need to return anything?
	filename = config["cache_dir"] + "/" + filename
	resource = fetch_resource(filename,art_url,config)

	if resource != nil
		system("#{config['viewer']} #{resource} 2>/dev/null")

	end

	unless config["cache_result"]
		puts "deleting"
		File.delete(resource) if File.exist?(resource)
	end

	return
end

###############################################################################
# how to pronounce a word
# params: remote filename, config
# returns: nil
def play_sound(filename,config)

	# these rules per the API documentation.
	# Start with the base URL: 
	sound_url = "https://media.merriam-webster.com/soundc11/"
	# If the file name begins with "bix", the subdirectory should be "bix".
	if filename.match(/^bix/)
		sound_url += "bix/"
	# If the file name begins with "gg", the subdirectory should be "gg".
	elsif filename.match(/^gg/)
		sound_url += "gg/" 
	# If the file name begins with a number, the subdirectory should be "number".
	elsif filename.match(/^[0-9]/)
		sound_url += "number/" 
	# Else add the first letter of the wav file as a subdirectory
	else
		substr = filename[0,1]
 		sound_url += substr + "/"
	end

	filename += ".wav"

	sound_url += filename

	filename = config['cache_dir']+"/"+filename+".wav"

	local_store = fetch_resource(filename,sound_url,config)

	system("#{config['player']} #{local_store} 2>/dev/null >/dev/null")

	unless config["cache_result"]
		File.delete(local_store) if File.exist?(local_store)
	end

	return
end

###############################################################################
# how to pronounce a word
# params: word to look up, config
# returns: parsed json object
def get_body(word, config)

	url =  "https://www.dictionaryapi.com/api/v3/references/collegiate/json/"
	url += word + "?key=" + config["key"]

	file = config['cache_dir']+"/"+word + ".json"	
	#resource = fetch_resource(file,url)
	resource = fetch_resource(file,url,config)

	data = JSON.parse(IO.read(resource))

	unless config["cache_result"]
		File.delete(resource) if File.exist?(resource)
	end

	data
end

###############################################################################
# main: entry point
# params: none
# returns: nil
def main
	
	# parse command line options
	opt = Getopt::Std.getopts("chspxw:C:")
	
	if opt["h"]
		help
	end
	
	# deal with configuration file
	config_file = ENV["HOME"] + "/.mwrc"
	if opt["C"]
		config_file = opt["C"]
	end
	config = parse_config(config_file)
	
	# get the word to look up
	word = String.new
	if opt["w"]
		word = opt["w"]
	else
		help
	end
	
	# execute caching options
	config["cache_result"] = false
	if opt["c"]
		config["cache_result"] = true
		Dir.mkdir(config["cache_dir"]) unless File.exists?(config["cache_dir"])  
	end

	# get the definitions from disk or the remote server.
	cache_file = config["cache_dir"] + "/" + word + ".json"

	# set up method ordering
	config["methods"] = ["net","disk"]
	if opt["x"]
		#config["local_first"] = true
		config["methods"] = ["disk","net"]

	end
	
	json = get_body(word,config)

	json.each { |entry|
		# some entries have gif files associated with them
		if opt["p"]
			if entry["art"]
				display_image(entry["art"]["artid"],config) 
			end
		end
	
		# play sound
		if opt["s"]
			# pronounce the words seems to be in two possible locations
			if entry.dig("uros", 0, "prs", 0, "sound", "audio")
				play_sound(entry.dig("uros", 0, "prs", 0, "sound", "audio"),config)
			end
	
			if entry.dig("hwi", "prs", 0, "sound", "audio")
				play_sound(entry.dig("hwi", "prs", 0, "sound", "audio"),config)
			end
		end
	
		#print the definition
		puts entry["meta"]["id"] 
	
		entry["shortdef"].each { |shortdef|
			puts  " -- " + shortdef
		}
	}

	return	
end

if __FILE__ == $0
	main
end
