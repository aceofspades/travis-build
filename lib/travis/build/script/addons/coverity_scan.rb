module Travis
  module Build
    class Script
      module Addons
        class CoverityScan
          SCAN_URL      = 'http://scan.coverity.local'
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
            authorize_branch
            @script.if "$COVERITY_SCAN_BRANCH == 0", echo: true do
              authorize_quota
              build_command
            end
            @script.else echo: true do
              @script.fold('original_script') { |_| @original_script.script }
            end
            @script.raw "echo -en 'coverity_scan script override:end\\r'"
          end

          private

          def authorize_quota
            scr = <<SH
export SCAN_URL=#{SCAN_URL}
AUTH_RES=`curl -s --form project="$PROJECT_NAME" --form token="$COVERITY_SCAN_TOKEN" $SCAN_URL/api/upload_permitted`
AUTH=`echo $AUTH_RES | ruby -e "require 'rubygems'; require 'json'; puts JSON[STDIN.read]['upload_permitted']"`
if [[ "$AUTH" == "true" ]]; then
  echo -e "\033[33;1mCoverity Scan analysis authorized per quota.\033[0m"
else
  WHEN=`echo $AUTH_RES | ruby -e "require 'rubygems'; require 'json'; puts JSON[STDIN.read]['next_upload_permitted_at']"`
  echo -e "\033[33;1mCoverity Scan analysis NOT authorized until $WHEN.\033[0m"
  exit 1
fi
SH
            @script.raw(scr, echo: true)
          end

          def authorize_branch
            scr = <<SH
export COVERITY_SCAN_BRANCH=`ruby -e "puts '$TRAVIS_BRANCH' =~ /\\A#{@config[:branch_pattern]}\\z/ ? 'true' : 'false'"`
if [[ "$COVERITY_SCAN_BRANCH" == "true" ]]; then
  echo -e "\033[33;1mCoverity Scan analysis selected for branch \\"$TRAVIS_BRANCH\\".\033[0m"
else
  echo -e "\033[33;1mCoverity Scan analysis NOT slected for branch \\"$TRAVIS_BRANCH\\"\033[0m"
fi
SH
            @script.raw(scr, echo: true)
          end

          def extract_original_script
            @original_script = @script.dup
            @script.delete_script
          end

          def build_command
            @script.if "\"$TRAVIS_TEST_RESULT\" == 0", echo: true do |script|
              script.fold('build_coverity') do |script|
                env = []
                env << "PROJECT_SLUG=\"#{@config[:project][:slug]}\""
                env << "PROJECT_NAME=\"#{@config[:project][:name]}\""
                env << "OWNER_EMAIL=\"#{@config[:email]}\""
                env << "BUILD_COMMAND=\"#{@config[:build_command]}\""
                env << "COVERITY_SCAN_BRANCH_PATTERN=#{@config[:branch_pattern]}"
                script.cmd "curl -s #{@config[:build_script_url]} | #{env.join(' ')} bash", echo: true
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
