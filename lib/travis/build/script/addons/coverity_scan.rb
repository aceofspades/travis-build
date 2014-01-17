module Travis
  module Build
    class Script
      module Addons
        class CoverityScan
          UPLOAD_URL    = 'http://scan5.coverity.com/cgi-bin/upload.py'
          TMP_TAR       = '/tmp/cov-analysis.tar.gz'
          INSTALL_DIR   = '/usr/local'

          def initialize(script, config)
            @script = script
            @config = config.respond_to?(:to_hash) ? config.to_hash : {}
          end

          # This method consumes the script method of the caller, calling it or the Coverity Scan
          #   script depending on the TRAVIS_BRANCH env variable.
          # The Coverity Scan build therefore overrides the default script, but only on the
          #   coverity_scan branch.
          def script
            extract_original_script
            @script.raw "echo -en 'coverity_scan script override:start\\r'"
            @script.if "$TRAVIS_BRANCH =~ #{@config[:branch_pattern]}", echo: true do
              build_command
            end
            @script.else echo: true do
              @script.fold('original_script') { |_| @original_script.script }
            end
            @script.raw "echo -en 'coverity_scan script override:end\\r'"
          end

          private

          def extract_original_script
            @original_script = @script.dup
            @script.delete_script
          end

          def build_command
            @script.if "\"$TRAVIS_TEST_RESULT\" == 0", echo: true do |script|
              script.fold('build_coverity') do |script|
                script.cmd "export PROJECT_SLUG=\"#{@config[:project][:slug]}\""
                script.cmd "export PROJECT_NAME=\"#{@config[:project][:name]}\""
                script.cmd "export OWNER_EMAIL=\"#{@config[:email]}\""
                script.cmd "export MAKE_COMMAND=\"#{@config[:build_command}\""
                script.cmd "export COVERITY_SCAN_BRANCH_PATTERN=#{@config[:branch_pattern]}"
                script.cmd "curl #{@config[:build_script_url]} | sh", echo: true
              end
            end
            @script.else echo:true do |script|
              script.raw "echo -e \"\033[33;1mSkipping build_coverity due to previous error\033[0m\""
            end
          end

        end
      end
    end
  end
end
