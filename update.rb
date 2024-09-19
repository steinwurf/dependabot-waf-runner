require "dependabot/credential"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/config/file_fetcher"
require "dependabot/simple_instrumentor"

require "dependabot/waf"

$options = {
  credentials: [],
  provider: "github",
  directory: "/",
  dependency_names: nil,
  branch: nil,
  cache_steps: [],
  write: false,
  reject_external_code: false,
  requirements_update_strategy: nil,
  commit: nil,
  updater_options: {},
  security_advisories: [],
  security_updates_only: false,
  vendor_dependencies: false,
  ignore_conditions: [],
  pull_request: false
}

unless ENV["LOCAL_GITHUB_ACCESS_TOKEN"].to_s.strip.empty?
  $options[:credentials] << Dependabot::Credential.new(
    {
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => ENV.fetch("LOCAL_GITHUB_ACCESS_TOKEN", nil)
    }
  )
end

$repo_name = ENV["GITHUB_REPO"]
directory = ENV["DIRECTORY_PATH"] || "/"
$package_manager = "waf"

def fetch_files(fetcher)
  if $repo_contents_path
    if $options[:cache_steps].include?("files") && Dir.exist?($repo_contents_path)
      puts "=> reading cloned repo from #{$repo_contents_path}"
    else
      puts "=> cloning into #{$repo_contents_path}"
      FileUtils.rm_rf($repo_contents_path)
      fetcher.clone_repo_contents
    end
    if $options[:commit]
      Dir.chdir($repo_contents_path) do
        puts "=> checking out commit #{$options[:commit]}"
        Dependabot::SharedHelpers.run_shell_command("git checkout #{$options[:commit]}")
      end
    end
    fetcher.files
  end

rescue StandardError => e
  error_details = Dependabot.fetcher_error_details(e)
  raise unless error_details

  puts " => handled error whilst fetching dependencies: #{error_details.fetch(:"error-type")} " \
       "#{error_details.fetch(:"error-detail")}"

  []
end

def update_checker_for(dependency)
  Dependabot::UpdateCheckers.for_package_manager($package_manager).new(
    dependency: dependency,
    dependency_files: $files,
    credentials: $options[:credentials],
    repo_contents_path: $repo_contents_path,
    requirements_update_strategy: $options[:requirements_update_strategy],
    options: $options[:updater_options]
  )
end

def log_conflicting_dependencies(conflicting_dependencies)
  return unless conflicting_dependencies.any?

  puts " => The update is not possible because of the following conflicting " \
       "dependencies:"

  conflicting_dependencies.each do |conflicting_dep|
    puts "   #{conflicting_dep['explanation']}"
  end
end

$source = Dependabot::Source.new(
  provider: $options[:provider],
  repo: $repo_name,
  directory: $options[:directory],
  branch: $options[:branch],
  commit: $options[:commit]
)

$repo_contents_path = File.expand_path(File.join("tmp", $repo_name.split("/")))

fetcher_args = {
  source: $source,
  credentials: $options[:credentials],
  repo_contents_path: $repo_contents_path,
  options: $options[:updater_options]
}

# Fetch dependency files

puts "Fetching #{$package_manager} dependency files for #{$repo_name}"
fetcher = Dependabot::FileFetchers.for_package_manager($package_manager).new(**fetcher_args)

$files = fetch_files(fetcher)
commit = fetcher.commit
return if $files.empty?

# Parse the dependency files
puts "=> parsing dependency files"
parser = Dependabot::FileParsers.for_package_manager($package_manager).new(
  dependency_files: $files,
  repo_contents_path: $repo_contents_path,
  source: $source,
  credentials: $options[:credentials],
  reject_external_code: $options[:reject_external_code]
)



dependencies = parser.parse

if $options[:dependency_names].nil?
  dependencies.select!(&:top_level?)
else
  dependencies.select! do |d|
    $options[:dependency_names].include?(d.name.downcase)
  end
end

puts "=> updating #{dependencies.count} dependencies: #{dependencies.map(&:name).join(', ')}"

checker_count = 0

updated_deps_collection = []

dependencies.each do |dep|
  checker_count += 1
  checker = update_checker_for(dep)
  name_version = "\n=== #{dep.name} (#{dep.version})"
  vulnerable = checker.vulnerable? ? " (vulnerable 🚨)" : ""
  puts name_version + vulnerable

  puts " => checking for updates #{checker_count}/#{dependencies.count}"
  puts " => latest available version is #{checker.latest_version}"

  if $options[:security_updates_only] && !checker.vulnerable?
    if checker.version_class.correct?(checker.dependency.version)
      puts "    (no security update needed as it's not vulnerable)"
    else
      puts "    (can't update vulnerable dependencies for " \
           "projects without a lockfile as the currently " \
           "installed version isn't known 🚨)"
    end
    next
  end

  if checker.vulnerable?
    if checker.lowest_security_fix_version
      puts " => earliest available non-vulnerable version is " \
           "#{checker.lowest_security_fix_version}"
    else
      puts " => there is no available non-vulnerable version"
    end
  end

  if checker.up_to_date?
    puts "    (no update needed as it's already up-to-date)"
    next
  end

  latest_allowed_version = if checker.vulnerable?
    checker.lowest_resolvable_security_fix_version
  else
    checker.latest_resolvable_version
  end
  puts " => latest allowed version is #{latest_allowed_version || dep.version}"

  requirements_to_unlock =
    if !checker.requirements_unlocked_or_can_be?
      if checker.can_update?(requirements_to_unlock: :none) then :none
      else :update_not_possible
      end
    elsif checker.can_update?(requirements_to_unlock: :own) then :own
    elsif checker.can_update?(requirements_to_unlock: :all) then :all
    else :update_not_possible
    end

  puts " => requirements to unlock: #{requirements_to_unlock}"

  if checker.respond_to?(:requirements_update_strategy)
    puts " => requirements update strategy: " \
         "#{checker.requirements_update_strategy}"
  end

  if requirements_to_unlock == :update_not_possible
    if checker.vulnerable? || $options[:security_updates_only]
      puts "    (no security update possible 🙅‍♀️)"
    else
      puts "    (no update possible 🙅‍♀️)"
    end

    log_conflicting_dependencies(checker.conflicting_dependencies)
    next
  end

  updated_deps = checker.updated_dependencies(
    requirements_to_unlock: requirements_to_unlock
  )

  updated_deps_collection.push(*updated_deps)

end

if updated_deps_collection.empty?
  puts "Done"
  return
end 

# Generate updated dependency files
updated_deps_collection.each do |dep|
  print " - Updating #{dep.name} (from #{dep.version}) \n"
end

updater = Dependabot::FileUpdaters.for_package_manager($package_manager).new(
  dependencies: updated_deps_collection,
  dependency_files: $files,
  credentials: $options[:credentials],
)

updated_files = updater.updated_dependency_files

# Create a pull request for the update
return unless $options[:pull_request]
pr_creator = Dependabot::PullRequestCreator.new(
  source: $source,
  base_commit: commit,
  dependencies: updated_deps_collection,
  files: updated_files,
  credentials: $options[:credentials],
  assignees: [(ENV["PULL_REQUESTS_ASSIGNEE"])&.to_i],
  label_language: true
)

pull_request = pr_creator.create
puts " submitted"

puts "Done"