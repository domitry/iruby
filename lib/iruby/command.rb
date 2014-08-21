require 'shellwords'
require 'fileutils'

module IRuby
  class Command
    PLATFORM_WIN = RUBY_PLATFORM.downcase =~ /mswin(?!ce)|mingw|cygwin/
    IRUBYDIR = (PLATFORM_WIN ? '~/iruby' : '~/.config/iruby')

    def initialize(args)
      @args = args
    end

    def run
      raise 'Use --iruby-dir instead of --ipython-dir!' unless @args.grep(/\A--ipython-dir=.*\Z/).empty?

      if @args.first == 'kernel'
        run_kernel
      else
        run_ipython
      end
    end

    private

    def run_kernel
      raise(ArgumentError, 'Not enough arguments to the kernel') if @args.size < 2 || @args.size > 4
      config_file, boot_file, working_dir = @args[1..-1]
      Dir.chdir(working_dir) if working_dir
      require boot_file if boot_file
      require 'iruby'
      Kernel.new(config_file).run
    rescue Exception => ex
      STDERR.puts "Kernel died: #{ex.message}\n#{ex.backtrace.join("\n")}"
      raise
    end

    def check_version
      required = '1.2.0'
      version = `ipython --version`.chomp
      if version < required
        STDERR.puts "Your IPython version #{version} is too old, at least #{required} is required"
        exit 1
      end
    end

    def run_ipython
      check_version

      dir = @args.grep(/\A--iruby-dir=.*\Z/)
      @args -= dir
      dir = dir.last.to_s.sub(/\A--profile=/, '')
      dir = ENV['IRUBYDIR'] || IRUBYDIR if dir.empty?
      dir = File.expand_path(dir)
      ENV['IPYTHONDIR'] = dir

      if @args.size == 3 && @args[0] == 'profile' && @args[1] == 'create'
        profile = @args[2]
      else
        profile = @args.grep(/\A--profile=.*\Z/).last.to_s.sub(/\A--profile=/, '')
        profile = 'default' if profile.empty?
      end

      create_profile(dir, profile)

      # We must use the console to launch the whole 0MQ-client-server stack
      @args = %w(console --no-banner) + @args if @args.first.to_s !~ /\A\w+\Z/

      Kernel.exec('ipython', *@args)
    end

    def create_profile(dir, profile)
      profile_dir = File.join(dir, "profile_#{profile}")
      unless File.directory?(profile_dir)
        puts "Creating profile directory #{profile_dir}"
        `ipython profile create #{Shellwords.escape profile}`
      end

      kernel_cmd = []
      kernel_cmd << ENV['BUNDLE_BIN_PATH'] << 'exec' if ENV['BUNDLE_BIN_PATH']

      if PLATFORM_WIN
        files = [RbConfig.ruby, File.expand_path("../../../bin/iruby", __FILE__)].map{|path| path.gsub('/', '\\\\\\')}
        kernel_cmd += files + ['kernel' , '{connection_file}']
      elsif
        kernel_cmd += [File.expand_path($0), 'kernel', '{connection_file}']
      end

      kernel_cmd = "c.KernelManager.kernel_cmd = #{kernel_cmd.inspect}"
      Dir[File.join(profile_dir, '*_config.py')].each do |path|
        content = File.read(path)
        content << kernel_cmd unless content.gsub!(/^c\.KernelManager\.kernel_cmd.*$/, kernel_cmd)
        File.open(path, 'w') {|f| f.write(content) }
      end

      static_dir = File.join(profile_dir, 'static')
      target_dir = File.join(File.dirname(__FILE__), 'static')
      if PLATFORM_WIN
        if File.exist? static_dir
          if ['custom.css', 'custom.js'].any? do |name|
              dst = File.expand_path('./custom/' + name, target_dir).gsub('/', '\\')
              src = File.expand_path('./custom/' + name, static_dir).gsub('/', '\\')
              !FileUtils.cmp(src, dst)
            end
            src = File.expand_path('..', static_dir)
            FileUtils.cp_r(target_dir, src)
          end
        end
      elsif
        unless (File.readlink(static_dir) rescue nil) == target_dir
          FileUtils.rm_rf(static_dir) rescue nil
          begin
            FileUtils.ln_sf(target_dir, static_dir)
          rescue => ex
            STDERR.puts "Could not create directory #{static_dir}: #{ex.message}"
          end
        end
      end
    end
  end
end
