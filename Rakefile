require "bundler/gem_tasks"

require "bundler/setup"
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
if defined?(Rails)
  load "./lib/dynamoid/tasks/database.rake"
end

require "rake"
require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList["spec/**/*_spec.rb"]
end

require "yard"
YARD::Rake::YardocTask.new do |t|
  t.files   = ["lib/**/*.rb", "README", "LICENSE"] # optional
  t.options = ["-m", "markdown"] # optional
end

desc "Publish documentation to gh-pages"
task :publish do
  Rake::Task["yard"].invoke
  `git add .`
  `git commit -m 'Regenerated documentation'`
  `git checkout gh-pages`
  `git clean -fdx`
  `git checkout master -- doc`
  `cp -R doc/* .`
  `git rm -rf doc/`
  `git add .`
  `git commit -m 'Regenerated documentation'`
  `git pull`
  `git push`
  `git checkout master`
end

require "wwtd/tasks"

task :default => :spec
