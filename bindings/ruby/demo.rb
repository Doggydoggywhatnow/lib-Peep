require_relative 'peep'

%w[test.wav test.flac].each do |name|
  peep = Peep.new(File.binread(File.join(__dir__, name)))
  total = sum = 0
  loop do
    s = peep.read(1024)
    break if s.empty?
    total += s.size / 2
    sum += s.sum
  end
  peep.seek(2205)
  seek_sum = peep.read(100).sum
  puts "#{name} rate=#{peep.rate} channels=#{peep.channels} frames=#{total} sum=#{sum} seek_sum=#{seek_sum}"
  peep.close
end
