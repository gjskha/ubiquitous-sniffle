#!ruby

require 'uri'
require 'net/http'
require 'getopt/std'
require 'json'

###############################################################################
# how to use the program 
# params: nothing
# returns: exit
def help

	puts <<-eohelp
		#{$0} -- get a definition from the Merriam-Webster dictionary
		Usage:
		$ #{$0} -h
		$ #{$0} [-s -p -x -c [-r config-file]] -w [word]
		
		Where :
		
		-h prints this message
		-w is followed by the word to look up
		-c cache the results
		-r use specified config file
		-x check cache on disk first
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
# cleaning up on completion
# params: array of results
# returns: nil
def clean(word_array,config)

	unless config["cache_result"]

		# remove "1" at the end of first of multiple entries
		json = config["cache_dir"] + "/" + word_array[0]["word"].split(":").first + ".json"
		File.delete(json) if File.exist?(json)

		for word in word_array
		
			if word["sound"]
				wav = config["cache_dir"] + "/" + word["sound"] + ".wav"
				File.delete(wav) if File.exist?(wav)
			end

			if word["art"]
				art = config["cache_dir"] + "/" + word["art"] + ".gif"
				File.delete(art) if File.exist?(art)
			end
		end
	end
end

###############################################################################
# get the definitions from disk or the remote server.
# params: file to fetch, url to use, configuration
# returns: the resource requested or nil 
def fetch_resource(file,url,config)

	resource = nil

	# methods are ordered by preference via the -x flag
	for method in config["methods"]

		if method == "disk" && resource == nil
			if File.exist?(file)
				resource = file
			end
		end

		if method == "net" && resource == nil
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

	filename = config["cache_dir"] + "/" + filename

	if fetch_resource(filename,art_url,config)
		system("#{config['viewer']} #{filename} 2>/dev/null")
	end

	return
end

###############################################################################
# how to pronounce a word
# params: remote filename, config
# returns: nil
def play_sound(filename,config)

	# These rules per the API documentation. Start with the base URL: 
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

	filename = config['cache_dir']+"/"+filename

	if fetch_resource(filename,sound_url,config)
		system("#{config['player']} #{filename} 2>/dev/null >/dev/null")
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

	file = config['cache_dir'] + "/" + word + ".json"	

	data = nil

	if fetch_resource(file,url,config)
		data = JSON.parse(IO.read(file))
	end

	data
end

###############################################################################
# print out the results
# params: array of results, config
# returns: nil
def print(word_array,config)

	for word in word_array

		puts word["word"]

		for d in word["defs"]
			puts "-- #{d}"
		end

		if word["sound"]
			play_sound(word["sound"],config) 
			sleep 1
		end

		if word["art"]
			display_image(word["art"],config)
		end
	end
end

###############################################################################
# main: entry point
# params: none
# returns: nil
def main
	
	# parse command line options
	opt = Getopt::Std.getopts("chspxw:r:")
	
	if opt["h"]
		help
	end
	
	# deal with configuration file
	config_file = ENV["HOME"] + "/.mwrc"
	if opt["r"]
		config_file = opt["r"]
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

	# set up method ordering
	if opt["x"]
		config["methods"] = ["disk","net"]
	else
		config["methods"] = ["net","disk"]
	end
	
	json = get_body(word,config)

	word_array = Array.new

	json.each { |entry|

		struct = Hash.new
		struct["word"] = entry["meta"]["id"]

		struct["defs"] = Array.new

		entry["shortdef"].each { |shortdef|
			struct["defs"].push(shortdef)
		}

		# some entries have gif files associated with them
		if opt["p"]
			if entry["art"]
				struct["art"] = entry["art"]["artid"]
			end
		end
	
		# play sound
		if opt["s"]
			# the sound files seem to be in one of two possible locations
			if entry.dig("uros", 0, "prs", 0, "sound", "audio")
				struct["sound"] = entry.dig("uros", 0, "prs", 0, "sound", "audio")
			end
	
			if entry.dig("hwi", "prs", 0, "sound", "audio")
				struct["sound"] = entry.dig("hwi", "prs", 0, "sound", "audio")
			end
		end
	
		word_array.push(struct)
	}

	print(word_array,config)

	clean(word_array,config)

	return	
end

# we use this pythonism for facilitating testing
if __FILE__ == $0
	main
end
