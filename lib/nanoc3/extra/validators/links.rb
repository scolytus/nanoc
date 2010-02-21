# encoding: utf-8

module Nanoc3::Extra::Validators

  # A validator that verifies that all links (`<a href="…">…</a>`) point to a
  # location that exists.
  class Links

    # @param [String] dir The directory that will be searched for HTML files
    #   to validate
    #
    # @param [Array<String>] index_filenames An array of index filenames that
    #   will be appended to URLs by web servers if a directory is requested
    #   instead of a file
    #
    # @option params [Boolean] :internal True if internal links should be
    #   checked; false if they should not
    #
    # @option params [Boolean] :external True if external links should be
    #   checked; false if they should not
    def initialize(dir, index_filenames, params={})
      @dir              = dir
      @index_filenames  = index_filenames
      @include_internal = params.has_key?(:internal) && params[:internal]
      @include_external = params.has_key?(:external) && params[:external]
    end

    # Starts the validator. The results will be printed to stdout.
    #
    # @return [void]
    def run
      require 'nokogiri'

      links = all_broken_hrefs
      if links.empty?
        puts "No broken links found!"
      else
        links.each_pair do |href, origins|
          puts "Broken link: #{href} -- referenced from:"
          origins.each do |origin|
            puts "    #{origin}"
          end
          puts
        end
      end
    end

  private

    def all_broken_hrefs
      broken_hrefs = {}

      # Validate internal hrefs
      external_hrefs = {}
      all_hrefs_per_filename.each_pair do |filename, hrefs|
        hrefs.each do |href|
          if is_external_href?(href)
            external_hrefs[href] ||= []
            external_hrefs[href] << filename
          elsif @include_internal && !is_valid_internal_href?(href, filename)
            broken_hrefs[href] ||= []
            broken_hrefs[href] << filename
          end
        end
      end

      # Validate external hrefs
      if @include_external
        external_hrefs.each_pair do |href, filenames|
          if !is_valid_external_href?(href)
            broken_hrefs[href] = filenames
          end
        end
      end

      broken_hrefs
    end

    def all_files
      Dir[@dir + '/**/*.html']
    end

    def all_hrefs_per_filename
      hrefs = {}
      all_files.each do |filename|
        hrefs[filename] ||= all_hrefs_in_file(filename)
      end
      hrefs
    end

    def all_hrefs_in_file(filename)
      doc = Nokogiri::HTML(::File.read(filename))
      doc.css('a').map { |l| l[:href] }.compact
    end

    def is_external_href?(href)
      !!(href =~ %r{^[a-z\-]+:})
    end

    def is_valid_internal_href?(href, origin)
      # Skip hrefs that point to self
      # FIXME this is ugly and won’t always be correct
      return true if href == '.'

      # Remove target
      path = href.sub(/#.*$/, '')
      return true if path.empty?

      # Make absolute
      if path[0, 1] == '/'
        path = @dir + path
      else
        path = ::File.expand_path(path, ::File.dirname(origin))
      end

      # Check whether file exists
      return true if File.file?(path)

      # Check whether directory with index file exists
      return true if File.directory?(path) && @index_filenames.any? { |fn| File.file?(File.join(path, fn)) }

      # Nope :(
      return false
    end

    def is_valid_external_href?(href)
      require 'net/http'
      require 'uri'

      # Parse
      uri = URI.parse(href)

      # Skip non-HTTP URLs
      return true if uri.scheme != 'http'

      # Make call
      res = nil
      p uri
      begin
        path = (uri.path.nil? || uri.path.empty? ? '/' : uri.path)
        req = Net::HTTP::Head.new(path)
        res = Net::HTTP.start(uri.host, uri.port) { |h| h.request(req) }
      rescue => e
        p e
        return false
      end
      p res
      puts

      # Check
      res.is_a?(Net::HTTPSuccess)
    end

  end

end
