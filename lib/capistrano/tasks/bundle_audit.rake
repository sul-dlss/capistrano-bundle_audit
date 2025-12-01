require 'bundler'
require 'shellwords'
require 'tmpdir'

namespace :deploy do
  namespace :check do
    desc "Audit the Gemfile.lock for known vulnerabilities"
    task :bundle_audit do

      on primary(:app), in: :sequence do |host|

        # Download the relevant files and run bundle-audit on them locally
        Dir.mktmpdir do |dir|
          Dir.chdir dir do
            download! "#{release_path}/Gemfile.lock", "Gemfile.lock"

            run_locally do
              capture %(echo 'gem "bundler-audit"' > Gemfile)

              bundle_audit_output = Bundler.with_unbundled_env do
                capture "bundle-audit check --update #{"--ignore #{Shellwords.join(fetch(:bundle_audit_ignore))}" unless fetch(:bundle_audit_ignore).empty? }"
              end

              # bundle-audit includes failures for both gem vulnerabilities
              # and insecure gem sources, and offers no way to distinguish those cases.
              # unfortunately, we only want to fail when vulnerable gems are required.
              # This should only fail if there is a bundle-audit output AND it has
              # a solution available to upgrade. If no solution is available deploy
              # will still be allowed.
              if bundle_audit_output =~ /Solution: upgrade to/
                warn bundle_audit_output
                fail "Bundle audit failed; update your vulnerable dependencies before deploying"
              else
                debug bundle_audit_output
                info bundle_audit_output.split("\n").last
              end
            end
          end
        end
      end
    end
  end

  after 'bundler:install', 'deploy:check:bundle_audit' unless ENV['SKIP_BUNDLE_AUDIT']
end

namespace :load do
  task :defaults do
    set :bundle_audit_ignore, %W{#{ENV['BUNDLE_AUDIT_IGNORES']}}
    set :skip_bundle_audit, !!ENV['SKIP_BUNDLE_AUDIT']
  end
end
