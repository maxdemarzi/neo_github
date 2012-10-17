require 'rubygems'
require 'neography'
require 'sinatra'
require 'open-uri'
require 'zlib'
require 'yajl'
require 'set'
require 'faraday'

def create_graph
  users = Set.new
  vouches = Set.new
  dates = []
  (0..23).each do |h|
    (1..1).each do |d|  #just one day for now
      if d < 10
        dates << "2012-04-0#{d}-#{h}" 
      else
        dates << "2012-04-#{d}-#{h}" 
      end
    end
  end
  
  dates = ["2012-03-11-11", "2012-03-11-12"]

  dates.each do |date|
    puts "Procesing #{date}"
    path = "github/#{date.split("-")[0..-3].join("-")}/#{date}.json.gz"
    unless File.exist?(path)
      url = "http://data.githubarchive.org/#{date}.json.gz"
      puts "#{path} not found, downloading file #{url}"

      con = Faraday::Connection.new url, :ssl => {:ca_file => "./cacert.pem"}
      FileUtils.mkdir("github/#{date.split("-")[0..-3].join("-")}") unless File.directory?("github/#{date.split("-")[0..-3].join("-")}")
      File.open("github/#{date.split("-")[0..-3].join("-")}/#{date}.json.gz", 'wb') { |fp| fp.write(con.get.body) }
      puts 'done!'
    end
    gz = File.open("github/#{date.split("-")[0..-3].join("-")}/#{date}.json.gz", 'r')

    begin
      js = Zlib::GzipReader.new(gz).read
    rescue
      # if nobody did anything that hour
      next
    end
    
    Yajl::Parser.parse(js) do |event|
      case event["type"]
      when "CommitCommentEvent"
      when "CreateEvent"
      when "DeleteEvent"
      when "DownloadEvent"
      when "FollowEvent"
      when "ForkApplyEvent"
      when "ForkEvent"
      when "GistEvent"
      when "GollumEvent"
      when "IssuesEvent"
      when "IssueCommentEvent"
      when "MemberEvent"
      when "PublicEvent"
      when "PullRequestReviewCommentEvent"
      when "PushEvent"
      when "WatchEvent"
      # Do nothing
      when "PullRequestEvent"
        if (event["payload"]["action"] == "closed") && 
          event["payload"]["pull_request"]["merged"] && 
          event["repository"]["language"]
          
          from = event["payload"]["pull_request"]["merged_by"]
          to   = event["payload"]["pull_request"]["user"]
        
          users.add({:name      => from["login"], 
                     :avatar_url => from["avatar_url"]})

          users.add({:name      => to["login"], 
                     :avatar_url => to["avatar_url"]})

          vouches.add({:from     => from["login"], 
                       :to       => to["login"],
                       :type     => event["repository"]["language"]})
          vouches.add({:from     => to["login"],
                       :to       => from["login"], 
                       :type     => event["repository"]["language"]})

        end
      end
    end
  end
  
  load_vouches(users, vouches)
  
end


def load_vouches(users, vouches)
  neo = Neography::Rest.new
  commands = []
  user_nodes = {}
  users.each_with_index do |user, index|
    commands << [:create_node, {:name      => user[:name], 
                                :avatar_url => user[:avatar_url]}]
    commands << [:add_node_to_index, "users_index", "name", user[:name], "{#{index * 2}}"]
  end
  
  batch_results = neo.batch *commands

  batch_results.values_at(*batch_results.each_index.select(&:even?)).each do |result|
    user_nodes[result["body"]["data"]["name"]] = result["body"]["self"].split('/').last
  end
  
  commands = []
  vouches.each do |vouch|
    commands << [:create_relationship, vouch[:type], user_nodes[vouch[:from]], user_nodes[vouch[:to]], nil] 
  end
  batch_results = neo.batch *commands
end

class NeoGithub < Sinatra::Application
  set :haml, :format => :html5 
  set :app_file, __FILE__

  helpers do
    def link_to(url, text=url, opts={})
      attributes = ""
      opts.each { |key,value| attributes << key.to_s << "=\"" << value << "\" "}
      "<a href=\"#{url}\" #{attributes}>#{text}</a>"
    end
  end
    
  def neighbours
    {"order"         => "depth first",
     "uniqueness"    => "none",
     "return filter" => {"language" => "builtin", "name" => "all_but_start_node"},
     "depth"         => 1}
  end

  def node_id(node)
    case node
      when Hash
        node["self"].split('/').last
      when String
        node.split('/').last
      else
        node
    end
  end

  def get_properties(node)
    properties = "<ul>"
    node.each_pair do |key, value|
      if key == "avatar_url"
        properties << "<li><img src='#{value}'></li>"
      else
        properties << "<li><b>#{key}:</b> #{value}</li>"
      end
    end
    properties + "</ul>"
  end

  get '/resources/show' do
    content_type :json
    neo = Neography::Rest.new    

    cypher = "START me=node(#{params[:id]}) 
              MATCH me <-[r?]- vouchers
              RETURN me, r, vouchers"

    connections = neo.execute_query(cypher)["data"]   
 
    me = connections[0][0]["data"]
    
    vouches = []
    if connections[0][1]
      connections.group_by{|group| group[1]["type"]}.each do |key,values| 
        vouches <<  {:id => key, 
                     :name => key,
                     :values => values.collect{|n| n[2]["data"].merge({:id => node_id(n[2]) }) } }
      end
    end

     vouches = [{"name" => "No Relationships","name" => "No Relationships","values" => [{"id" => "#{params[:id]}","name" => "No Relationships "}]}] if vouches.empty?

    @node = {:details_html => "<h2>Neo ID: #{params[:id]}</h2>\n<p class='summary'>\n#{get_properties(me)}</p>\n",
                :data => {:attributes => vouches, 
                          :name => me["name"],
                          :id => params[:id]}
              }

      @node.to_json


    end

  get '/' do
    @neoid = params["neoid"]
    haml :index
  end
  
  get '/best' do
    neo = Neography::Rest.new
    cypher = "START me=node(*) 
              MATCH me <-[r?]- vouchers
              RETURN ID(me), COUNT(r)
              ORDER BY COUNT(r) DESC"

    neo.execute_query(cypher)["data"].to_json
  end
end