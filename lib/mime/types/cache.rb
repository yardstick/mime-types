# -*- ruby encoding: utf-8 -*-

class MIME::Types
  # Caching of MIME::Types registries is advisable if you will be loading
  # the default registry relatively frequently. With the class methods on
  # MIME::Types::Cache, any MIME::Types registry can be marshaled quickly
  # and easily.
  #
  # The cache is invalidated on a per-version basis; a cache file for
  # version 2.0 will not be reused with version 2.0.1.
  Cache = Struct.new(:version, :data)

  class << Cache
    # Attempts to load the cache from the file provided as a parameter or in
    # the environment variable +RUBY_MIME_TYPES_CACHE+. Returns +nil+ if the
    # file does not exist, if the file cannot be loaded, or if the data in
    # the cache version is different than this version.
    def load(cache_file = nil)
      cache_file = cache_file || ENV['RUBY_MIME_TYPES_CACHE']
      return nil unless cache_file and File.exists?(cache_file)

      cache = Marshal.load(File.read(cache_file))
      if cache.version == MIME::Types::VERSION
        Marshal.load(cache.data)
      else
        warn "Could not load MIME::Types cache: invalid version"
        nil
      end
    rescue => e
      warn "Could not load MIME::Types cache: #{e}"
      return nil
    end

    # Attempts to save the types provided to the cache file provided.
    #
    # If +types+ is not provided or is +nil+, the cache will contain the
    # current MIME::Types default registry.
    #
    # If +cache_file+ is not provided or is +nil+, the cache will be written
    # to the file specified in the environment variable
    # +RUBY_MIME_TYPES_CACHE+. If there is no cache file specified either
    # directly or through the environment, this method will return +nil+
    def save(types = nil, cache_file = nil)
      cache_file = cache_file || ENV['RUBY_MIME_TYPES_CACHE']
      return nil unless cache_file

      types      = types || MIME::Types.send(:__types__)

      File.open(cache_file, 'wb') do |f|
        f.write(Marshal.dump(new(types.data_version, Marshal.dump(types))))
      end
    end
  end

  # MIME::Types requires a container Hash with a default values for keys
  # resulting in an empty array (<tt>[]</tt>), but this cannot be dumped
  # through Marshal because of the presence of that default Proc. This class
  # exists solely to satisfy that need.
  class Container < Hash # :nodoc:
    def initialize
      default_proc = lambda { |h, k| h[k] = [] }
      super(&default_proc)
    end

    def marshal_dump
      {}.merge(self)
    end

    def marshal_load(hash)
      self.merge!(hash)
    end
  end
end
