#!/usr/bin/ruby -w
require 'json'
require 'fileutils'
require 'open3'
require 'getoptlong'

# TestMin is a simple, minimalist testing framework. It evolved out of the need
# for such a framework for Utilibase. TestMin will eventually be spun off into
# its own project.

# note clear as done
ENV['clear_done'] = '1'


################################################################################
# TestMin
#
module TestMin
	
	# TestMin version
	VERSION = '0.0.1'
	
	# length for horizontal rules
	HR_LENGTH = 100
	
	# directory settings file
	DIR_SETTINGS_FILE = 'testmin.dir.json'
	GLOBAL_CONFIG_FILE = './testmin.config.json'
	
	# human languages (e.g. english, spanish)
	# For now we only have English.
	@human_languages = ['en']
	
	# if devshortcut() has been called
	@devshortcut_called = false
	
	# settings
	@settings = nil
	
	#---------------------------------------------------------------------------
	# DefaultSettings
	#
	DefaultSettings = {
		# timeout: set to 0 for no timeout
		'timeout' => 30,
		
		# should the user be prompted to submit the test results
		'submit' => {
			'request' => false,
			'url' => 'https://testmin.idocs.com/submit',
			'title' => 'Idocs Testmin',
			'messages' => {
				'en' => {
					# request to submit results
					'submit-request' => <<~TEXT,
					May this script submit these test results to [[title]]?
					The results will be submitted to the Idocs TestMin service
					where they will be publicly available. In addition to the
					test results, the only information about your system will be
					the operating system and version, the version of Ruby, and
					the version of TestMin.
					TEXT
					
					# request to add email address
					'email-request' => <<~TEXT,
					Would you like to send your email address? Your email will
					not be displayed publicly. You will only be contacted to
					about this project.
					TEXT
				}
			}
		},
		
		# messages
		'messages' => {
			# English
			'en' => {
				# general purpose messages
				'success' => 'success',
				'failure' => 'failure',
				
				# messages about test results
				'test-success' => 'All tests run successfully',
				'test-failure' => 'There were some errors in the tests',
				'finished-testing' => 'finished testing',
				
				# submit messages
				'email-prompt' => 'email address',
				'submit-hold' => 'Submitting...',
				'submit-success' => 'Test results successfully submitted.',
				'submit-failure' => 'Submission of test results failed. Errors: [[errors]]',
				
				# prompts
				'yn' => '[Yes|No]',
			},
			
			# Spanish
			# Did one message in Spanish just to test the system. Somebody
			# please feel free to add Spanish translations.
			'es' => {
				'submit-results' => '¿Envíe estos resultados de la prueba a [[title]]?'
			},
		},
	}
	#
	# DefaultSettings
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# done
	#
	def TestMin.done(opts = {})
		# TestMin.hr(__method__.to_s)
		
		# cannot mark done if _devshortcut_called is true
		# if Settings['devshortcut_called']
		if @devshortcut_called
			raise 'devshortcut called, so cannot mark as done'
		end if
		
		# initialize hash
		opts = {'testmin-success'=>true}.merge(opts)
		
		# output done hash
		puts JSON.generate(opts)
		
		# exit
		exit
	end
	#
	# done
	#---------------------------------------------------------------------------

	
	#---------------------------------------------------------------------------
	# devshortcut
	#
	def TestMin.devshortcut()
		@devshortcut_called = true
		return false
	end
	#
	# devshortcut
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# dir_settings
	#
	def TestMin.dir_settings(run_dirs, dir_path)
		# TestMin.hr(dir_path)
		
		# normalize dir_path to remove trailing / if there is one
		dir_path = dir_path.gsub(/\/+\z/, '')
		
		# initialize directory properties and settings
		dir = {}
		dir['path'] = dir_path
		dir['settings'] = {}
		run_dirs.push(dir)
		
		# build settings path
		settings_path = dir_path + '/' + DIR_SETTINGS_FILE
		
		# slurp in settings from directory settings file if it exists
		if File.exist?(settings_path)
			begin
				file_settings = JSON.parse(File.read(settings_path))
				dir['settings'] = dir['settings'].merge(file_settings)
			rescue Exception => e
				# TESTING
				# puts 'parse error'
				
				# note error in directory log
				dir['success'] = false
				dir['errors'] = [
					{
						'id'=>'testmin.dir.json-parse-error',
						'exception-message' => e.message,
					}
				]
				
				# note that test run has failed
				log['success'] = false
				
				# return
				return false
			end
		end
		
		# set default dir-order
		if dir['settings']['dir-order'].nil?()
			dir['settings']['dir-order'] = 1000000
		end
		
		# set default files
		if dir['settings']['files'].nil?()
			dir['settings']['files'] = []
		else
			if not dir['settings']['files'].is_a?(Array)
				raise 'files setting is not an array for ' + dir_path
			end
		end
		
		# return success
		return true
	end
	#
	# dir_settings
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# dir_check
	#
	def TestMin.dir_check(log, dir)
		# TestMin.hr(__method__.to_s)
		
		# change into test dir
		Dir.chdir(dir['path']) do
			in_dir = {}
			in_settings = {}
			
			# build hash of files in settings
			dir['settings']['files'].each do |file_path|
				in_settings[file_path] = true
			end
			
			# get list of rb files in directory, except for dev files
			Dir.glob('./*.rb').each do |file_path|
				# remove leading ./
				file_path = file_path.sub(/\A\.\//, '')
				
				# skip dev files
				if not file_path.match(/\Adev\./)
					in_dir[file_path] = true
				end
				
				# remove from settings
				in_settings.delete(file_path)
			end
			
			# should not have anything left in in_settings
			if in_settings.keys.length > 0
				message = {}
				message['error'] = true
				message['id'] = 'non-existent-file'
				message['dir'] = dir['path']
				message['files'] = in_settings.keys
				log['messages'].push(message)
				log['success'] = false
				
				puts 'do not have file(s) in ' + dir['path'] + ': ' + in_settings.keys.join(' ')
				return false
			end
			
			# loop through files setting, removing
			# existing files from in_dir
			dir['settings']['files'].each do |file_path|
				in_dir.delete(file_path)
			end
			
			# add remaining files to files list
			in_dir.keys.each do |file|
				puts '*** not in ' + DIR_SETTINGS_FILE + ': ' + dir['path'] + '/' + file
				dir['files'].push(file)
			end
		end
		
		# retutrn success
		return true
	end
	#
	# dir_check
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# dir_run
	#
	def TestMin.dir_run(log, dir, dir_order)
		# verbosify
		dir_path_display = dir['path']
		dir_path_display = dir_path_display.sub(/\A\.\//, '')
		TestMin.hr('title'=>dir_path_display, 'dash'=>'=')
		
		# add directory to log
		dir_files = {}
		dir_log = {'dir_order'=>dir_order, 'files'=>dir_files}
		log['dirs'][dir_path_display] = dir_log
		
		# skip if marked to do si
		if dir['skip']
			puts "*** skipping ***\n\n"
			return true
		end
		
		# change into test dir, run files
		Dir.chdir(dir['path']) do
			# initialize file_order
			file_order = 0
			
			# loop through files
			dir['settings']['files'].each do |file_path|
				# increment file order
				file_order = file_order + 1
				
				# run file
				success = TestMin.file_run(dir_files, file_path, file_order)
				
				# if failure, we're done
				if not success
					return false
				end
			end
		end
		
		# add a little room underneath dir
		puts
		
		# return true
		return true
	end
	#
	# dir_run
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# file_run
	#
	def TestMin.file_run(dir_files, file_path, file_order)
		# TestMin.hr(__method__.to_s)
		
		# TestMin.hr(file_path)
		puts file_path
		
		# add to dir files list
		file_log = {'file_order'=>file_order}
		dir_files[file_path] = file_log
		
		# debug objects
		debug_stdout = ''
		debug_stderr = ''
		
		# run file
		Open3.popen3('./' + file_path) do |stdin, stdout, stderr, thread|
			debug_stdout = stdout.read.chomp
			debug_stderr = stderr.read.chomp
		end
		
		# get results
		results = TestMin.parse_results(debug_stdout)
		
		# determine success
		if results.is_a?(Hash)
			# get success
			success = results.delete('testmin-success')
			
			# add other elements to details if any
			if results.any?
				file_log['details'] = results
			end
		else
			success = false
		end
		
		# if failure
		if not success
			# show file output
			puts
			TestMin.hr('title'=>TestMin.message('failure'), 'dash'=>'*')
			TestMin.hr('stdout')
			puts debug_stdout
			TestMin.hr('stderr')
			puts debug_stderr
			TestMin.hr('dash'=>'*')
			puts
			
			# add to file log
			file_log['stdout'] = debug_stdout
			file_log['stderr'] = debug_stderr
		end
		
		# return success
		return success
	end
	#
	# file_run
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# os_info
	#
	def TestMin.os_info(versions)
		os = versions['os'] = {}
		
		# kernel version
		os['version'] = `uname -v`
		os['version'] = os['version'].strip
		
		# kernel release
		os['release'] = `uname -r`
		os['release'] = os['release'].strip
	end
	#
	# os_info
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# versions
	#
	def TestMin.versions(log)
		# TestMin.hr(__method__.to_s)
		
		# initliaze versions hash
		versions = log['versions'] = {}
		
		# TestMin version
		versions['testmin'] = TestMin::VERSION
		
		# OS information
		TestMin.os_info(versions)
		
		# ruby version
		versions['ruby'] = RUBY_VERSION
	end
	#
	# versions
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# last_line
	#
	def TestMin.last_line(str)
		# TestMin.hr(__method__.to_s)
		
		# early exit: str is not a string
		if not str.is_a?(String)
			return nil
		end
		
		# split into lines
		lines = str.split(/[\n\r]/)
		
		# loop through lines
		lines.reverse.each { |line|
			# if non-blank line, return
			if line.match(/\S/)
					return line
			end
		}
		
		# didn't find non-blank, return nil
		return nil
	end
	#
	# last_line
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# parse_results
	#
	def TestMin.parse_results(stdout)
		# TestMin.hr(__method__.to_s)
		
		# get last line
		last_line = TestMin.last_line(stdout)
		
		# if we got a string
		if last_line.is_a?(String)
			if (last_line.match(/\A\s*\{/) and last_line.match(/\}\s*\z/))
				# attempt to parse
				begin
					rv = JSON.parse(last_line)
				rescue
					return nil
				end
				
				# should have gotten a hash
				if rv.is_a?(Hash)
					return rv
				end
			end
		end
		
		# the last line of stdout was not a TestMin results line, so return nil
		return nil
	end
	#
	# parse_results
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# get_results
	#
	def TestMin.get_results(stdout)
		# TestMin.hr(__method__.to_s)
		
		# get results hash
		results = parse_results(stdout)
		
		# if hash, check for results
		if results.is_a?(Hash)
			success = results['testmin-success']
			
			# if testmin-success is defined
			if (success.is_a?(TrueClass) || success.is_a?(FalseClass))
				return results
			end
		end
		
		# didn't get a results line, do return nil
		return nil
	end
	#
	# get_results
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# create_log
	#
	def TestMin.create_log()
		# initialize log object
		log = {}
		log['id'] = ('a'..'z').to_a.shuffle[0,20].join
		log['success'] = true
		log['messages'] = []
		log['dirs'] = {}
		
		# get project id if there is one
		if not TestMin.settings['project-id'].nil?
			log['project-id'] = TestMin.settings['project-id']
		end
		
		# get client id if there is one
		if not TestMin.settings['client-id'].nil?
			log['client-id'] = TestMin.settings['client-id']
		end
		
		# add system version info
		TestMin.versions(log)
		
		# return
		return log
	end
	#
	# create_log
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# hr
	#
	def TestMin.hr(opts={})
		# set opts from scalar or hash
		if opts.nil?
			opts = {}
		elsif not opts.is_a?(Hash)
			opts = {'title'=>opts}
		end
		
		# set default dash
		opts = {'dash'=>'-', 'title'=>''}.merge(opts)
		
		# output
		if opts['title'] == ''
			puts opts['dash'] * HR_LENGTH
		else
			puts (opts['dash'] * 3) + ' ' + opts['title'] + ' ' + (opts['dash'] * (HR_LENGTH - 5 - opts['title'].length))
		end
	end
	#
	# hr
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# devexit
	#
	def TestMin.devexit()
		# TestMin.hr(__method__.to_s)
		puts "\n", '[devexit]'
		exit
	end
	#
	# devexit
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# randstr
	#
	def TestMin.randstr()
		return (('a'..'z').to_a + (0..9).to_a).shuffle[0,8].join
	end
	#
	# randstr
	#---------------------------------------------------------------------------
		
	
	#---------------------------------------------------------------------------
	# run_tests
	#
	def TestMin.run_tests
		# TestMin.hr(__method__.to_s)
		
		# initialize log object
		log = TestMin.create_log()
		
		# run tests, output results
		results = TestMin.process_tests(log)
		
		# verbosify
		puts()
		TestMin.hr 'dash'=>'=', 'title'=>TestMin.message('finished-testing')
		
		# output succsss|failure
		if results
			puts TestMin.message('test-success')
		else
			puts TestMin.message('test-failure')
		end
		
		# bottom of section
		TestMin.hr 'dash'=>'='
		puts
		
		# send log to TestMin service if necessary
		puts
		TestMin.submit_results(log)
	end
	#
	# run_tests
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# settings
	#
	def TestMin.settings()
		# TestMin.hr(__method__.to_s)
		
		# if @settings is nil, initalize settings
		if @settings.nil?
			# if config file exists, merge it with
			if File.exist?(GLOBAL_CONFIG_FILE)
				config = JSON.parse(File.read(GLOBAL_CONFIG_FILE))
				@settings = DefaultSettings.deep_merge(config)
			end
			
			# if @settings is still nil, just clone DefaultSettings
			if @settings.nil?
				@settings = DefaultSettings.clone()
			end
		end
		
		# return settings
		return @settings
	end
	#
	# settings
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# yes_no
	#
	def TestMin.yes_no(prompt)
		# TestMin.hr(__method__.to_s)
		
		# output prompt
		print prompt
		
		# get response until it's y or n
		loop do
			# output prompt
			print TestMin.message('yn') + ' '
			
			# get response
			response = $stdin.gets.chomp
			
			# normalize response
			response = response.gsub(/\A\s+/, '')
			response = response.downcase
			response = response[0,1]
			
			# if we got one of the matching letters, we're done
			if response == 'y'
				return true
			elsif response == 'n'
				return false
			end
		end
		
		# return
		# should never get to this point
		return response
	end
	#
	# yes_no
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# submit_ask
	#
	def TestMin.submit_ask()
		# TestMin.hr(__method__.to_s)
		
		# get prompt
		prompt = TestMin.message(
			'submit-request',
			'fields' => TestMin.settings['submit'],
			'root' => TestMin.settings['submit']['messages'],
		)
		
		# get results of user prompt
		return TestMin.yes_no(prompt)
	end
	#
	# submit_ask
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# email_ask
	#
	def TestMin.email_ask(results)
		# TestMin.hr(__method__.to_s)
		
		# get prompt
		prompt = TestMin.message(
			'email-request',
			'fields' => TestMin.settings['submit'],
			'root' => TestMin.settings['submit']['messages'],
		)
		
		# add a little horizontal space
		puts
		
		# if the user wants to add email
		if not TestMin.yes_no(prompt)
			return true
		end
		
		# build prompt for getting email
		prompt = TestMin.message('email-prompt')
		
		# get email
		email = TestMin.get_line(prompt)
		
		# ensure results has private element
		if not results['private'].is_a?(Hash)
			results['private'] = {}
		end
		
		# add to private
		results['private']['email'] = email
		
		# done
		return true
	end
	#
	# email_ask
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# get_line
	#
	def TestMin.get_line(prompt)
		# TestMin.hr(__method__.to_s)
		
		# loop until we get a line with some content
		loop do
			# get response
			print prompt + ': '
			response = $stdin.gets.chomp
			
			# if line has content, collapse and return it
			if response.match(/\S/)
				response = collapse(response)
				return response
			end
		end
	end
	#
	# get_line
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# collapse
	#
	def self.collapse(str)
		# TestMin.hr(__method__.to_s)
		
		# only process defined strings
		if str.is_a?(String) and (not str.nil?())
			str = str.gsub(/^[ \t\r\n]+/, '')
			str = str.gsub(/[ \t\r\n]+$/, '')
			str = str.gsub(/[ \t\r\n]+/, ' ')
		end
		
		# return
		return str
	end
	#
	# collapse
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# submit_results
	# TODO: Need to generalize this routine for submitting to other test
	# logging sites.
	#
	def TestMin.submit_results(results)
		# TestMin.hr(__method__.to_s)
		
		# load settings
		settings = TestMin.settings
		
		# if not set to submit, nothing to do
		if not settings['submit']['request']
			return true
		end
		
		# check if the user wants to submit
		if not TestMin.submit_ask()
			return true
		end
		
		# get email address
		TestMin.email_ask(results)
		
		# load some modules
		require "net/http"
		require "uri"
		
		# get site settings
		site = settings['submit']
		
		# verbosify
		puts TestMin.message('submit-hold')
		
		# post
		url = URI.parse(site['url'])
		params = {'test-results': JSON.generate(results)}
		response = Net::HTTP.post_form(url, params)
		
		# check results
		if response.is_a?(Net::HTTPOK)
			# parse json response
			# response = response.body.gsub(/\A.*\n\n/, '')
			response = JSON.parse(response.body)
			
			# output success or failure
			if response['success']
				puts TestMin.message('submit-success')
			else
				# initialize error array
				errors = []
				
				# build array of errors
				response['errors'].each do |error|
					errors.push error['id']
				end
				
				# output message
				puts TestMin.message('submit-failure', {'errors'=>errors.join(', ')})
			end
		else
			raise "Failed at submitting results. I have not yet implemented giving a good message for this situation yet."
		end
		
		# return success
		# NOTE: returning success only indicates that this function ran all the
		# way through, not that the results were successfully submitted.
		return true
	end
	#
	# submit_results
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# message
	#
	def TestMin.message(message_id, opts={})
		# TestMin.hr(__method__.to_s)
		
		# default options
		opts = {'fields'=>{}, 'root'=>TestMin.settings['messages']}.merge(opts)
		fields = opts['fields']
		root = opts['root']
		
		# TESTING
		# @human_languages = ['xx']
		
		# loop through languages
		@human_languages.each do |language|
			# if the template exists in this language
			if root[language].is_a?(Hash)
				# get tmeplate
				template = root[language][message_id]
				
				# if we actually got a template, process it
				if template.is_a?(String)
					# field substitutions
					fields.each do |key, val|
						# TODO: need to meta quote the key name
						template = template.gsub(/\[\[\s*#{key}\s*\]\]/i, val.to_s)
					end
					
					# return
					return template
				end
			end
		end
		
		# we didn't find the template
		raise 'do not find message with message id "' + message_id + '"'
	end
	#
	# message
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# process_tests
	# This routine does the actual job of running the tests. It returns false
	# when an error is reached. If it gets to the end it returns true.
	#
	def TestMin.process_tests(log)
		# TestMin.hr(__method__.to_s)
		
		# get settings
		# settings = TestMin.load_settings()
		
		# create test_id
		ENV['testmin_test_id'] = TestMin.randstr
		
		# initialize dirs array
		run_dirs = []
		
		# get list of directories
		Dir.glob('./*/').each do |dir_path|
			if not TestMin.dir_settings(run_dirs, dir_path)
				return false
			end
		end
		
		# sort on dir-order setting
		run_dirs = run_dirs.sort { |x, y| x['settings']['dir-order'] <=> y['settings']['dir-order'] }
		
		# check each directory settings
		run_dirs.each do |dir|
			if not TestMin.dir_check(log, dir)
				return false
			end
		end
		
		# initialize dir_order
		dir_order = 0
		
		# loop through directories
		run_dirs.each do |dir|
			# incremement dir_order
			dir_order = dir_order + 1
			
			# run directory
			if not TestMin.dir_run(log, dir, dir_order)
				return false
			end
		end
		
		# success
		return true
	end
	#
	# process_tests
	#---------------------------------------------------------------------------
end
#
# TestMin
################################################################################


################################################################################
# Hash
#
class ::Hash
	def deep_merge(second)
		merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
		self.merge(second, &merger)
	end
end
#
# Hash
################################################################################


#---------------------------------------------------------------------------
# run tests
#
if caller().length <= 0
	TestMin.run_tests()
end
#
# run tests
#---------------------------------------------------------------------------
