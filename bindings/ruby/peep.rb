# Liberated Peep for Ruby (Fiddle, standard library only)
require 'fiddle'

class Peep
  NAME = Gem.win_platform? ? 'peep.dll' : 'libpeep.so'
  PATH = [ENV['PEEP_LIB'], File.join(__dir__, NAME)].compact.find { |f| File.exist?(f) } or
    raise 'libpeep not found: run ./build.sh first (or set PEEP_LIB)'
  LIB = Fiddle.dlopen(PATH)
  VP = Fiddle::TYPE_VOIDP
  SZ = Fiddle::TYPE_SIZE_T
  OPEN  = Fiddle::Function.new(LIB['peep_open'], [VP, VP, VP, SZ, VP, SZ], Fiddle::TYPE_INT)
  FILL  = Fiddle::Function.new(LIB['peep_fill'], [VP, VP, SZ], SZ)
  SEEK  = Fiddle::Function.new(LIB['peep_seek'], [VP, -Fiddle::TYPE_LONG_LONG], Fiddle::TYPE_VOID)
  CLOSE = Fiddle::Function.new(LIB['peep_close'], [VP], Fiddle::TYPE_VOID)
  FLAC  = Fiddle::Function.new(LIB['peep_flac'], [], VP).call.to_i   # address of the FLAC codec table

  def self.zeroed(n)
    ptr = Fiddle::Pointer.malloc(n, Fiddle::RUBY_FREE)
    ptr[0, n] = "\0" * n
    ptr
  end

  # data: a binary String holding a WAV or FLAC file
  def initialize(data, flac: true)
    @len = data.bytesize
    @data = Peep.zeroed(@len)                       # the library reads from this: keep it alive
    @data[0, @len] = data
    @p = Peep.zeroed(160)                           # struct peep
    @codecs = Peep.zeroed(16)
    @codecs[0, 16] = [flac ? FLAC : 0, 0].pack('QQ')
    @work = nil
    if OPEN.call(@p, @codecs, @data, @len, 0, 0).zero?
      need = @p[144, 8].unpack1('Q')                # work_need
      raise ArgumentError, 'not a playable WAV or FLAC file' if need.zero?
      @work = Peep.zeroed(need)
      raise ArgumentError, 'not a playable WAV or FLAC file' if OPEN.call(@p, @codecs, @data, @len, @work, need).zero?
    end
    @out = Peep.zeroed(4096 * 4)
  end

  def rate     = @p[40, 4].unpack1('V')       # Hz
  def channels = @p[44, 4].unpack1('V')       # channels in the file
  def total    = @p[32, 8].unpack1('Q')       # frames, 0 = unknown
  def position = @p[24, 8].unpack1('Q')       # frames played so far

  # Up to `frames` stereo frames as an Array of interleaved int16 values; empty at the end.
  def read(frames = 1024)
    n = FILL.call(@p, @out, [frames, 4096].min)
    @out[0, n * 4].unpack('s*')
  end

  def seek(frame) = SEEK.call(@p, frame)
  def gain=(q8)                                   # 0..256, 256 = full volume
    @p[48, 4] = [q8.clamp(0, 256)].pack('V')
  end
  def close = CLOSE.call(@p)
end
