# -*- ruby encoding: utf-8 -*-

require 'mime/types/loader_path'

# This class is responsible for initializing the MIME::Types registry from
# the data files supplied with the mime-types library.
#
# The Loader will use one of the following paths:
# 1.  The +path+ provided in its constructor argument;
# 2.  The value of ENV['RUBY_MIME_TYPES_DATA']; or
# 3.  The value of MIME::Types::Loader::PATH.
#
# When #load is called, the +path+ will be searched recursively for all YAML
# (.yml or .yaml) files. By convention, there is one file for each media type
# (application.yml, audio.yml, etc.), but this is not required.
#
#
class MIME::Types::Loader
  # The path that will be read for the MIME::Types files.
  attr_reader :path
  # The MIME::Types container instance that will be loaded. If not provided
  # at initialization, a new MIME::Types instance will be constructed.
  attr_reader :container

  # Creates a Loader object that can be used to load MIME::Types registries
  # into memory, using YAML, JSON, or v1 registry format loaders.
  def initialize(path = nil, container = nil)
    path       = path || ENV['RUBY_MIME_TYPES_DATA'] ||
      MIME::Types::Loader::PATH
    @path      = File.expand_path(File.join(path, '**'))
    @container = container || MIME::Types.new
  end

  # Loads a MIME::Types registry from JSON files (<tt>*.json</tt>)
  # recursively found in +path+.
  #
  # It is expected that the JSON objects will be an array of hash objects.
  # The JSON format is the registry format for the MIME types registry
  # shipped with the mime-types library.
  #
  # This method is aliased to #load.
  def load_json
    Dir[json_path].sort.each do |f|
      types = self.class.load_from_json(f).map { |type|
        MIME::Type.new(type)
      }
      container.add(*(types << :silent))
    end
    container
  end
  alias_method :load, :load_json

  # Loads a MIME::Types registry from files found in +path+ that are in the
  # v1 data format. The file search for this will exclude both JSON
  # (<tt>*.json</tt>) and YAML (<tt>*.yml</tt> or <tt>*.yaml</tt>) files.
  #
  # This method has been deprecated.
  def load_v1
    MIME.deprecated(self.class, __method__)
    Dir[v1_path].sort.each do |f|
      next if f =~ /\.ya?ml$|\.json$/
      container.add(self.class.load_from_v1(f), true)
    end
    container
  end

  class << self
    # Loads the default MIME::Type registry.
    def load
      new.load
    end

    # Build the type list from a file in the format:
    #
    #   [*][!][os:]mt/st[<ws>@ext][<ws>:enc][<ws>'url-list][<ws>=docs]
    #
    # == *
    # An unofficial MIME type. This should be used if and only if the MIME type
    # is not properly specified (that is, not under either x-type or
    # vnd.name.type).
    #
    # == !
    # An obsolete MIME type. May be used with an unofficial MIME type.
    #
    # == os:
    # Platform-specific MIME type definition.
    #
    # == mt
    # The media type.
    #
    # == st
    # The media subtype.
    #
    # == <ws>@ext
    # The list of comma-separated extensions.
    #
    # == <ws>:enc
    # The encoding.
    #
    # == <ws>'url-list
    # The list of comma-separated URLs.
    #
    # == <ws>=docs
    # The documentation string.
    #
    # That is, everything except the media type and the subtype is optional. The
    # more information that's available, though, the richer the values that can
    # be provided.
    def load_from_v1(filename)
      data = read_file(filename).split($/)
      mime = MIME::Types.new
      data.each_with_index { |line, index|
        item = line.chomp.strip
        next if item.empty?

        begin
          m = MIME::Types::Loader::V1_FORMAT.match(item).captures
        rescue Exception
          warn <<-EOS
#{filename}:#{index}: Parsing error in v1 MIME type definition.
=> #{line}
          EOS
          raise
        end

        unregistered, obsolete, platform, mediatype, subtype, extensions,
          encoding, urls, docs, comment = *m

        if mediatype.nil?
          if comment.nil?
            warn <<-EOS
#{filename}:#{index}: Parsing error in v1 MIME type definition (no media type).
=> #{line}
            EOS
            raise
          end

          next
        end

        extensions &&= extensions.split(/,/)
        urls &&= urls.split(/,/)

        if docs.nil?
          use_instead = nil
        else
          use_instead = docs.scan(%r{use-instead:(\S+)}).flatten
          docs = docs.gsub(%r{use-instead:\S+}, "").squeeze(" \t")
        end

        mime_type = MIME::Type.new("#{mediatype}/#{subtype}") do |t|
          t.extensions  = extensions
          t.encoding    = encoding
          t.system      = platform
          t.obsolete    = obsolete
          t.registered  = false if unregistered
          t.use_instead = use_instead
          t.docs        = docs
          t.references  = urls
        end

        mime.add_type(mime_type, true)
      }
      mime
    end

    # Loads MIME::Types from a single JSON file.
    #
    # It is expected that the JSON objects will be an array of hash objects.
    # The JSON format is the registry format for the MIME types registry
    # shipped with the mime-types library.
    def load_from_json(filename)
      require 'json'
      JSON.load(read_file(filename)).map { |type| MIME::Type.new(type) }
    end

    private
    def read_file(filename)
      File.read(filename)
    end
  end

  private
  def json_path
    File.join(path, '*.json')
  end

  def v1_path
    File.join(path, '*')
  end

  # The regular expression used to match a v1-format file-based MIME type
  # definition.
  MIME::Types::Loader::V1_FORMAT = # :nodoc:
    %r{\A\s*
    ([*])?                                 # 0: Unregistered?
    (!)?                                   # 1: Obsolete?
    (?:(\w+):)?                            # 2: Platform marker
    #{MIME::Type::MEDIA_TYPE_RE}?          # 3,4: Media type
    (?:\s+@(\S+))?                         # 5: Extensions
    (?:\s+:(base64|7bit|8bit|quoted\-printable))?  # 6: Encoding
    (?:\s+'(\S+))?                         # 7: URL list
    (?:\s+=(.+))?                          # 8: Documentation
    (?:\s*([#].*)?)?
    \s*
    \z
    }x
end
