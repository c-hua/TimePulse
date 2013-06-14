require 'yaml'
require 'pathname'

LOCAL_SQL_PATH = 'sqldumps/'
REMOTE_SQL_PATH = 'db_backups/'

#
# Capistrano sync.rb task for syncing databases and directories between the
# local development environment and different multi_stage environments. You
# cannot sync directly between two multi_stage environments, always use your
# local machine as loop way.
#
# This version pulls credentials for the remote database from
# {shared_path}/config/database.yml on the remote server, thus eliminating
# the requirement to have your production database credentials on your local
# machine or in your repository.
#
# Author: Michael Kessler aka netzpirat
# Gist: 111597
#
# Edits By: Evan Dorn, Logical Reality Design, March 2010
# Gist: 339471
#
# Released under the MIT license.
# Kindly sponsored by Screen Concept, www.screenconcept.ch
#

Capistrano::Configuration.instance.load do
  namespace :remote_sync do

    after "deploy:setup", "sync:setup"

    desc <<-DESC
  Creates the sync dir in shared path. The sync directory is used to keep
  backups of database dumps and archives from synced directories. This task will
  be called on 'deploy:setup'
  DESC
    task :setup do
      run "cd #{shared_path}; mkdir sync"
    end

    namespace :down do

      desc <<-DESC
  Syncs the database and declared directories from the selected multi_stage environment
  to the local development environment. This task simply calls both the 'sync:down:db' and
  'sync:down:fs' tasks.
  DESC
      task :default do
        db and fs
      end

      desc <<-DESC
  Syncs database from the selected mutli_stage environement to the local develoment environment.
  The database credentials will be read from your local config/database.yml file and a copy of the
  dump will be kept within the shared sync directory. The amount of backups that will be kept is
  declared in the sync_backups variable and defaults to 5.
  DESC
      task :db, :roles => :db, :only => { :primary => true } do

        filename = "synced_#{stage}.sql.bz2"
        local_filename = File.join(LOCAL_SQL_PATH, filename)
        remote_filename = File.join(shared_path, REMOTE_SQL_PATH, 'latest.sql.bz2')
        Dir.mkdir(LOCAL_SQL_PATH) unless Dir.exists?(LOCAL_SQL_PATH)

        # Remote DB dump
        #run "cd #{current_path}; mkdir -p #{REMOTE_SQL_PATH}"
        #run "cd #{current_path}; RAILS_ENV=#{stage} bundle exec
        #rakedb:backups:create[#{REMOTE_SQL_PATH},#{filename}]"

        download remote_filename, local_filename

        # Local DB importcd /var/cd
        system "bundle exec rake db:backups:restore[#{local_filename}]"

        logger.important "sync database from the stage '#{stage}' to local finished"
      end

      desc <<-DESC
  Sync declared directories from the selected multi_stage environment to the local development
  environment. The synced directories must be declared as an array of Strings with the sync_directories
  variable. The path is relative to the rails root.
  DESC
      task :fs, :roles => :web, :once => true do

        server, port = host_and_port

        Array(fetch(:sync_directories, [])).each do |syncdir|
          unless File.directory? "#{syncdir}"
            logger.info "create local '#{syncdir}' folder"
            Dir.mkdir "#{syncdir}"
          end
          logger.info "sync #{syncdir} from #{server}:#{port} to local"
          destination, base = Pathname.new(syncdir).split
          system "rsync --verbose --archive --compress --copy-links --delete --stats --rsh='ssh -p #{port}' #{user}@#{server}:#{current_path}/#{syncdir} #{destination.to_s}"
        end

        logger.important "sync filesystem from the stage '#{stage}' to local finished"
      end

    end

    namespace :up do

      desc <<-DESC
  Syncs the database and declared directories from the local development environment
  to the selected multi_stage environment. This task simply calls both the 'sync:up:db' and
  'sync:up:fs' tasks.
  DESC
      task :default do
        db and fs
      end

      desc <<-DESC
  Syncs database from the local develoment environment to the selected mutli_stage environement.
  The database credentials will be read from your local config/database.yml file and a copy of the
  dump will be kept within the shared sync directory. The amount of backups that will be kept is
  declared in the sync_backups variable and defaults to 5.
  DESC
      task :db, :roles => :db, :only => { :primary => true } do

        filename = "database.#{stage}.#{Time.now.strftime '%Y-%m-%d_%H:%M:%S'}.sql.bz2"
        local_filename = LOCAL_SQL_PATH + filename

        on_rollback do
          delete "#{shared_path}/sync/#{filename}"
          system "rm -f #{filename}"
        end

        # Make a backup before importing
        username, password, database, host = remote_database_config(rails_env)
        p "hostname was #{host}"
        hostcmd = host.nil? ? '' : "-h #{host}"
        run "mysqldump -u #{username} --password='#{password}' #{hostcmd} #{database} | bzip2 -9 > #{shared_path}/sync/#{filename}" do |channel, stream, data|
          puts data
        end

        # Local DB export
        filename = "dump.local.#{Time.now.strftime '%Y-%m-%d_%H:%M:%S'}.sql.bz2"
        username, password, database = database_config('development')
        system "mkdir -p #{LOCAL_SQL_PATH}"
        system "mysqldump -u #{username} --password='#{password}' #{database} | bzip2 -9 > #{local_filename}"
        upload local_filename, "#{shared_path}/sync/#{filename}"
        system "rm -f #{local_filename}"

        # Remote DB import
        username, password, database, host = remote_database_config(rails-env)
        hostcmd = host.nil? ? '' : "-h #{host}"
        run "bzip2 -d -c #{shared_path}/sync/#{filename} | mysql -u #{username} --password='#{password}' #{hostcmd} #{database}; rm -f #{shared_path}/sync/#{filename}"
        purge_old_backups "database"

        logger.important "sync database from local to the stage '#{stage}' finished"
      end

      desc <<-DESC
  Sync declared directories from the local development environement to the selected multi_stage
  environment. The synced directories must be declared as an array of Strings with the sync_directories
  variable. The path is relative to the rails root.
  DESC
      task :fs, :roles => :web, :once => true do

        server, port = host_and_port
        Array(fetch(:sync_directories, [])).each do |syncdir|
          destination, base = Pathname.new(syncdir).split
          if File.directory? "#{syncdir}"
            # Make a backup
            logger.info "backup #{syncdir}"
            run "tar cjf #{shared_path}/sync/#{base}.#{Time.now.strftime '%Y-%m-%d_%H:%M:%S'}.tar.bz2 #{current_path}/#{syncdir}"
            purge_old_backups "#{base}"
          else
            logger.info "Create '#{syncdir}' directory"
            run "mkdir #{current_path}/#{syncdir}"
          end

          # Sync directory up
          logger.info "sync #{syncdir} to #{server}:#{port} from local"
          system "rsync --verbose --archive --compress --keep-dirlinks --delete --stats --rsh='ssh -p #{port}' #{syncdir} #{user}@#{server}:#{current_path}/#{destination.to_s}"
        end
        logger.important "sync filesystem from local to the stage '#{stage}' finished"
      end

    end

    #
    # Reads the database credentials from the local config/database.yml file
    # +db+ the name of the environment to get the credentials for
    # Returns username, password, database
    #
    def database_config(db)
      database = YAML::load_file('config/database.yml')
      db = database["#{db}"]
      return (db['username']  || db['user']), db['password'], db['database'], db['host']
    end


    #
    # Reads the database credentials from the remote config/database.yml file
    # +db+ the name of the environment to get the credentials for
    # Returns username, password, database
    #
    def remote_database_config(db)
      remote_config = capture("cat #{shared_path}/config/database.yml")
      database = YAML::load(remote_config)
      return database["#{db}"]['username'], database["#{db}"]['password'], database["#{db}"]['database'], database["#{db}"]['host']
    end

    #
    # Returns the actual host name to sync and port
    #
    def host_and_port
      return roles[:web].servers.first.host, ssh_options[:port] || roles[:web].servers.first.port || 22
    end

    #
    # Purge old backups within the shared sync directory
    #
    def purge_old_backups(base)
      count = fetch(:sync_backups, 5).to_i
      backup_files = capture("ls -xt #{shared_path}/sync/#{base}*").split.reverse
      if count >= backup_files.length
        logger.important "no old backups to clean up"
      else
        logger.info "keeping #{count} of #{backup_files.length} sync backups"
        delete_backups = (backup_files - backup_files.last(count)).join(" ")
        try_sudo "rm -rf #{delete_backups}"
      end
    end

  end
end
