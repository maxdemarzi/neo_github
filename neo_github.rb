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

  dates = ["2012-03-11-11", "2012-03-11-12"]
  dates.each do |date|
    unless File.exist?("github/#{date.split("-")[0..-3].join("-")}.json.gz") 
      con = Faraday::Connection.new "http://data.githubarchive.org/#{date}.json.gz", :ssl => {:ca_file => "./cacert.pem"}
      FileUtils.mkdir("github/#{date.split("-")[0..-3].join("-")}") unless File.directory?("github/#{date.split("-")[0..-3].join("-")}")
      File.open("github/#{date.split("-")[0..-3].join("-")}/#{date}.json.gz", 'wb') { |fp| fp.write(con.get.body) }
    end
    gz = File.open("github/#{date.split("-")[0..-3].join("-")}/#{date}.json.gz", 'r')
    js = Zlib::GzipReader.new(gz).read
  
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
        
          users.add({:login      => from["login"], 
                     :avatar_url => from["avatar_url"],
                     :id         => from["id"]})

          users.add({:login      => to["login"], 
                     :avatar_url => to["avatar_url"],
                     :id         => to["id"]})

          vouches.add({:from     => from["login"], 
                       :to       => to["login"],
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
    commands << [:create_node, {:login      => user[:login], 
                                :avatar_url => user[:avatar_url],
                                :id         => user[:id]}]
    commands << [:add_node_to_index, "users_index", "login", user[:login], "{#{index * 2}}"]
  end
  
  batch_results = neo.batch *commands
  puts batch_results.count
  batch_results.values_at(*batch_results.each_index.select(&:even?)).each do |result|
    user_nodes[result["body"]["data"]["login"]] = result["body"]["self"].split('/').last
  end
  
  commands = []
  vouches.each do |vouch|
    puts "from " + vouch[:from] + " to " + vouch[:to] + " type " + vouch[:type]
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

    def neo
      @neo = Neography::Rest.new
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
    node["data"].each_pair do |key, value|
        properties << "<li><b>#{key}:</b> #{value}</li>"
      end
    properties + "</ul>"
  end

  get '/resources/show' do
      content_type :json

      node = neo.get_node(params[:id]) 
      connections = neo.traverse(node, "fullpath", neighbours)
      incoming = Hash.new{|h, k| h[k] = []}
      outgoing = Hash.new{|h, k| h[k] = []}
      nodes = Hash.new
      attributes = Array.new

      connections.each do |c|
         c["nodes"].each do |n|
           nodes[n["self"]] = n["data"]
         end
         rel = c["relationships"][0]

         if rel["end"] == node["self"]
           incoming["Incoming:#{rel["type"]}"] << {:values => nodes[rel["start"]].merge({:id => node_id(rel["start"]) }) }
         else
           outgoing["Outgoing:#{rel["type"]}"] << {:values => nodes[rel["end"]].merge({:id => node_id(rel["end"]) }) }
         end
      end

        incoming.merge(outgoing).each_pair do |key, value|
          attributes << {:id => key.split(':').last, :name => key, :values => value.collect{|v| v[:values]} }
        end

     attributes = [{"name" => "No Relationships","name" => "No Relationships","values" => [{"id" => "#{params[:id]}","name" => "No Relationships "}]}] if attributes.empty?

      @node = {:details_html => "<h2>Neo ID: #{node_id(node)}</h2>\n<p class='summary'>\n#{get_properties(node)}</p>\n",
                :data => {:attributes => attributes, 
                          :name => node["data"]["name"],
                          :id => node_id(node)}
              }

      @node.to_json

    end

  get '/' do
    @neoid = params["neoid"]
    haml :index
  end
end