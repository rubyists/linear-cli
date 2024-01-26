# frozen_string_literal: true

Pathname.new(__FILE__).dirname.join('issue').glob('*.rb').each do |file|
  require file.expand_path
end
