# frozen_string_literal: true

Pathname.new(__FILE__).dirname.join('team').glob('*.rb').each do |file|
  require file.expand_path
end
