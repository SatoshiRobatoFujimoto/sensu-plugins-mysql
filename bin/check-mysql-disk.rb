#!/usr/bin/env ruby
#
# MySQL Disk Usage Check
# ===
#
# Copyright 2011 Sonian, Inc <chefs@sonian.net>
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.
#
# Check the size of the database and compare to crit and warn thresholds

require 'sensu-plugin/check/cli'
require 'mysql'
require 'inifile'

class CheckMysqlDisk < Sensu::Plugin::Check::CLI
  option :host,
         short: '-h',
         long: '--host=VALUE',
         description: 'Database host'

  option :user,
         short: '-u',
         long: '--username=VALUE',
         description: 'Database username'

  option :pass,
         short: '-p',
         long: '--password=VALUE',
         description: 'Database password'

  option :ini,
         description: 'My.cnf ini file',
         short: '-i',
         long: '--ini VALUE'

  option :size,
         short: '-s',
         long: '--size=VALUE',
         description: 'Database size'

  option :warn,
         short: '-w',
         long: '--warning=VALUE',
         description: 'Warning threshold',
         default: '85'

  option :crit,
         short: '-c',
         long: '--critical=VALUE',
         description: 'Critical threshold',
         default: '95'

  option :port,
         description: 'Port to connect to',
         short: '-P PORT',
         long: '--port PORT',
         proc: proc(&:to_i),
         default: '3306'

  option :socket,
         description: 'Socket to use',
         short: '-s SOCKET',
         long: '--socket SOCKET',
         default: nil

  def run
    if config[:ini]
      ini = IniFile.load(config[:ini])
      section = ini['client']
      db_user = section['user']
      db_pass = section['password']
    else
      db_user = config[:user]
      db_pass = config[:pass]
    end
    db_host = config[:host]
    disk_size = config[:size].to_f
    critical_usage = config[:crit].to_f
    warning_usage = config[:warn].to_f

    if [db_host, db_user, db_pass, disk_size].any?(&:nil?)
      unknown 'Must specify host, user, password and size'
    end

    begin
      total_size = 0.0
      db = Mysql.real_connect(config[:host], db_user, db_pass, nil, config[:port], config[:socket])

      results = db.query <<-EOSQL
        SELECT table_schema,
        count(*) TABLES,
        concat(round(sum(table_rows)/1000000,2),'M') rows,
        round(sum(data_length)/(1024*1024*1024),2) DATA,
        round(sum(index_length)/(1024*1024*1024),2) idx,
        round(sum(data_length+index_length)/(1024*1024*1024),2) total_size,
        round(sum(index_length)/sum(data_length),2) idxfrac
        FROM information_schema.TABLES group by table_schema
      EOSQL

      unless results.nil?
        results.each_hash do |row|
          # #YELLOW
          total_size = total_size + row['total_size'].to_f # rubocop:disable Style/SelfAssignment
        end
      end

      disk_use_percentage = total_size / disk_size * 100
      diskstr = "DB size: #{total_size}, disk use: #{disk_use_percentage}%"

      if disk_use_percentage > critical_usage
        critical "Database size exceeds critical threshold: #{diskstr}"
      elsif disk_use_percentage > warning_usage
        warning "Database size exceeds warning threshold: #{diskstr}"
      else
        ok diskstr
      end

    rescue Mysql::Error => e
      errstr = "Error code: #{e.errno} Error message: #{e.error}"
      critical "#{errstr} SQLSTATE: #{e.sqlstate}" if e.respond_to?('sqlstate')

    rescue => e
      critical e

    ensure
      db.close if db
    end
  end
end
