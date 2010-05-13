ERPARSER_LIB = File.dirname(__FILE__)

# To use this code, you'll need to install the following:
# * ruby 1.8.7 or higher
# * ruby gems 1.3.5 or higher

# And the following gems:
# * sudo gem install nokogiri
# * sudo gem install fastercsv
# * sudo gem install typhoeus

require 'rubygems'
require 'fileutils'
require 'parsedate'
require 'benchmark'

require 'nokogiri'
require 'fastercsv'
require 'typhoeus'

module ErParser
  DOWNLOAD_BATCH_SIZE = 20
  ERSOURCE_URL = "http://electionresults.ibanangayon.ph"
  
  # e.g. bin/download_clusters var/found_clusters.csv
  def self.download_clusters!(argv)
    options = parse_arguments(argv)

    dest_dir = argv[0]
    cluster_file = argv[1]
    start_batch = argv[2]

    raise "Please specify the directory mirror of the election results website" if dest_dir.nil?
    raise "Please specify a target path for the cluster_file" if cluster_file.nil?

    found_clusters = [ ]

    puts "* Parsing #{cluster_file}"
    rt = benchmark do
      FasterCSV.foreach(cluster_file) do |row|
        found_clusters.push(row)
      end
    end
    puts "  * took #{rt} sec(s)"

    puts "* Found #{found_clusters.size} from CSV file"

    unless start_batch.nil?
      found_clusters.slice!(0, start_batch.to_i * DOWNLOAD_BATCH_SIZE)
      batch_no = start_batch.to_i
    else
      batch_no = 1
    end
    
    while !found_clusters.empty?
      this_batch = found_clusters.slice!(0, DOWNLOAD_BATCH_SIZE)

      puts "* Downloading batch \##{batch_no}"
      puts "  - #{this_batch.collect{ |cd| cd[0] }.join(', ')}"
      download_clusters_per_batch(dest_dir, this_batch, DOWNLOAD_BATCH_SIZE)

      batch_no += 1
    end
  end

  def self.download_clusters_per_batch(dest_dir, clusters, batch_size = DOWNLOAD_BATCH_SIZE)
    clusters_info = { }
    
    clusters.each do |cdata|
      html_file = cdata[1]
      local_file = File.join(dest_dir, html_file)
      etag_file = File.join(dest_dir, "#{html_file}.etag")
      source_url = File.join(ERSOURCE_URL, html_file)
      
      if File.exists?(local_file)
        mtime = File.mtime(local_file).getutc
      else
        mtime = nil
      end

      if File.exists?(etag_file)
        etag = File.read(etag_file)
      else
        etag = nil
      end
      
      clusters_info[cdata[0]] = { :html_file => html_file,
        :source_url => source_url,
        :mtime => mtime,
        :etag => etag }
    end

    puts "  - Downloading modification times"
    source_mtimes = get_clusters_modification_time(clusters_info.collect { |cid, ci| ci[:source_url] })

    clusters_for_dl = [ ]
    clusters_info.each do |cid, ci|
      mtime, etag = source_mtimes.shift
      ci[:source_mtime] = mtime
      ci[:source_etag] = etag

      unless mtime.nil?
        # no local file
        if ci[:mtime].nil?
          mode = "N"
          clusters_for_dl.push(ci)
          
          # etag mismatch
        elsif ci[:etag] != ci[:source_etag]
          ci[:mode] = 'U'
          clusters_for_dl.push(ci)
          
          # mtime mismatch
        elsif ci[:mtime] < ci[:source_mtime]
          ci[:mode] = 'U'
          clusters_for_dl.push(ci)
          
          # else do nothing
        else
          mode = nil
        end
      end
    end

    unless clusters_for_dl.empty?
      puts "  - Downloading #{clusters_for_dl.size} clusters"
      get_clusters_html_file(dest_dir, clusters_for_dl)
    else
      puts "  - All clusters in this batch are up to date"
    end
  end

  def self.get_clusters_html_file(dest_dir, clusters)
    h = Typhoeus::Hydra.hydra

    requests = [ ]
    replied = 0
    clusters.each do |ci|
      html_file = ci[:html_file]
      etag_file = File.join(dest_dir, "#{html_file}.etag")
      
      local_file = File.join(dest_dir, html_file)
      url = ci[:source_url]
      request_options = { :method => :get }
      request_options[:headers] = { }
      
      unless ci[:etag].nil?
        request_options[:headers]['If-None-Match'] = ci[:etag]
      end
      
      r = Typhoeus::Request.new(url)
      r.on_complete do |resp|
        replied += 1
        progress = "#{replied}/#{clusters.size}"
        
        if resp.code == 200
          # let's get the source time from source site
          source_mtime = to_time(resp.headers_hash['Last-Modified'])
          etag = resp.headers_hash['ETag']
          length = resp.headers_hash['Content-Length']
          
          puts "    + (#{progress}) writing #{html_file}, #{length}, #{source_mtime}, #{etag}"
          File.open(local_file, "w") { |f| f.write(resp.body) }
          
          # let's write the etag for later checking
          File.open(etag_file, "w") { |f| f.write(etag) }
          
          # let's set the mtime of the local file
          File.utime(Time.now, source_mtime.getlocal, local_file)
        elsif resp.code == 304
          puts "   + (#{progress}) file #{html_file} hasn't changed"
        elsif resp.code == 404
          puts "   + (#{progress}) 404! #{url}"
        else
          raise "Got HTTP response #{r.url}: #{resp.code}, #{resp.body}"
        end
      end

      requests.push(r)
      h.queue(r)
    end

    rt = benchmark { h.run }
    puts(sprintf("    * took %.5f sec(s)", rt))

    requests
  end
  
  def self.get_clusters_modification_time(urls)
    h = Typhoeus::Hydra.hydra

    source_mtimes = [ ]
    requests = [ ]
    urls.each do |url|
      r = Typhoeus::Request.new(url, :method => :head)
      requests.push(r)
      h.queue(r)
    end
    
    rt = benchmark { h.run }
    puts(sprintf("    * took %.5f sec(s)", rt))
    
    requests.each do |r|
      resp = r.response
      if resp.code == 200
        source_mtime = to_time(resp.headers_hash['Last-Modified'])
        etag = resp.headers_hash['ETag']
        
        source_mtimes.push([ source_mtime, etag ])
      elsif resp.code == 404
        puts "    - 404! #{r.url}"
        source_mtimes.push([ nil, nil ])
      else
        raise "Got HTTP response #{r.url}: #{resp.code}, #{resp.body}"
      end
    end

    source_mtimes
  end

  def self.to_time(time_str)
    ::Time.utc(*ParseDate.parsedate(time_str))
  end

  def self.benchmark(&block)
    [ Benchmark.measure(&block).real, 0.0001 ].max
  end
  
  # e.g bin/parse_clusters electionresults.ibanangayon.ph/ var/found_clusters.csv
  def self.parse_for_clusters!(argv)
    options = parse_arguments(argv)

    dir = argv[0]
    cluster_file = argv[1]

    raise "Please specify the directory mirror of the election results website" if dir.nil?
    raise "Please specify a target path for the cluster_file" if cluster_file.nil?
    
    puts "Working on #{dir}"

    html_files = [ ]
    Dir[File.join(dir, "*.html")].each do |html_file|
      html_files.push(html_file)
    end

    found_clusters = { }
    puts "Found #{html_files.size} file(s) to work on"
    html_files.each do |html_file|
      # puts "* #{html_file}"
      parsed_clusters = parse_clusters(html_file)
      parsed_clusters.each do |pc|
        unless found_clusters.include?(pc[0])
          found_clusters[pc[0]] = pc
        end
      end
    end

    puts "Found #{found_clusters.size} possible clusters to parse"
    FasterCSV.open(cluster_file, 'w') do |f|
      found_clusters.each do |cid, cdata|
        f << cdata
      end
    end
  end

  def self.parse_arguments(argv)
    options = { }
  end

  def self.parse_clusters(html_file)
    options = { }
    xml_d = nil
    found_clusters = [ ]
    
    File.open(html_file, 'r') do |f|
      xml_d = Nokogiri::HTML(f.read)
    end

    unless xml_d.nil?
      link = File.basename(html_file)
      cluster_id = $~[1] if link =~ /\Ares_reg(\d+).html\Z/

      cluster_info = [ ]
      # retrieve nagivation items
      xml_d.search('div.locationBar a').each do |link_tag|        
        nav_link = File.basename(link_tag['href'])
        nav_cluster_id = $~[1] if nav_link =~ /\Ares_reg(\d+).html\Z/        
        nav_link_name = link_tag.content
        
        cluster_info += [ nav_cluster_id, nav_link, nav_link_name ]
      end

      puts "  + #{link} = #{cluster_id}, #{cluster_info.inspect}"
      found_clusters.push([ cluster_id, link ] + cluster_info)
      
      xml_d.search('li.region-nav-item a').each do |link_tag|
        link = File.basename(link_tag['href'])
        cluster_id = $~[1] if link =~ /\Ares_reg(\d+).html\Z/
        link_name = link_tag.content

        this_cluster_info = cluster_info + [ cluster_id, link, link_name ]
        
        puts "  + #{link} = #{cluster_id}, #{this_cluster_info.inspect}"

        found_clusters.push([ cluster_id, link ] + this_cluster_info)
      end
    end

    found_clusters
  end
end
