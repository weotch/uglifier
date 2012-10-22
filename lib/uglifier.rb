# encoding: UTF-8

require "execjs"
require "multi_json"

class Uglifier
  Error = ExecJS::Error
  # MultiJson.engine = :json_gem

  # Default options for compilation
  DEFAULTS = {
    :mangle => true, # Mangle variable and function names, use :vars to skip function mangling
    :toplevel => false, # Mangle top-level variable names
    :except => ["$super"], # Variable names to be excluded from mangling
    :max_line_length => 32 * 1024, # Maximum line length
    :squeeze => true, # Squeeze code resulting in smaller, but less-readable code
    :seqs => true, # Reduce consecutive statements in blocks into single statement
    :dead_code => true, # Remove dead code (e.g. after return)
    :lift_vars => false, # Lift all var declarations at the start of the scope
    :unsafe => false, # Optimizations known to be unsafe in some situations
    :copyright => true, # Show copyright message
    :ascii_only => false, # Encode non-ASCII characters as Unicode code points
    :inline_script => false, # Escape </script
    :quote_keys => false, # Quote keys in object literals
    :define => {}, # Define values for symbol replacement
    :beautify => false, # Ouput indented code
    :beautify_options => {
      :indent_level => 4,
      :indent_start => 0,
      :space_colon => false
    }
  }

  SourcePath = File.expand_path("../uglify.js", __FILE__)
  ES5FallbackPath = File.expand_path("../es5.js", __FILE__)

  # Minifies JavaScript code using implicit context.
  #
  # source should be a String or IO object containing valid JavaScript.
  # options contain optional overrides to Uglifier::DEFAULTS
  #
  # Returns minified code as String
  def self.compile(source, options = {})
    self.new(options).compile(source)
  end

  # Initialize new context for Uglifier with given options
  #
  # options - Hash of options to override Uglifier::DEFAULTS
  def initialize(options = {})
    @options = DEFAULTS.merge(options)
    @context = ExecJS.compile(File.open(ES5FallbackPath, "r:UTF-8").read + File.open(SourcePath, "r:UTF-8").read)
  end

  # Minifies JavaScript code
  #
  # source should be a String or IO object containing valid JavaScript.
  #
  # Returns minified code as String
  def compile(source)
    source = source.respond_to?(:read) ? source.read : source.to_s

    js = <<EOF
    var options = UglifyJS.defaults({}, {
        outSourceMap : null,
        inSourceMap  : null,
        fromString   : true,
        warnings     : false,
    });

    var toplevel = UglifyJS.parse(%{source}, {filename: "?"});

    if (%{compress}) {
      toplevel.figure_out_scope();
      var sq = UglifyJS.Compressor(%{compressor_options});
      toplevel = toplevel.transform(sq);
    }

    if (%{mangle}) {
      toplevel.figure_out_scope();
      toplevel.compute_char_frequency();
      toplevel.mangle_names(%{mangle_options});
    }

    var stream = UglifyJS.OutputStream(%{output_options});
    toplevel.print(stream);
    return stream + ""
EOF

    @context.exec((js % {
      :source => json_encode(source),
      :mangle => mangle?.to_s,
      :compress => squeeze?.to_s,
      :mangle_options => json_encode(mangle_options),
      :output_options => json_encode(output_options),
      :compressor_options => json_encode(compressor_options)
    })) + ";"
  end
  alias_method :compress, :compile

  private

  def mangle?
    !!@options[:mangle]
  end

  def squeeze?
    !!@options[:squeeze]
  end

  def mangle_options
    { "except" => @options[:except] }
  end

  def output_options
    options = {
      "max_line_len" => @options[:max_line_length],
      "ascii_only" => @options[:ascii_only],
      "quote_keys" => @options[:quote_keys],
      "inline_script" => @options[:inline_script],
      "comments" => @options[:copyright]
    }

    if @options[:beautify]
      options.merge(:beautify => true).merge(@options[:beautify_options])
    else
      options
    end
  end

  def compressor_options
    {
      "unsafe" => @options[:unsafe],
      "sequences" => @options[:seqs],
      "dead_code" => @options[:dead_code],
      "global_defs" => defines,
      "hoist_vars" => @options[:lift_vars]
    }
  end

  def defines
    @options[:define] || {}
  end

  def gen_code_options
    options = {
      :ascii_only => @options[:ascii_only],
      :inline_script => @options[:inline_script],
      :quote_keys => @options[:quote_keys]
    }

    if @options[:beautify]
      options.merge(:beautify => true).merge(@options[:beautify_options])
    else
      options
    end
  end

  # MultiJson API detection
  if MultiJson.respond_to? :dump
    def json_encode(obj)
      MultiJson.dump(obj)
    end
  else
    def json_encode(obj)
      MultiJson.encode(obj)
    end
  end
end
