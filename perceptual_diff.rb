require 'rubygems'
require 'rcomposite'
include RComposite

class PerceptualDiff 
  # debug is referring to the ruby program
  # verbose is referring to the perceptualdiff command line program
  attr_accessor :img1, :img2, :verbose, :fov, :threshold, :gamma, :luminance, :luminanceonly, 
                :output, :verbose, :debug
  attr_reader   :visibly_different, :identical, :indistinguishable, :pixel_difference

  def initialize(img1, img2, options={})
    @img1, @img2 = img1, img2
    options.each {|k,v| send("#{k}=", v)}
    @pixel_difference = 0
  end

  def method_missing(m, *args, &block)  
    match = m.to_s[/^opt_.*$/]
    if match
      cmd_arg       = match.sub("opt_", "")
      cmd_arg_value = send(cmd_arg)

      if cmd_arg_value == true
        "-#{cmd_arg}"
      elsif cmd_arg_value
        "-#{cmd_arg} #{cmd_arg_value}" 
      else
        ""
      end
    end
  end

  def diff
    @indistinguishable = @visibly_different = @identical = false 
    @pixel_difference = 0

    # consider using open4
    # but $? doesn't seem to return anything good
    o = `./perceptualdiff -verbose #{@img1} #{@img2} #{opt_output} #{opt_threshold} #{opt_gamma} #{opt_fov} #{opt_luminance} #{opt_luminanceonly}`

    o.split(/\n/).each do |line|
      # TODO: didn't convert those
      # Converting RGB to XYZ
      # Constructing Laplacian Pyramids

      @fov               = $1   if line =~ /Field of view is (\d+\.\d+) degrees/
      @threshold         = $1   if line =~ /Threshold pixels is (\d+) pixels/
      @gamma             = $1   if line =~ /The Gamma is (\d+\.\d+)/
      @luminance         = $1   if line =~ /The Display's luminance is (\d+\.\d+) candela per meter squared/
      
      @pixel_difference  = $1   if line =~ /(\d+) pixels are different/
      @visibly_different = true if line =~ /FAIL: Images are visibly different/
      @identical         = true if line =~ /PASS: Images are binary identical/
      @indistinguishable = true if line =~ /PASS: Images are perceptually indistinguishable/
    end

    output_verbose if verbose 
  end


  private
    def output_verbose
      puts "fov                #{fov}"
      puts "threshold          #{threshold}"
      puts "gamma              #{gamma}"
      puts "luminance          #{luminance}"
      puts "pixel difference   #{pixel_difference}"
      puts
      puts "identical=         #{identical}"
      puts "visibly_different= #{visibly_different}"
      puts "indistinguishable= #{indistinguishable}"
    end
end

# def diff_file_name(img1, img2)
#   i1       = File.basename(img1, File.extname(img1)) 
#   i2       = File.basename(img2, File.extname(img2))
#   datetime = Time.now.strftime("%Y%m%d%H%M")
#   ext      = File.extname(img1)
#   "#{i1}_diff_#{i2}_#{datetime}#{ext}"
# end

def diff_file_name(img1)
  i1       = File.basename(img1, File.extname(img1)) 
  ext      = File.extname(img1)
  datetime = Time.now.strftime("%Y%m%d%H%M")
  "diff_layer_on_top_#{i1}_#{datetime}_#{ext}"
end

GREEN  = "#1EE225"
YELLOW = "#FFFF00"
RED    = "#FF0000"

def process(img1, img2, options)
  p = PerceptualDiff.new(img1, img2, options)
  p.diff

  before = Magick::Image.read(p.img1).first
  after  = Magick::Image.read(p.img2).first
  diff   = Magick::Image.read(p.output).first

  color = if p.visibly_different
            RED
          elsif p.indistinguishable
            YELLOW
          elsif p.identical
            GREEN
          else
            # TODO: come up with a different color
            "FFFFFF"
          end

  if color == RED || color == YELLOW
    before.border!(10, 10, color) 
    after.border!(10, 10, color)
    diff.border!(10, 10, color)

    before_canvas = Canvas.new(diff.columns, diff.rows) do
      layer :image => diff do opacity 60 end
      layer :image => before
    
      save_as diff_file_name(p.img1) #"diff_layer_on_top_original_" + File.basename(p.img1,  + ".png"  # diff_file_name(p.img1, p.img2)
    end

    after_canvas = Canvas.new(diff.columns, diff.rows) do
      layer :image => diff do opacity 60 end
      layer :image => after
    
      save_as diff_file_name(p.img2)
    end
  else
    #after.save_as   
  end
end

if __FILE__ == $0
  require 'optparse'
  options = {}
  options[:debug]         = false
  options[:verbose]       = false
  options[:luminanceonly] = false

  OptionParser.new do |opts|
    opts.banner = "\nruby peceptual_diff image1.tif image2.tif \n\n   Compares image1.tif and image2.tif using a perceptually based image metric \n   Options:"

    opts.on("--debug",                   "Turns on perceptualdiff command line output")                      {|val| options[:debug]         = val}
    opts.on("--verbose",                 "Turns on verbose mode")                                            {|val| options[:verbose]       = val}
	  opts.on("--fov deg",        String,  "Field of view in degrees (0.1 to 89.9)")                           {|val| options[:fov]           = val}
	  opts.on("--threshold p",    Integer, "#pixels p below which differences are ignored")                    {|val| options[:threshold]     = val}
	  opts.on("--gamma g",        Float,   "Value to convert rgb into linear space (default 2.2)")             {|val| options[:gamma]         = val}
	  opts.on("--luminance l",    Float,   "White luminance (default 100.0 cdm^-2)")                           {|val| options[:luminance]     = val}
	  opts.on("--luminanceonly",           "Only consider luminance; ignore chroma (color) in the comparison") {|val| options[:luminanceonly] = val}
	  #opts.on("-colorfactor ",            "How much of color to use, 0.0 to 1.0, 0.0 = ignore color.")        {|val| options[:colorfactor]   = val}
	  #opts.on("-downsample",              "How many powers of two to down sample the image.")                 {|val| options[:downsample]    = val}
	  opts.on("--output out.ppm", String,  "Write difference to the file o.ppm")                               {|val| options[:output]        = val}

    opts.parse!
    if ARGV.count == 2
      img1, img2 = ARGV 
      process(img1, img2, options)
    else
      puts opts
      exit
    end
  end
end
