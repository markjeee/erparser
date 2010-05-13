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
  CONCURRENCY = 10
  DOWNLOAD_BATCH_SIZE = 100
  ERSOURCE_URL = "http://electionresults.ibanangayon.ph"

  # bin/parse_positions ../electionresults.ibanangayon.ph/ var/found_clusters.csv var/unique_positions.csv var/all_positions.csv
  def self.parse_for_positions!(argv)
    options = parse_arguments(argv)

    dest_dir = argv[0]
    clusters_file = argv[1]
    all_positions_file = argv[3]
    all_positions_candidates_file = argv[5]
    
    raise "Please specify the directory mirror of the election results website" if dest_dir.nil?
    raise "Please specify a target path for the clusters_file" if clusters_file.nil?
    raise "Please specify a target path for all positions file" if all_positions_file.nil?
    raise "Please specify a target path for all positions candidates file" if all_positions_candidates_file.nil?
    
    # parse clusters file
    found_clusters = parse_clusters_file(clusters_file)

    clusters_for_parsing = [ ]
    found_clusters.each do |cdata|
      cluster_name = cdata.last
      clusters_for_parsing.push(cdata) if cluster_name =~ /\ACP\s+/
    end

    puts "* Found #{clusters_for_parsing.size} clusters for parsing"

    # for debugging purposes
    # clusters_for_parsing = clusters_for_parsing.slice(0, 100)
    
    concurrency_count = CONCURRENCY
    total_count = clusters_for_parsing.size
    perslice_count = (total_count / concurrency_count).ceil

    puts "Concurrency count: #{concurrency_count}"
    puts "Total count: #{total_count}"
    puts "Per slice: #{perslice_count}"
    
    (1..concurrency_count).each do |part_no|
      slice_start = (part_no - 1) * perslice_count
      puts "Working on slice: #{slice_start}, #{perslice_count}"

      Process.fork do      
        child_options = {
          :dest_dir => dest_dir,
          :all_positions_file => "#{all_positions_file}.part#{part_no}",
          :all_positions_candidates_file => "#{all_positions_candidates_file}.part#{part_no}"
        }
        
        parse_for_positions_child_worker(clusters_for_parsing.slice(slice_start, perslice_count), child_options)
      end
    end

    Process.waitall

    clusters_file_h = nil
    all_positions_file_h = nil
    all_positions_candidates_file_h = nil
    
    begin
      all_positions_file_h = File.open(all_positions_file, "w")
      all_positions_candidates_file_h = File.open(all_positions_candidates_file, "w")
      
      (1..concurrency_count).each do |part_no|
        child_options = {
          :dest_dir => dest_dir,
          :all_positions_file => "#{all_positions_file}.part#{part_no}",
          :all_positions_candidates_file => "#{all_positions_candidates_file}.part#{part_no}"
        }

        all_positions_file_h.write(File.read(child_options[:all_positions_file]))
        all_positions_candidates_file_h.write(File.read(child_options[:all_positions_candidates_file]))
      end
    ensure
      all_positions_file_h.close unless all_positions_file_h.nil?
      all_positions_candidates_file_h.close unless all_positions_candidates_file_h.nil?
    end
  end

  def self.parse_for_positions_child_worker(clusters_for_parsing, options = { })
    dest_dir = options[:dest_dir]
    clusters_file = options[:clusters_file]
    all_positions_file = options[:all_positions_file]
    all_positions_candidates_file = options[:all_positions_candidates_file]
    
    worked = 0
    all_positions = [ ]
    all_positions_candidates = [ ]
    
    clusters_for_parsing.each do |cdata|
      html_file = cdata[1]
      local_file = File.join(dest_dir, html_file)
      
      if File.exists?(local_file)
        worked += 1
        
        puts "* (#{worked}/#{clusters_for_parsing.size}) Working on #{html_file}"
        positions = parse_positions(local_file, cdata)
        
        unless positions.empty?
          puts "    + Found #{positions.size} positions"
          
          positions.each do |po|
            candidates = po.pop
            candidates.each do |can|
              all_positions_candidates.push([ po[0], po[1], can[0], can[1], can[2], can[3] ])
            end
          end
          
          all_positions += positions
        else
          puts "    + Found no positions"
        end
      else
        puts "* Skippng on #{html_file}, not found"
      end
    end
    
    puts "* Worked on #{worked} clusters out of #{clusters_for_parsing.size}"
    
    puts "* Found #{all_positions.size} total positions"
    FasterCSV.open(all_positions_file, 'w') do |f|
      all_positions.each do |po|
        f << po
      end
    end
    
    puts "* Found #{all_positions_candidates.size} unique positions and candidates"
    FasterCSV.open(all_positions_candidates_file, 'w') do |f|
      all_positions_candidates.each do |pc_data|
        f << pc_data
      end
    end
  end
  
  def self.parse_positions(local_file, cdata)
    xml_d = nil
    File.open(local_file, 'r') do |f|
      xml_d = Nokogiri::HTML(f.read)
    end
    
    positions = [ ]
    unless xml_d.nil?
      xml_d.search('div.boxheader center').each do |boxh|
        unless boxh.content =~ /\AThere is not available/
          position_title = nil
          position_id = nil
          cluster_id = nil
          html_id = nil
          xml_file = nil
          candidates = nil
          
          boxh.search('a').each do |link|
            position_title = link.content
            
            # javascript:Show(1050335);
            if link['href'] =~ /\Ajavascript\:Show\((\d+)\)\;\Z/
              html_id = $~[1]
            end
          end

          unless html_id.nil?
            query = "//div[@id = '#{html_id}']//object//embed"
            xml_d.search(query).each do |embed|
              # &dataURL=res_299001_5524076.xml&chartWidth=513&chartHeight=300
              if embed["flashvars"] =~ /\A\&dataURL=res\_(\d+)\_(\d+)\.xml\&chartWidth\=.+\Z/
                position_id = $~[1]
                cluster_id = $~[2]
                xml_file = "res_#{position_id}_#{cluster_id}.xml"
              else
                raise "Got: #{embed['flashvars']}"
              end
            end
          end

          unless xml_file.nil?
            candidates = [ ]
            query = "//div[@id = '#{html_id}']//table//tr[@class = 'tblightrow']"
            xml_d.search(query).each do |tr|
              candidate_data = [ ]
              tr.search("td[@class = 'lightRowContent']//span").each do |span|
                candidate_data.push(span.content)
              end

              # only parse candidate data if it contain four rows
              # <tr>
              #   <th class="boxtd_big" align="center">Candidate</th>
              #   <th class="boxtd_big" align="center">Party</th>
              #   <th class="boxtd_big" align="center">Votes</th>
              #   <th class="boxtd_big" align="center">Percentage</th>
              # </tr>              
              if candidate_data.size == 4
                candidates.push(candidate_data)
              end
            end
          end
          
          unless xml_file.nil? || candidates.nil?
            # puts "    + Found #{position_id}, #{position_title}, #{xml_file}, #{html_id}, #{candidates.size} candidate(s)"
            positions.push([ cluster_id, position_id, position_title, xml_file, html_id, candidates ])
          else
            puts "    + New format? It's not not available, but can't parse it!"
            break
          end
        end
      end
    end
    
    positions
  end
  
  def self.parse_clusters_file(clusters_file)
    found_clusters = [ ]
    
    puts "* Parsing #{clusters_file}"
    rt = benchmark do
      FasterCSV.foreach(clusters_file) do |row|
        found_clusters.push(row)
      end
    end
    puts "  * took #{rt} sec(s)"

    puts "* Found #{found_clusters.size} from CSV file"

    found_clusters
  end
  
  # e.g. bin/download_clusters var/found_clusters.csv
  def self.download_clusters!(argv)
    options = parse_arguments(argv)

    dest_dir = argv[0]
    clusters_file = argv[1]
    start_batch = argv[2]

    raise "Please specify the directory mirror of the election results website" if dest_dir.nil?
    raise "Please specify a target path for the cluster_file" if clusters_file.nil?

    # parse clusters file
    found_clusters = parse_clusters_file(clusters_file)

    unless start_batch.nil?
      found_clusters.slice!(0, start_batch.to_i * DOWNLOAD_BATCH_SIZE)
      batch_no = start_batch.to_i
    else
      batch_no = 1
    end

    start_time = Time.now
    while !found_clusters.empty?
      this_batch = found_clusters.slice!(0, DOWNLOAD_BATCH_SIZE)

      puts "* Downloading batch \##{batch_no} elapsed time: #{(Time.now - start_time).to_i} sec(s)"
      puts "  - #{this_batch.collect{ |cd| cd[0] }.join(', ')}"

      tries_left = 3
      loop do
        success = download_clusters_per_batch(dest_dir, this_batch, DOWNLOAD_BATCH_SIZE)

        break if success == this_batch.size
        break if tries_left <= 0
        tries_left -= 1
        
        puts "  - Retrying (left: #{tries_left}) only #{success} out of #{this_batch.size}"
      end

      batch_no += 1
    end
  end

  def self.download_clusters_per_batch(dest_dir, clusters, batch_size = DOWNLOAD_BATCH_SIZE)
    success = 0
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
          success += 1
        end
      end
    end

    unless clusters_for_dl.empty?
      puts "  - Downloading #{clusters_for_dl.size} clusters"
      success += get_clusters_html_file(dest_dir, clusters_for_dl)
    else
      puts "  - All clusters in this batch are up to date"
    end

    success
  end

  def self.get_clusters_html_file(dest_dir, clusters)
    h = Typhoeus::Hydra.hydra

    requests = [ ]
    replied = 0
    success = 0
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
      
      r = Typhoeus::Request.new(url, :timeout => 1000 * 5)
      r.on_complete do |resp|
        replied += 1
        progress = "#{replied}/#{clusters.size}"
        
        if resp.code == 200
          # let's get the source time from source site
          source_mtime = to_time(resp.headers_hash['Last-Modified'])
          etag = resp.headers_hash['ETag']
          length = resp.headers_hash['Content-Length']
          
          puts "    + (#{progress} - #{resp.time}s) writing #{html_file}, #{length}, #{source_mtime}, #{etag}"
          File.open(local_file, "w") { |f| f.write(resp.body) }
          
          # let's write the etag for later checking
          File.open(etag_file, "w") { |f| f.write(etag) }
          
          # let's set the mtime of the local file
          File.utime(Time.now, source_mtime.getlocal, local_file)

          success += 1
        elsif resp.code == 304
          puts "    + (#{progress}) file #{html_file} hasn't changed"

          success += 1
        elsif resp.code == 404
          puts "    + (#{progress}) 404! #{url}"
        elsif resp.code == 0
          puts "    + (#{progress}) took to long! #{url}"
        else
          raise "Got HTTP response #{r.url}: #{resp.code}, #{resp.body}"
        end
      end

      requests.push(r)
      h.queue(r)
    end

    rt = benchmark { h.run }
    puts(sprintf("    * took %.5f sec(s)", rt))

    success
  end
  
  def self.get_clusters_modification_time(urls)
    h = Typhoeus::Hydra.hydra

    source_mtimes = [ ]
    requests = [ ]
    urls.each do |url|
      r = Typhoeus::Request.new(url, :method => :head, :timeout => 1000 * 20)
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
