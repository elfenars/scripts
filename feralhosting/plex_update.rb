#!/usr/bin/ruby

require 'net/https'
require 'open-uri'
require 'logger'
require 'json'
require 'fileutils'

logger = Logger.new(STDOUT)
env    = ENV['PLEX_UPDATE_ENV']

require 'pry' if env != 'production'

def report_pushover(message)
  pushover_token   = ENV["PUSHOVER_TOKEN"]
  pushover_user    = ENV["PUSHOVER_USER"]
  pushover_message = message
  pushover_url     = "https://api.pushover.net/1/messages"
  system("curl -XPOST #{pushover_url} --form-string 'token=#{pushover_token}' --form-string 'user=#{pushover_user}' --form-string 'message=#{pushover_message}'")
end

# Validate Plex Token
logger.info "Starting Plex Update"
plex_token     = ENV["PLEX_TOKEN"]
token_validation = Net::HTTP.get_response(URI("https://plex.tv/api/resources?X-Plex-Token=#{plex_token}")).response.code.to_i
unless token_validation == 200
  message = "Token not valid"
  logger.info message
  report_pushover(message)
  exit
end

# Get latest versions
latest_versions_url = URI("https://plex.tv/api/downloads/1.json?channel=plexpass&X-Plex-Token=#{plex_token}")
response            = Net::HTTP.get_response(latest_versions_url)

if response.is_a? Net::HTTPRedirection
  linux_versions = JSON.parse(Net::HTTP.get(URI.parse(response['Location'])))["computer"]["Linux"]
else
  linux_versions = JSON.parse(Net::HTTP.get(latest_versions_url))["computer"]["Linux"]
end

# Check Release Date
latest_release     = linux_versions["release_date"]
release_file       = "#{Dir.home}/private/plex_releases.txt"
downloaded_release = (env == 'production') ? File.read(release_file).to_i : 1

unless latest_release > downloaded_release
  message = "Already at the latest version #{latest_release}."
  logger.info message
  exit
end

ubuntu64_release = linux_versions["releases"].select{ |k,v| k["build"] == "linux-x86_64" and k["distro"] == "debian"}
if ( ubuntu64_release == "" ) || ( ubuntu64_release == nil ) || ( ubuntu64_release == [] )
  message = "Ubuntu64 release is empty"
  logger.info message
  report_pushover(message)
  exit
end

# Downlod Plex
download_url = ubuntu64_release.first["url"]
file_name = download_url.split("/")[-1]

if env == "production"
  begin
    logger.info "Starting Download: #{Dir.home}/private/#{file_name}"
    File.open("#{Dir.home}/private/#{file_name}", 'w') do |saved_file|
      open(download_url, "rb") do |read_file|
        saved_file.write(read_file.read)
      end
    end
  rescue => e
    message = "Problem with dowload: #{file_name} -> #{e}"
    logger.info message
    report_pushover(message)
    exit
  end

  # Decompress Plex
  begin
    logger.info "Decompressing Plex"
    FileUtils.cd("#{Dir.home}/private") do
      system "dpkg -x #{file_name} plex"
    end
  rescue => e
    message = "Problem decompressing Plex -> #{e}"
    logger.info message
    report_pushover(message)
    exit
  end

  # Kill Plex
  begin
    logger.info "Restarting Plex"
    system('pkill -9 -fu "$(whoami)" "plexmediaserver"')
    system('pkill -9 -fu "$(whoami)" "Plex EAE Service"')
  rescue => e
    message = "Problem killing Plex -> #{e}"
    logger.info message
    report_pushover(message)
    exit
  end

  File.open(release_file, "w+") { |file| file.puts latest_release}
  logger.info "Download & Restart complete!"
else
  logger.info "ENV NOT PRODUCTION!"
  logger.info "Download URL: #{download_url}"
end
