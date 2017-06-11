#!/usr/bin/ruby -w
require 'json'
require 'fileutils'
require 'open3'
require 'benchmark'
require 'timeout'
require 'optparse'


# Testmin is a simple, minimalist testing framework. Testmin is on GitHub at
# https://github.com/mikosullivan/Testmin

# note clear as done
# NOTE: This setting is a leftover from an earlier version of Testmin. For now
# just leave this line as it is. It won't get in the way of how Testmin works.
ENV['clear_done'] = '1'



################################################################################
# Testmin
#
module Testmin
	
	# Testmin version
	VERSION = '0.0.3'
	
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
			'email' => false,
			'comments' => false,
			
			'site' => {
				'root' => 'https://testmin.idocs.com',
				'submit' => '/submit',
				'project' => '/project',
				'entry' => '/entry',
				'title' => 'Idocs Testmin',
			},
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
				'add-comments' => 'Add your comments here.',
				
				# request to submit results
				'submit-request' => <<~TEXT,
				May this script submit these test results to [[title]]?
				The results will be submitted to the [[title]] service
				where they will be publicly available. In addition to the
				test results, the only information about your system will be
				the operating system and version, the version of Ruby, and
				the version of Testmin.
				TEXT
				
				# request to add email address
				'email-request' => <<~TEXT,
				Would you like to send your email address? Your email will
				not be publicly displayed. You will only be contacted to
				about this project.
				TEXT
				
				# request to add email address
				'comments-request' => <<~TEXT,
				Would you like to add some comments? Your comments will not
				be publicly displayed.
				TEXT
				
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
	def Testmin.done(opts = {})
		# Testmin.hr(__method__.to_s)
		
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
	def Testmin.devshortcut()
		@devshortcut_called = true
		return false
	end
	#
	# devshortcut
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# dir_settings
	#
	def Testmin.dir_settings(log, run_dirs, dir_path)
		# Testmin.hr(dir_path)
		
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
				dir_settings = JSON.parse(File.read(settings_path))
				dir['settings'] = dir['settings'].merge(dir_settings)
			rescue Exception => e
				# note error in directory log
				dir['success'] = false
				dir['errors'] = [
					{
						'id'=>'Testmin.dir.json-parse-error',
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
			dir['settings']['files'] = {}
		else
			if not dir['settings']['files'].is_a?(Hash)
				raise 'files setting is not an hash for ' + dir_path
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
	def Testmin.dir_check(log, dir)
		# Testmin.hr(__method__.to_s)
		
		# array of files to add to files hash
		add_files = []
		
		# change into test dir
		Dir.chdir(dir['path']) do
			# loop through files in directory
			Dir.glob('*').each do |file_path|
				# skip dev files
				if file_path.match(/\Adev\./)
					next
				end
				
				# must be executable
				if not File.executable?(file_path)
					next
				end
				
				# must be file, not directory
				if not File.file?(file_path)
					next
				end
				
				# if file is not in files hash, add to array of unlisted files
				if not dir['settings']['files'].key?(file_path)
					add_files.push(file_path)
				end
			end
		end
		
		# add files not listed in config file
		add_files.each do |file_path|
			dir['settings']['files'][file_path] = true
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
	def Testmin.dir_run(log, dir, dir_order)
		# verbosify
		dir_path_display = dir['path']
		dir_path_display = dir_path_display.sub(/\A\.\//, '')
		Testmin.hr('title'=>dir_path_display, 'dash'=>'=')
		
		# initialize success to true
		success = true
		
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
			
			# run test files in directory
			mark = Benchmark.measure {
				# loop through files
				dir['settings']['files'].each do |file_path, file_settings|
					# increment file order
					file_order = file_order + 1
					
					# run file
					success = Testmin.file_run(dir_files, file_path, file_settings, file_order)
					
					# if failure, we're done
					if not success
						break
					end
				end
			}
			
			# note run-time
			dir_log['run-time'] = mark.real
		end
		
		# add a little room underneath dir
		puts
		
		# return success
		return success
	end
	#
	# dir_run
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# get_file_settings
	#
	def Testmin.get_file_settings(file_settings)
		# Testmin.hr(__method__.to_s)
		
		# if false
		if file_settings.is_a?(FalseClass)
			return nil
		end
		
		# if not a hash, make it one
		if not file_settings.is_a?(Hash)
			file_settings = {}
		end
		
		# set default file settings
		file_settings = {'timeout'=>Testmin.settings['timeout']}.merge(file_settings)
		
		# return
		return file_settings
	end
	#
	# get_file_settings
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# file_run
	# TODO: The code in this routine gets a litle spaghettish. Need to clean it
	# up.
	#
	def Testmin.file_run(dir_files, file_path, file_settings, file_order)
		# Testmin.hr(__method__.to_s)
		
		# get file settings
		file_settings = Testmin.get_file_settings(file_settings)
		
		# if file_settings is nil, don't run this file
		if file_settings.nil?
			return true
		end
		
		# verbosify
		puts file_path
		
		# add to dir files list
		file_log = {'file_order'=>file_order}
		dir_files[file_path] = file_log
		
		# debug objects
		debug_stdout = ''
		debug_stderr = ''
		completed = true
		
		# run file with benchmark
		mark = Benchmark.measure {
			# run file with timeout
			Open3.popen3('./' + file_path) do |stdin, stdout, stderr, thread|
				begin
					Timeout::timeout(file_settings['timeout']) {
						debug_stdout = stdout.read.chomp
						debug_stderr = stderr.read.chomp
					}
				rescue
					Process.kill('KILL', thread.pid)
					file_log['timed-out'] = Testmin.settings['timeout']
					completed = false
				rescue
					completed = false
				end
			end
		}
		
		# if completed
		if completed
			# get results
			results = Testmin.parse_results(debug_stdout)
			
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
		
		# else not completed
		else
			success = false
		end
		
		# add success and run time
		file_log['success'] = success
		file_log['run-time'] = mark.real
		
		# if failure
		if not success
			# show file output
			puts
			Testmin.hr('title'=>Testmin.message('failure'), 'dash'=>'*')
			Testmin.hr('stdout')
			puts debug_stdout
			Testmin.hr('stderr')
			puts debug_stderr
			Testmin.hr('dash'=>'*')
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
	def Testmin.os_info(versions)
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
	def Testmin.versions(log)
		# Testmin.hr(__method__.to_s)
		
		# initliaze versions hash
		versions = log['versions'] = {}
		
		# Testmin version
		versions['Testmin'] = Testmin::VERSION
		
		# OS information
		Testmin.os_info(versions)
		
		# ruby version
		versions['ruby'] = RUBY_VERSION
	end
	#
	# versions
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# last_line
	#
	def Testmin.last_line(str)
		# Testmin.hr(__method__.to_s)
		
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
	def Testmin.parse_results(stdout)
		# Testmin.hr(__method__.to_s)
		
		# get last line
		last_line = Testmin.last_line(stdout)
		
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
		
		# the last line of stdout was not a Testmin results line, so return nil
		return nil
	end
	#
	# parse_results
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# get_results
	#
	def Testmin.get_results(stdout)
		# Testmin.hr(__method__.to_s)
		
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
	def Testmin.create_log()
		# initialize log object
		log = {}
		log['id'] = ('a'..'z').to_a.shuffle[0,20].join
		log['success'] = true
		log['messages'] = []
		log['dirs'] = {}
		log['private'] = {}
		
		# get project id if there is one
		if not Testmin.settings['project-id'].nil?
			log['project-id'] = Testmin.settings['project-id']
		end
		
		# get client id if there is one
		if not Testmin.settings['client-id'].nil?
			log['client-id'] = Testmin.settings['client-id']
		end
		
		# add system version info
		Testmin.versions(log)
		
		# return
		return log
	end
	#
	# create_log
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# hr
	#
	def Testmin.hr(opts={})
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
	def Testmin.devexit()
		# Testmin.hr(__method__.to_s)
		puts "\n", '[devexit]'
		exit
	end
	#
	# devexit
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# randstr
	#
	def Testmin.randstr()
		return (('a'..'z').to_a + (0..9).to_a).shuffle[0,8].join
	end
	#
	# randstr
	#---------------------------------------------------------------------------
		
	
	#---------------------------------------------------------------------------
	# val_to_bool
	#
	def Testmin.val_to_bool(t)
		# Testmin.hr(__method__.to_s)
		
		# String
		if t.is_a?(String)
			t = t.downcase
			t = t[0,1]
			
			# n, f, 0, or empty string
			if ['n', 'f', '0', ''].include? t
				return false
			end
			
			# anything else return true
			return true
		end
		
		# anything else return !!
		return !!t
	end
	#
	# val_to_bool
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# set_cmd_opts
	#
	def Testmin.set_cmd_opts()
		# Testmin.hr(__method__.to_s)
		
		# initialize command line options
		cmd_opts  = {}
		
		# get command line options
		OptionParser.new do |opts|
			
			# submit
			opts.on("-sSUBMIT", "--submit=SUBMIT", 'If the results should be submitted to the Testmin service') do |bool|
				bool = Testmin.val_to_bool(bool)
				
				# if true, automatically submit results, else don't even ask
				if bool
					Testmin.settings['submit']['auto-submit'] = true
				else
					Testmin.settings['submit']['request'] = false
				end
			end
		end.parse!
		
		# return
		return cmd_opts
	end
	#
	# set_cmd_opts
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# run_tests
	#
	def Testmin.run_tests()
		# Testmin.hr(__method__.to_s)
		
		# get command line options
		Testmin.set_cmd_opts()
		
		# initialize log object
		log = Testmin.create_log()
		
		# run tests, output results
		results = Testmin.process_tests(log)
		
		# verbosify
		puts()
		Testmin.hr 'dash'=>'=', 'title'=>Testmin.message('finished-testing')
		
		# output succsss|failure
		if results
			puts Testmin.message('test-success')
		else
			puts Testmin.message('test-failure')
		end
		
		# bottom of section
		Testmin.hr 'dash'=>'='
		puts
		
		# send log to Testmin service if necessary
		puts
		Testmin.submit_results(log)
	end
	#
	# run_tests
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# settings
	#
	def Testmin.settings()
		# Testmin.hr(__method__.to_s)
		
		# if @settings is nil, initalize settings
		if @settings.nil?
			# if config file exists, merge it with
			if File.exist?(GLOBAL_CONFIG_FILE)
				# read in configuration file if one exists
				config = JSON.parse(File.read(GLOBAL_CONFIG_FILE))
				
				# merge with default settings
				@settings = DefaultSettings.deep_merge(config)
				
				# turn off auto-submit, that setting can only be set from the
				# command line
				@settings.delete('auto-submit')
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
	def Testmin.yes_no(prompt)
		# Testmin.hr(__method__.to_s)
		
		# output prompt
		print prompt
		
		# get response until it's y or n
		loop do
			# output prompt
			print Testmin.message('yn') + ' '
			
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
	def Testmin.submit_ask()
		# Testmin.hr(__method__.to_s)
		
		# get submit settings
		submit = Testmin.settings['submit']
		
		# if auto-submit, return true
		if (not submit['auto-submit'].nil?) and (submit['auto-submit'])
			return true
		end
		
		# get prompt
		prompt = Testmin.message(
			'submit-request',
			'fields' => submit,
		)
		
		# get results of user prompt
		return Testmin.yes_no(prompt)
	end
	#
	# submit_ask
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# email_ask
	#
	def Testmin.email_ask(results)
		# Testmin.hr(__method__.to_s)
		
		# if not set to submit email, nothing to do
		if not settings['submit']['email']
			return true
		end
		
		# get prompt
		prompt = Testmin.message(
			'email-request',
			'fields' => Testmin.settings['submit'],
		)
		
		# add a little horizontal space
		puts
		
		# if the user wants to add email
		if not Testmin.yes_no(prompt)
			return true
		end
		
		# build prompt for getting email
		prompt = Testmin.message('email-prompt')
		
		# get email
		email = Testmin.get_line(prompt)
		
		# add to private
		results['private']['email'] = email
		
		# done
		return true
	end
	#
	# email_ask
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# comments_ask
	#
	def Testmin.comments_ask(results)
		# Testmin.hr(__method__.to_s)
		
		# early exit: no editor
		if ENV['EDITOR'].nil?
			return
		end
		
		# if not set to submit comments, nothing to do
		if not settings['submit']['comments']
			return true
		end
		
		# get prompt
		prompt = Testmin.message(
			'comments-request',
			'fields' => Testmin.settings['submit'],
		)
		
		# add a little horizontal space
		puts
		
		# if the user wants to add email
		if not Testmin.yes_no(prompt)
			return true
		end
		
		# build prompt for getting email
		prompt = Testmin.message('add-comments')
		
		# create comments file
		path = '/tmp/Testmin-comments-' + Testmin.randstr + '.txt'
		
		# create file
		File.open(path, 'w') { |file|
			file.write(prompt + "\n");
		}
		
		# open editor
		system(ENV['EDITOR'], path)
		
		# read in file
		results['private']['comments'] = File.read(path)
		
		# delete file
		if File.exist?(path)
			File.delete(path)
		end
		
		# done
		return true
	end
	#
	# comments_ask
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# get_line
	#
	def Testmin.get_line(prompt)
		# Testmin.hr(__method__.to_s)
		
		# loop until we get a line with some content
		loop do
			# get response
			print prompt + ': '
			response = $stdin.gets.chomp
			
			# if line has content, collapse and return it
			if response.match(/\S/)
				response = Testmin.collapse(response)
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
	def Testmin.collapse(str)
		# Testmin.hr(__method__.to_s)
		
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
	def Testmin.submit_results(results)
		# Testmin.hr(__method__.to_s)
		
		# load settings
		settings = Testmin.settings
		
		# if not set to submit, nothing to do
		if not settings['submit']['request']
			return true
		end
		
		# check if the user wants to submit the test results
		if not Testmin.submit_ask()
			return true
		end
		
		# get email address
		Testmin.email_ask(results)
		
		# get comments
		Testmin.comments_ask(results)
		
		# load some modules
		require "net/http"
		require "uri"
		
		# get site settings
		site = settings['submit']['site']
		
		# verbosify
		puts Testmin.message('submit-hold')
		
		# post
		url = URI.parse(site['root'] + site['submit'])
		params = {'test-results': JSON.generate(results)}
		response = Net::HTTP.post_form(url, params)
		
		# check results
		if response.is_a?(Net::HTTPOK)
			# parse json response
			# response = response.body.gsub(/\A.*\n\n/, '')
			response = JSON.parse(response.body)
			
			# output success or failure
			if response['success']
				puts Testmin.message('submit-success')
			else
				# initialize error array
				errors = []
				
				# build array of errors
				response['errors'].each do |error|
					errors.push error['id']
				end
				
				# output message
				puts Testmin.message('submit-failure', {'errors'=>errors.join(', ')})
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
	def Testmin.message(message_id, opts={})
		# Testmin.hr(__method__.to_s)
		
		# default options
		opts = {'fields'=>{}, 'root'=>Testmin.settings['messages']}.merge(opts)
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
	def Testmin.process_tests(log)
		# Testmin.hr(__method__.to_s)
		
		# get settings
		# settings = Testmin.load_settings()
		
		# create test_id
		ENV['Testmin_test_id'] = Testmin.randstr
		
		# initialize dirs array
		run_dirs = []
		
		# get list of directories
		Dir.glob('./*/').each do |dir_path|
			if not Testmin.dir_settings(log, run_dirs, dir_path)
				return false
			end
		end
		
		# sort on dir-order setting
		run_dirs = run_dirs.sort { |x, y| x['settings']['dir-order'] <=> y['settings']['dir-order'] }
		
		# check each directory settings
		run_dirs.each do |dir|
			if not Testmin.dir_check(log, dir)
				return false
			end
		end
		
		# initialize dir_order
		dir_order = 0
		
		# initialize success to true
		success = true
		
		# loop through directories
		mark = Benchmark.measure {
			run_dirs.each do |dir|
				# incremement dir_order
				dir_order = dir_order + 1
				
				# run directory
				success = Testmin.dir_run(log, dir, dir_order)
				
				# if not success, we're done looping
				if not success
					break
				end
			end
		}
		
		# note run time
		log['run-time'] = mark.real
		
		# success
		return success
	end
	#
	# process_tests
	#---------------------------------------------------------------------------
end
#
# Testmin
################################################################################


################################################################################
# Array
#
class ::Array
	def show()
		return '[' + self.join('|') + ']'
	end
	
	def Array.as_a(el)
		if el.is_a?(Array)
			return el
		else
			return [el]
		end
	end
end
#
# Array
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
# run tests if this script was not loaded by another script
#
if caller().length <= 0
	Testmin.run_tests()
end
#
# run tests if this script was not loaded by another script
#---------------------------------------------------------------------------
