# -*- coding: utf-8 -*-
require 'rubygems'
require 'bundler/setup'

require 'nokogiri'
require 'open-uri'
require 'hipchat'
require 'psych'

@filename = './config.yml'
@config = Psych::load(File.open(@filename))
exit if @config.nil?

@apikey = @config[:apikey]
@proj   = @config[:igg_project]

class Pledge
  attr_accessor :name, :amount, :level
  @@cache = {}

  def initialize(name, amount, level)
    @name = name
    @amount = amount
    @level = level
  end

  # Hackey method to get all the pledges from indiegogo's lame feed because they
  # don't have an API.
  def self.get_all(proj)
    url = "http://www.indiegogo.com/project/partial/#{proj}?count=100&partial_name=activity_pledges"
    doc = Nokogiri::HTML(open(url))

    pledges = []
    doc.css('.pledge').each do |pledge|
      begin
        name = pledge.css('.pledge-name span').text
        amount = pledge.css('.pledge-amount .notranslate .currency span').text
        level = pledge.css('.pledge-amount .perk-received').text

        pledges << Pledge.new(name, amount, level)
      end
    end

    return pledges
  end

  def id
    self.name.downcase.gsub(/\s/, '_')
  end

  def format_text
    text = ["#{@name} just pledged"]
    text << (@amount == '' ? 'an undisclosed amount' : @amount)
    if @level == ''
      text << "(#{@level})"
    end
    return text.join(' ')
  end

  def cache
    @@cache[id] = self
  end

  def cached?
    @@cache.key?(id)
  end
end

# Spin up a hipChat client.
puts "[Indiegogo] Spining up client for #{@proj}"
client = HipChat::Client.new(@apikey)

# Cache all the current pledges so the bot doesn't spam old shit.
puts "[Indiegogo] Caching current pledges for #{@proj}"
@pledges = Pledge.get_all(@proj).map(&:cache)
puts "[Indiegogo] Cached #{@pledges.length} old pledges."

# Let's start looking for pledges
puts "[Indiegogo] Watching for new pledges for #{@proj}..."
while true do
  queue = []
  # Post the new pledges to the channel and the terminal
  Pledge.get_all(@proj).each do |pledge|
    unless pledge.cached?
      queue << pledge.format_text
      pledge.cache
      puts "[Indiegogo] New pledge cached."
    end
  end

  # OH GOD WHY ARE YOU SO BIG
  exit if queue.length > 5

  queue.each do |post|
    puts "[Indiegogo] #{post}"
    client[@config[:channel]].send(@config[:nick], post, color: 'purple', notify: true)
  end

  sleep 30
end
