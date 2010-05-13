require 'rubygems'

unless defined?(Palmade)
  if ENV.include?('PALMADE_GEMS_DIR')
    pe_dir = File.join(ENV['PALMADE_GEMS_DIR'], 'palmade_extensions')
  else
    pe_dir = File.join(RAILS_ROOT, '/opt/caresharing/gems/palmade_extensions')
  end

  if File.exists?(pe_dir)
    puts "** Using local palmade_extensions"

    require File.join(pe_dir, 'lib/palmade_extensions')
  elsif pe_gem = Gem.cache.search('palmade_extensions')
    puts "** Using gem palmade_extensions"

    gem 'palmade_extensions'
    require 'palmade_extensions'
  else
    raise "Can't find palmade_extensions!"
  end
end

