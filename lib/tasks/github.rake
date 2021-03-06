namespace :github do
  desc 'Sync github users'
  task sync_users: :environment do
    RepositoryUser.visible.where(last_synced_at: nil).limit(100).select('login').each(&:async_sync)
    RepositoryUser.visible.order('last_synced_at ASC').limit(100).select('login').each(&:async_sync)
  end

  desc 'Sync github orgs'
  task sync_orgs: :environment do
    RepositoryOrganisation.visible.order('last_synced_at ASC').limit(200).select('login').each(&:async_sync)
  end

  desc 'Sync github repos'
  task sync_repos: :environment do
    scope = Repository.source.open_source
    scope.where(last_synced_at: nil).limit(100).each(&:update_all_info_async)
    scope.order('last_synced_at ASC').limit(100).each(&:update_all_info_async)
  end

  desc 'Update source rank'
  task update_source_rank: :environment do
    Repository.source.open_source.where(rank: nil).order('repositories.stargazers_count DESC').limit(1000).select('id').each(&:update_source_rank_async)
  end

  desc 'Sync github issues'
  task sync_issues: :environment do
    scope = Issue.includes(:repository)
    scope.help_wanted.indexable.order('last_synced_at ASC').limit(100).each(&:sync)
    scope.first_pull_request.indexable.order('last_synced_at ASC').limit(100).each(&:sync)
    scope.order('last_synced_at ASC').limit(100).each(&:sync)
  end

  desc 'Sync trending github repositories'
  task update_trending: :environment do
    trending = Repository.open_source.pushed.maintained.recently_created.hacker_news.limit(30).select('id')
    brand_new = Repository.open_source.pushed.maintained.recently_created.order('created_at DESC').limit(60).select('id')
    (trending + brand_new).uniq.each{|g| RepositoryDownloadWorker.perform_async(g.id) }
  end

  desc 'Download all github users'
  task download_all_users: :environment do
    since = REDIS.get('githubuserid').to_i

    while true
      users = AuthToken.client(auto_paginate: false).all_users(since: since)
      users.each do |o|
        begin
          if o.type == "Organization"
            RepositoryOrganisation.find_or_create_by(uuid: o.id) do |u|
              u.login = o.login
            end
          else
            RepositoryUser.create_from_host('GitHub', o)
          end
        rescue
          nil
        end
      end
      since = users.last.id + 1
      REDIS.set('githubuserid', since)
      puts '*'*20
      puts "#{since} - #{'%.4f' % (since.to_f/250000)}%"
      puts '*'*20
      sleep 0.5
    end
  end
end
