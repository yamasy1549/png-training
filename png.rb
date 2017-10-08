require 'zlib'
require 'tk'
require 'ruby-progressbar'

PNG_FILE_SIGNATURE = "89504e470d0a1a0a"
CHUNK_TYPE_SIZE = 4

IHDR_IW_SIZE = 4
IHDR_IH_SIZE = 4
IHDR_BD_SIZE = 1
IHDR_CT_SIZE = 1
IHDR_CM_SIZE = 1
IHDR_FM_SIZE = 1
IHDR_IM_SIZE = 1

def paeth_predictor(left_colors, top_colors, left_top_colors)
  3.times.map do |i|
    left     = left_colors[i]
    top      = top_colors[i]
    left_top = left_top_colors[i]
    here     = left + top - left_top

    here_left     = (here - left).abs
    here_top      = (here - top).abs
    here_left_top = (here - left_top).abs

    if here_left <= here_top && here_left <= here_left_top
      left
    elsif here_top <= here_left_top
      top
    else
      left_top
    end
  end
end

class Array
  def add(array)
    self.zip(array).map{ |a, b| (a + b) % 256 }
  end

  def code
    '#' + self.map{ |x| format("%02x", x) }.join
  end
end

class String
  def to_hex
    self.unpack("H*").pop.hex
  end
end

class Chunk
  attr_accessor :data

  def initialize(name, bytes)
    @name = name
    read_chunk(bytes)
  end

  def read_chunk(bytes)
    @length = bytes.match(/(\H{4})#{@name}/)[1].to_hex
    num = /#{@name}/ =~ bytes
    @data = bytes[num + CHUNK_TYPE_SIZE, @length]
  end
end

class PNG
  def initialize(filename)
    @filename = filename
    @bytes = File.open(filename, "rb").read
    @IHDR = Chunk.new("IHDR", @bytes)
    @IDAT = Chunk.new("IDAT", @bytes)
    @IEND = Chunk.new("IEND", @bytes)
    set_header_info
  end

  def set_header_info
    @image_width        = @IHDR.data[i = 0,             IHDR_IW_SIZE].to_hex
    @image_height       = @IHDR.data[i += IHDR_IW_SIZE, IHDR_IH_SIZE].to_hex
    @bit_depth          = @IHDR.data[i += IHDR_IH_SIZE, IHDR_BD_SIZE].to_hex
    @color_type         = @IHDR.data[i += IHDR_BD_SIZE, IHDR_CT_SIZE].to_hex
    @compression_method = @IHDR.data[i += IHDR_CT_SIZE, IHDR_CM_SIZE].to_hex
    @filter_method      = @IHDR.data[i += IHDR_CM_SIZE, IHDR_FM_SIZE].to_hex
    @interlace_method   = @IHDR.data[i += IHDR_FM_SIZE, IHDR_IM_SIZE].to_hex
  end

  def is_processable?
    is_png? && @color_type == 2
  end

  def is_png?
    head = @bytes[0...8]
    head.unpack("H*").pop == PNG_FILE_SIGNATURE
  end

  def image_data
    Zlib::Inflate.inflate(@IDAT.data)
  end

  def write
    canvas = TkCanvas.new(nil, height: @image_height, width: @image_width)
    canvas.pack(side: 'top')

    filter_types = []
    row_colors = self.image_data.chars.map(&:to_hex).each_slice(@image_width*3 + 1).map do |colors|
      filter_types << colors[0]
      colors[1..-1].each_slice(3).to_a
    end

    progressbar = ProgressBar.create(title: "Output", total: row_colors.length)
    output_colors = Array.new(@image_height).map{ Array.new(@image_width, 0) }
    row_colors.each_with_index do |colors, row|
      colors.each_with_index do |color, col|
        output_color =
          case filter_types[row]
          when 0
            color
          when 1
            col == 0 ? color : color.add(output_colors[row][col-1])
          when 2
            row == 0 ? color : color.add(output_colors[row-1][col])
          when 3
            left = col == 0 ? [0, 0, 0] : output_colors[row][col-1]
            top  = row == 0 ? [0, 0, 0] : output_colors[row-1][col]
            ave_color = left.zip(top).map{ |a, b| ((a + b)/2).floor }
            color.add(ave_color)
          when 4
            left     = col == 0 ? [0, 0, 0] : output_colors[row][col-1]
            top      = row == 0 ? [0, 0, 0] : output_colors[row-1][col]
            left_top = (row == 0 || col == 0) ? [0, 0, 0] : output_colors[row-1][col-1]
            paeth_color = paeth_predictor(left, top, left_top)
            color.add(paeth_color)
          end
        output_colors[row][col] = output_color
        TkcRectangle.new(canvas, col, row, col+1, row+1, fill: output_color.code, width: 0)
      end
      progressbar.increment
    end
    Tk.mainloop
  end
end

image = PNG.new(ARGV[0])
exit 1 unless image.is_processable?
image.write
