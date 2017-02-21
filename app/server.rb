# Sample application foundation for eschol5 - see README.md for more info

# Use bundler to keep dependencies local
require 'rubygems'
require 'bundler/setup'

###################################################################################################
# External gems we need
require 'cgi'
require 'digest'
require 'json'
require 'logger'
require 'mimemagic'
require 'net/http'
require 'open-uri'
require 'pp'
require 'sanitize'
require 'sequel'
require 'sinatra'
require 'sinatra/streaming'
require 'yaml'
require 'socksify'
require 'socket'

# Make puts thread-safe, and flush after every puts.
$stdoutMutex = Mutex.new
def puts(*args)
  $stdoutMutex.synchronize { 
    #STDOUT.print Thread.current
    super(*args)
    STDOUT.flush
  }
end

# Make it clear where the new session starts in the log file.
puts "\n\n=====================================================================================\n"

# Use the Sequel gem to get object-relational mapping, connection pooling, thread safety, etc.
# If specified, use SOCKS proxy for all connections (including database).
dbConfig = YAML.load_file("config/database.yaml")
if File.exist? "config/socks.yaml"
  # Configure socksify for all TCP connections. Jump through hoops for MySQL to use it too.
  TCPSocket::socks_server = "127.0.0.1"
  TCPSocket::socks_port = YAML.load_file("config/socks.yaml")['port']
  require_relative 'socksMysql'
  SocksMysql.reconfigure(dbConfig)
end
DB = Sequel.connect(dbConfig)
#DB.loggers << Logger.new('server.sql_log')  # Enable to debug SQL queries

# Internal modules to implement specific pages and functionality
require_relative 'dbCache'
require_relative 'hierarchy'
require_relative 'listItemViews'
require_relative 'searchApi'
require_relative 'queueWithTimeout'
require_relative 'unitPages'

# Sinatra configuration
configure do
  # Don't use Webrick, as sinatra-websocket requires 'thin', and 'thin' is better anyway.
  set :server, 'thin'
  # We like to use the 'app' folder for all our static resources
  set :public_folder, Proc.new { root }

  set :show_exceptions, false
end

# Compress responses larger than 512 bytes
use Rack::Deflater, :if => lambda {
  |*, body| body.map(&:bytesize).reduce(0, :+) > 512
}

# For general app development, set DO_ISO to false. For real deployment, set to true
DO_ISO = File.exist?("config/do_iso")

###################################################################################################
# Model classes for easy interaction with the database.
#
# For more info on the database schema, see contents of migrations/ directory, and for a more
# graphical version, see:
#
# https://docs.google.com/drawings/d/1gCi8l7qteyy06nR5Ol2vCknh9Juo-0j91VGGyeWbXqI/edit

class Unit < Sequel::Model
  unrestrict_primary_key
  one_to_many :unit_hier,     :class=>:UnitHier, :key=>:unit_id
  one_to_many :ancestor_hier, :class=>:UnitHier, :key=>:ancestor_unit
end

class UnitHier < Sequel::Model(:unit_hier)
  unrestrict_primary_key
  many_to_one :unit,          :class=>:Unit
  many_to_one :ancestor,      :class=>:Unit, :key=>:ancestor_unit
end

class UnitItem < Sequel::Model
  unrestrict_primary_key
end

class Item < Sequel::Model
  unrestrict_primary_key
end

class ItemAuthors < Sequel::Model(:item_authors)
  unrestrict_primary_key
end

class Issue < Sequel::Model
end

class Section < Sequel::Model
end

class Page < Sequel::Model
end

class Widget < Sequel::Model
end

##################################################################################################
# Database caches for speed. We check every 30 seconds for changes. These tables change infrequently.

$unitsHash, $hierByUnit, $hierByAncestor, $activeCampuses, $oruAncestors, $campusJournals,
  $statsCampusPubs, $statsCampusOrus, $statsCampusJournals = nil, nil, nil, nil, nil, nil, nil, nil, nil
Thread.new {
  prevTime = nil
  while true
    utime = nil
    DB.fetch("SHOW TABLE STATUS WHERE Name in ('units', 'unit_hier')").each { |row|
      if row[:Update_time] && (!utime || row[:Update_time] > utime)
        utime = row[:Update_time]
      end
    }
    if !utime || utime != prevTime
      $unitsHash = getUnitsHash 
      $hierByUnit = getHierByUnit
      $hierByAncestor = getHierByAncestor 
      $activeCampuses = getActiveCampuses
      $oruAncestors = getOruAncestors 
      $campusJournals = getJournalsPerCampus

      #####################################################################
      # STATISTICS
      # These are dependent on instantation of $activeCampuses
      $statsCampusPubs = getPubStatsPerCampus
      $statsCampusOrus = getOruStatsPerCampus
      $statsCampusJournals = getJournalStatsPerCampus
      prevTime = utime
    end
    sleep 30
  end
}


###################################################################################################
# ISOMORPHIC JAVASCRIPT
# =====================
#
# Using a Javascript front-end framework like React has a couple downsides: First, it makes the
# site unusable by users who have Javascript turned off. Second, not all crawlers can or do run
# your javascript, and so it might make the site invisible to them.
#
# The solution is so-called "isomorphic Javascript". Basically we run React not only in the
# browser but also on the server. When the page initially loads, we generate the initial HTML
# that React will eventually generate once it fully initializes on the client side, and we send
# that HTML as a starting point. When React starts up on the client, it verifies that the HTML
# is the same (and issues a console warning if not).
#
# How do we run React on the server? We keep a little Node Express server running on a differnet
# port than the main app, and when we need to load a page we feed it the initial data, it runs
# the appropriate React templates, and returns us the HTML.
#
# In this way, the user gets a speedy initial load and can use some of the site features without
# javascript, and crawlers have an easy time seeing everything the users see.
###################################################################################################

###################################################################################################
# Simple up-ness check
get "/check" do
  return "ok"
end

###################################################################################################
# Sanitize incoming filenames before applying them to the filesystem. In particular, prevent
# attacks using "../" as part of the path.
def sanitizeFilePath(path)
  path = path.gsub(/[^-a-zA-Z0-9_.\/]/, '_').split("/").map { |part|
    part.sub(/^\.+/, '_').sub(/\.+$/, '_')
  }.join('/')
end

###################################################################################################
class Fetcher
  def start(uri)
    # We have to fetch the file in a different thread, because it needs to keep the HTTP request
    # open in that thread while we return the status code to Sinatra. Then the remaining data can
    # be streamed from the thread to Sinatra.
    puts "Content fetch: #{uri}."
    @queue = QueueWithTimeout.new
    Thread.new do
      begin
        # Now jump through Net::HTTP's hijinks to actually fetch the file.
        Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
          http.request(Net::HTTP::Get.new uri.request_uri) do |response|
            @queue << [response.code, response.message]
            if response.code == "200"
              response.read_body { |chunk| @queue << chunk }
            else
              puts "Error: Response to #{uri} was HTTP #{response.code}: #{response.message.inspect}"
            end
          end
        end
      ensure
        @queue << nil  # mark end-of-data
      end
    end

    # Wait for the status code to come back from the fetch thread.
    code, msg = @queue.pop_with_timeout(60)
    return code.to_i, msg
  end

  # Now we're ready to set the content type and return the contents in streaming fashion.
  def copyTo(out)
    begin
      while true
        data = @queue.pop_with_timeout(10)
        data.nil? and break
        out.write(data)
      end
    rescue Exception => e
      puts "Warning: problem while streaming content: #{e.message}"
    end
  end
end

###################################################################################################
get "/content/:fullItemID/*" do |fullItemID, path|
  # Prep work
  fullItemID =~ /^qt[a-z0-9]{8}$/ or halt(404)  # protect against attacks
  item = Item[fullItemID]
  item.status == 'published' or halt(403)  # prevent access to embargoed and withdrawn files
  path = sanitizeFilePath(path)  # protect against attacks

  # Fetch the file from Merritt
  fetcher = Fetcher.new
  code, msg = fetcher.start(URI("http://mrtexpress.cdlib.org/dl/ark:/13030/#{fullItemID}/content/#{path}"))

  # Temporary fallback: if we can't find on Merritt, try the raw_data hack on pub-eschol-stg.
  # This is needed for ETDs, since we don't yet record their proper original Merritt location.
  if code != 200
    fetcher = Fetcher.new
    code2, msg2 = fetcher.start(URI("http://pub-eschol-stg.escholarship.org/raw_data/13030/pairtree_root/" +
                                    "#{fullItemID.scan(/../).join('/')}/#{fullItemID}/content/#{path}"))
    code2 == 200 or halt(code, msg)
  end

  # Guess the content type by path for now, and stream the results (don't buffer the whole thing,
  # as some files are huge and would blow out our RAM).
  content_type MimeMagic.by_path(path)
  return stream { |out| fetcher.copyTo(out) }
end

###################################################################################################
# The outer framework of every page is essentially the same, substituting in the intial page
# data and initial elements from React.
# The regex below matches every URL except /api/*, /content/*, and things ending with a file ext.
get %r{^/(?!(api/.*|content/.*|locale/.*|.*\.\w{1,4}$))} do

  puts "Page fetch: #{request.url}"

  if DO_ISO
    # We need to grab the hostname from the URL. There's probably a better way to do this.
    request.url =~ %r{^https?://([^/:]+)(:\d+)?(.*)$} or fail
    host = $1
    remainder = $3

    # Pass the full path and query string to our little Node Express app, which will run it through 
    # ReactRouter and React.
    response = Net::HTTP.new(host, 4002).start {|http| http.request(Net::HTTP::Get.new(remainder)) }
    response.code == "200" or halt(500, "ISO fetch failed")

    # Read in the template file, and substitute the results from React/ReactRouter
    template = File.new("app/app.html").read
    lookFor = '<div id="main"></div>'
    template.include?(lookFor) or raise("can't find #{lookFor.inspect} in template")
    return template.sub(lookFor, response.body)
  else
    # Development mode - skip iso
    return File.new("app/app.html").read
  end
end

###################################################################################################
# Home page data (All campuses or All journals)
get '/api/home' do
  content_type :json
  header = {
    :campuses => getCampusesAsMenu
  }
  return header.to_json
end

###################################################################################################
# Browse page data (All campuses or All journals)
get '/api/browse/:browse_type' do |browse_type|
  content_type :json
  body = {
    :browse_type => browse_type
  }
  case browse_type 
    when "campuslist"
      # Build array of hashes containing campus and stats
      campusesStats = []
      $activeCampuses.each do |k, v|
        pub_count =     ($statsCampusPubs.keys.include? k)  ? $statsCampusPubs[k]     : 0
        unit_count =    ($statsCampusOrus.keys.include? k)  ? $statsCampusOrus[k]     : 0
        journal_count = ($statsCampusJournals.keys.include? k) ? $statsCampusJournals[k] : 0
        campusesStats.push({"id"=>k, "name"=>v.values[:name], 
          "publications"=>pub_count, "units"=>unit_count, "journals"=>journal_count})
      end
      body.merge!({
        :campusesStats => campusesStats,
      })
      breadcrumb = [{"name" => "Campuses", "url" => "/browse/"+browse_type},]
      return body.merge(getHeaderElements(breadcrumb, nil)).to_json
    when "journals"
      body.merge!({
        :journals => $campusJournals.sort_by{ |h| h[:name].downcase }
      })
      breadcrumb = [{"name" => "Journals", "url" => "/browse/"+browse_type},]
      return body.merge(getHeaderElements(breadcrumb, "All Campuses")).to_json
  end
end

###################################################################################################
# Browse page - Campus depts data.
get '/api/browse/depts/:campusID' do |campusID|
  content_type :json
  d = $hierByAncestor[campusID].map do |a|
    getChildDepts($unitsHash[a.unit_id])
  end
  unit = $unitsHash[campusID]
  body = {
    :browse_type => "depts",
    :campusID => campusID,
    :campusName => unit.name,
    :depts => d.compact
  }
  breadcrumb = [
    {"name" => "Departments", "url" => "/browse/depts/"+campusID},
    {"name" => unit.name, "url" => "/unit/"+campusID}]
  return body.merge(getHeaderElements(breadcrumb, nil)).to_json
end

def getChildDepts(unit)
  if unit.type != 'oru'
    return nil
  else
    node = {"id" => unit.id, "name" => unit.name}
    child = $hierByAncestor[unit.id].map { |c| getChildDepts($unitsHash[c.unit_id]) }.compact
    if child[0] then node["children"] = child end
    return node
  end
end


###################################################################################################
# Unit page data.
get "/api/unit/:unitID/?:pageName/?" do
  content_type :json
  unit = $unitsHash.dig(params[:unitID])

  if unit
    begin
      attrs = JSON.parse(unit[:attrs])
      if params[:pageName]
        pageData = {
          unit: unit.values.reject{|k,v| k==:attrs},
          header: getUnitHeader(unit, attrs), 
          sidebar: [],
        }
        pageData[:content] = unitSearch(CGI::parse(request.query_string), unit) if params[:pageName] == 'search'
        pageData[:content] = getUnitPageContent(unit, attrs, params[:pageName]) if params[:pageName] == 'home'
        pageData[:marquee] = getUnitMarquee(unit, attrs) if params[:pageName] == 'home'
      else
        #public API data
        pageData = {
          unit: unit.values.reject{|k,v| k==:attrs}
        }
      end
      return pageData.to_json
    rescue Exception => e
      halt 404, e.message
    end
  else
    halt 404, "Unit not found"
  end
end

###################################################################################################
# Item view page data.
get "/api/item/:shortArk" do |shortArk|
  content_type :json
  id = "qt"+shortArk
  item = Item[id]
  unitIDs = UnitItem.where(:item_id => id, :is_direct => true).order(:ordering_of_units).select_map(:unit_id)
  unit = Unit[unitIDs[0]]

  if !item.nil?
    begin
      body = {
        :id => shortArk,
        :status => item.status,
        :title => item.title,
        :rights => item.rights,
        :pub_date => item.pub_date,
        :authors => ItemAuthors.filter(:item_id => id).order(:ordering).
                       map(:attrs).collect{ |h| JSON.parse(h)},
        :content_type => item.content_type,
        :content_html => getItemHtml(item.content_type, shortArk),
        :attrs => JSON.parse(Item.filter(:id => id).map(:attrs)[0]),
        :appearsIn => unitIDs.map { |unitID| {"id" => unitID, "name" => Unit[unitID].name} },

        :header => getUnitHeader(unit),
        :unit => unit.values.reject { |k,v| k==:attrs }
      }

      # TODO: at some point we'll want to modify the breadcrumb code to include CMS pages and issues
      # in a better way - I don't think this belongs here in the item-level code.
      if unit.type == 'journal'
        issue_id = Item.join(:sections, :id => :section).filter(:items__id => id).map(:issue_id)[0]
        volume, issue = Section.join(:issues, :id => issue_id).map([:volume, :issue])[0]
        body[:header][:breadcrumb] << {name: "Volume #{volume}, Issue #{issue}", id: "#{unitIDs[0]}/issues/#{issue}"}
      end

      return body.to_json
    rescue Exception => e
      halt 404, e.message
    end
  else 
    halt 404, "Item not found"
  end
end

###################################################################################################
# Search page data
get "/api/search/" do
  # Amy, hack here
  content_type :json
  header = {
    :campuses => getCampusesAsMenu
  }
  facetList = ['type_of_work', 'peer_reviewed', 'supp_file_types', 'campuses', 'departments', 'journals', 'disciplines', 'rights']
  return header.merge(search(CGI::parse(request.query_string), facetList)).to_json
end

###################################################################################################
# Social Media Links  for type = (item|unit)
get "/api/mediaLink/:type/:id/:service" do |type, id, service| # service e.g. facebook, google, etc.
  content_type :json
  sharedLink = "http://www.escholarship.com/" + type + "/" + id 
  title = (type == "item") ? Item["qt"+id].title : $unitsHash[id].name
  case service
    when "facebook"
      url = "http://www.facebook.com/sharer.php?u=" + sharedLink
    when "twitter"
      url = "http://twitter.com/home?status=" + title + "[" + sharedLink + "]"
    when "email"
      title_sm = title.length > 50 ? title[0..49] + "..." : title
      url = "mailto:?subject=" + title_sm + "&body=" +
        # ToDo: Put in proper citation
        (item.attrs["orig_citation"] ? item.attrs["orig_citation"] + "\n\n" : "") +
        sharedLink 
    when "mendeley"
      url = "http://www.mendeley.com/import?url=" + sharedLink + "&title=" + title
    when "citeulike"
      url = "http://www.citeulike.org/posturl?url=" + sharedLink + "&title=" + title
  end
  return { url: url }.to_json
end

##################################################################################################
# Helper methods

# Generate breadcrumb and header content for Browse or Static page
def getHeaderElements(breadcrumb, topItem)
  campuses = topItem ? getCampusesAsMenu(topItem) : getCampusesAsMenu
  return {
    :campuses => campuses,
    :breadcrumb => Hierarchy_Manual.new(breadcrumb).generateCrumb
  }
end

# Array of all active root level campuses/ORUs. Include empty label "eScholarship at..." 
def getCampusesAsMenu(topItem="eScholarship at...")
  campuses = []
  $activeCampuses.each do |id, c| campuses << {id: c.id, name: c.name} end
  return campuses.unshift({:id => "", :name=>topItem})
end

# Properly target links in HTML blob
def getItemHtml(content_type, id)
  return false if content_type != "text/html"
  dir = "http://" + request.env["HTTP_HOST"] + "/content/qt" + id + "/"
  htmlStr = open(dir + "qt" + id + ".html").read
  htmlStr.gsub(/(href|src)="((?!#)[^"]+)"/) { |m|
    attrib, url = $1, $2
    url = $2.start_with?("http", "ftp") ? $2 : dir + $2
    "#{attrib}=\"#{url}\"" + ((attrib == "src") ? "" : " target=\"new\"")
  }
end

###################################################################################################
# Static page data.
get "/api/static/:unitID/:pageName" do |unitID, pageName|
  content_type :json

  # Grab unit and page data from the database
  unit = $unitsHash[unitID]
  unit or halt(404, "Unit not found")

  page = Page.where(unit_id: unitID, name: pageName).first
  page or halt(404, "Page not found")

  body = { 
    campuses: getCampusesAsMenu,
    page: {
      title: page.title,
      html: JSON.parse(page.attrs)['html']
    },
    sidebarWidgets: Widget.where(unit_id: unitID, region: 'sidebar').order(:ordering).map { |w|
      attrs = JSON.parse(w.attrs)
      { id: w.id,
        kind: w.kind,
        title: attrs['title'],
        html: attrs['html'] }
    },
    sidebarNavLinks: [{"name" => "About eScholarship", "url" => request.path.sub("/api/", "/")},]
  }
  breadcrumb = [{"name" => "About eScholarship", "url" => request.path.sub("/api/", "/")},]
  return body.merge(getHeaderElements(breadcrumb, nil)).to_json
end

###################################################################################################
# The first line of defense against unwanted or unsafe HTML is the WYSIWIG editor's built-in
# filtering. However, since this is an API we cannot rely on that. This is the second line of
# defense.
def sanitizeHTML(htmlFragment)
  return Sanitize.fragment(params[:newText], 
    elements: %w{b em i strong u} +                      # all 'restricted' tags
              %w{a br li ol p small strike sub sup ul hr},  # subset of ''basic' tags
    attributes: { a: ['href'] },
    protocols:  { a: {'href' => ['ftp', 'http', 'https', 'mailto', :relative]} }
  )
end

###################################################################################################
# *Put* to change the main text on a static page
put "/api/static/:unitID/:pageName/mainText" do |unitID, pageName|

  # In future the token will be looked up in a sessions table of logged in users. For now
  # it's just a placeholder.
  params[:token] == 'xyz123' or halt(401) # TODO: make this actually secure
  # TODO: check that logged in user has permission to edit this unit and page
  puts "TODO: permission check"

  # Grab page data from the database
  page = Page.where(unit_id: unitID, name: pageName).first or halt(404, "Page not found")

  # Parse the HTML text, and sanitize to be sure only allowed tags are used.
  safeText = sanitizeHTML(params[:newText])

  # Update the database
  page.attrs = JSON.parse(page.attrs).merge({ "html" => safeText }).to_json
  page.save

  # And let the caller know it went fine.
  content_type :json
  return { status: "ok" }.to_json
end

###################################################################################################
# *Put* to change widget text
put "/api/widget/:unitID/:widgetID/text" do |unitID, widgetID|

  # In future the token will be looked up in a sessions table of logged in users. For now
  # it's just a placeholder.
  params[:token] == 'xyz123' or halt(401) # TODO: make this actually secure
  # TODO: check that logged in user has permission to edit this unit and page
  puts "TODO: permission check"

  # Grab widget data from the database
  widget = Widget.where(unit_id: unitID, id: widgetID).first or halt(404, "Widget not found")

  # Parse the HTML text, and sanitize to be sure only allowed tags are used.
  safeText = sanitizeHTML(params[:newText])

  # Update the database
  widget.attrs = JSON.parse(widget.attrs).merge({ "html" => safeText }).to_json
  widget.save

  # And let the caller know it went fine.
  content_type :json
  return { status: "ok" }.to_json
end

###################################################################################################
# Post from github notifying us of a push to the repo
post "/jscholGithubHook/onCommit" do
  puts "Got github commit hook - doing pull and restart."
  pid = spawn("/usr/bin/ruby tools/pullJschol.rb > /apps/eschol/tmp/pullJschol.log 2>&1")
  Process.detach(pid)
  return "ok"
end

