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
		$ #{$0} [-s -p -x -c -C] -w [word]
		
		Where :
		
		-h prints this message
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
# If a word has an illustration we can fetch it
# params: filename string, config
# returns: nil
def display_image(filename, config)

	art_url = "https://www.merriam-webster.com/assets/mw/static/art/dict/" 
	art_url += filename + ".gif"
	art = Net::HTTP.get(URI(art_url))
	File.write("/tmp/" + filename, art)
	
	system("#{config['viewer']} #{filename} 2>/dev/null &")

	if config["cache_result"]
		puts "saving"
	else
		puts "deleting"
		File.delete("/tmp/"+filename) if File.exist?("/tmp/"+filename)
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
	sound_url = "http://media.merriam-webster.com/soundc11/"
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

	puts sound_url
	sound_file = Net::HTTP.get(URI(sound_url))

	File.write("/tmp/" + filename, sound_file)

	system("#{config['player']} #{filename} 2>/dev/null")

	if config["cache_result"]
		puts "saving"
	else
		puts "deleting"
		#File.delete("/tmp/"+filename) if File.exist?("/tmp/"+filename)
	end

	return
end

def get_body(word, config)
	base_url =  "https://www.dictionaryapi.com/api/v3/references/collegiate/json/"
	cache_file = config["cache_dir"] + "/" + word + ".json"
	body = Net::HTTP.get(URI(base_url + word + "?key=" + config["key"]))
	
	if config["cache_result"]
		File.write(cache_file, body)
	end

	JSON.parse(body)
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
	config_file = ENV["HOME"] + "/.mwrc";
	if opt["C"]
		config_file = opt["C"]
	end
	config = parse_config(config_file)
	
	word = String.new
	if opt["w"]
		word = opt["w"]
	else
		help
	end
	
	config["cache_result"] = false
	if opt["c"]
		config["cache_result"] = true
		Dir.mkdir(config["cache_dir"]) unless File.exists?(config["cache_dir"])  
	end
	
	#base_url =  "https://www.dictionaryapi.com/api/v3/references/collegiate/json/"
	# XXX
	cache_file = config["cache_dir"] + "/" + word + ".json"
	if opt["x"]
		if File.exists?(cache_file)
			# XXX
			json = JSON.parse(IO.read(cache_file))
		else
			json = get_body(word,config)
		end
	else
		json = get_body(word,config)
	end
	
	json.each { |entry|
	
		# some entries have gif files associated with them
		if opt["p"]
			if entry["art"]
				#art_file = entry["art"]["artid"] + ".gif"
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

#main	
if __FILE__ == $0
	main
end
