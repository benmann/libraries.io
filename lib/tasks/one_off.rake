namespace :one_off do
  # put your one off tasks here and delete them once they've been ran
  desc 'get popular repos'
  task update_popular_repos: :environment do
    Project.popular_languages(:facet_limit => 20).map(&:term).each do |language|
      AuthToken.client.search_repos("language:#{language} stars:<300", sort: 'stars').items.each do |repo|
        GithubRepository.create_from_hash repo.to_hash
      end
    end
  end

  desc 'get popular users'
  task update_popular_users: :environment do
    Project.popular_languages(:facet_limit => 20).map(&:term).each do |language|
      AuthToken.client.search_users("language:#{language} followers:<500", sort: 'followers').items.each do |item|
        user = GithubUser.find_or_create_by(github_id: item.id) do |u|
          u.login = item.login
          u.user_type = item.type
          u.name = item.name
          u.company = item.company
          u.blog = item.blog
          u.location = item.location
        end
      end
    end
  end

  desc 'fix git urls'
  task fix_git_urls: :environment do
    Project.where('repository_url LIKE ?', 'https://github.com/git+%').find_each do |p|
      p.repository_url.gsub!('https://github.com/git+', 'https://github.com/')
      p.save
    end
  end

  desc 'delete duplicate repos'
  task delete_duplicate_repos: :environment do
    records_array = ActiveRecord::Base.connection.execute('SELECT lower(full_name) FROM "github_repositories" GROUP BY lower(full_name) HAVING count(*) > 1')
    repo_names = records_array.map{|k,v| k['lower']}

    repo_names.each do |repo_name|
      repos = GithubRepository.where('lower(full_name) = ?', repo_name.downcase).includes(:projects, :repository_subscriptions)
      # keep one repo

      with_projects = repos.select do |repo|
        repo.repository_subscriptions.empty?
      end

      # remove if no projects or repository_subscriptions
      for_removal = with_projects.select do |repo|
        repo.projects.empty?
      end

      keep = nil

      if for_removal.length == with_projects.length
        keep = for_removal.first
      end

      if for_removal.length.zero?
        keep = with_projects.first
      end

      if keep.present?
        with_projects.each do |repo|
          next if repo == keep
          repo.projects.each do |project|
            project.github_repository_id = keep.id
            project.save
          end
          repo.destroy
        end
      end

      for_removal.each_with_index do |repo, index|
        next if keep.present? && repo == keep
        repo.destroy
      end
    end
  end

  desc 'delete duplicate users'
  task delete_duplicate_users: :environment do
    records_array = ActiveRecord::Base.connection.execute('SELECT lower(login) FROM "github_users" GROUP BY lower(login) HAVING count(*) > 1')
    user_logins = records_array.map{|k,v| k['lower']}

    user_logins.each do |user_login|
      users = GithubUser.where('lower(login) = ?', user_login.downcase)

      users.each_with_index do |user, index|
        next if index.zero?
        user.destroy
      end
    end
  end

  desc 'delete duplicate orgs'
  task delete_duplicate_orgs: :environment do
    records_array = ActiveRecord::Base.connection.execute('SELECT lower(login) FROM "github_organisations" GROUP BY lower(login) HAVING count(*) > 1')
    user_logins = records_array.map{|k,v| k['lower']}

    user_logins.each do |user_login|
      users = GithubOrganisation.where('lower(login) = ?', user_login.downcase)

      users.each_with_index do |user, index|
        next if index.zero?
        user.destroy
      end
    end
  end

  desc 'download orgs'
  task download_orgs: :environment do
    GithubUser.find_each do |user|
      user.download_orgs
    end
  end

  desc 'update user repos'
  task update_user_repos: :environment do
    User.find_each do |user|
      user.update_repo_permissions
      user.adminable_github_repositories.each{|g| g.update_all_info_async user.token }
    end
  end

  desc 'mark users who need token upgrade'
  task token_upgrade: :environment do
    User.where.not(public_repo_token: nil).update_all(token_upgrade: true)
    User.where.not(private_repo_token: nil).update_all(token_upgrade: true)
  end
end
