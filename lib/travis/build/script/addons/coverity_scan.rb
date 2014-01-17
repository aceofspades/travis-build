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

          def install
            @script.fold('install_coverity') do |script|
              script.cmd "if [ \"$TRAVIS_BRANCH\" == \"coverity_scan\" ]; then"
              script.cmd download_build_utility, assert: false, echo: false
              script.cmd "fi"
            end
          end

          # This method consumes the script method of the caller, calling it or the Coverity Scan
          #   script depending on the TRAVIS_BRANCH env variable.
          # The Coverity Scan build therefore overrides the default script, but only on the
          #   coverity_scan branch.
          def script
            extract_original_script


            #@script.raw "export TRAVIS_TEST_RESULT=1", echo: true



            @script.raw "echo -en 'coverity_scan script override:start\\r'"
            @script.if "\"$TRAVIS_BRANCH\" == \"coverity_scan\"", echo: true do
              build_command
              submit_results
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
                script.cmd export_env, assert: false, echo: true
                script.cmd "export PATH=#{cov_analysis_dir}/bin:$PATH", assert: false, echo: true
                script.cmd "COVERITY_UNSUPPORTED=1 cov-build --dir cov-int #{@config[:build_command]}",
                    assert: false, echo: true
              end
            end
            @script.else echo:true do |script|
              script.raw "echo -e \"\033[33;1mSkipping build_coverity due to previous error\033[0m\""
            end
          end

          def submit_results
            @script.if "\"$TRAVIS_TEST_RESULT\" == 0", echo: true do
              @script.fold('submit_coverity_results') do |script|
                cmd = <<-BASH.squeeze(' ').lines.map { |s| s.strip }.join("\n") << "\n"
                  tar czf cov-int.tgz cov-int
                  curl \
                  --form project="#{@config[:project][:name]}" \
                  --form token=$COVERITY_SCAN_TOKEN \
                  --form email="#{@config[:email]}" \
                  --form file=@cov-int.tgz \
                  --form version="#{@config[:project][:version]}" \
                  --form description="#{@config[:project][:description]}" \
                  #{UPLOAD_URL}
                BASH
                script.cmd cmd, assert: false, echo: true
              end
            end
            @script.else echo:true do |script|
              script.raw "echo -e \"\033[33;1mSkipping submit_coverity_results due to previous error\033[0m\""
            end
          end

          private

          def download_url
            "https://scan.coverity.com/download/$COVERITY_PLATFORM"
          end

          def download_build_utility
            <<-BASH.squeeze(' ').lines.map { |s| s.strip }.join("\n") << "\n"
              #{export_env}
              echo -e \"\033[33;1mLooking for #{cov_analysis_dir}...\033[0m\"
              if [ -d #{cov_analysis_dir} ]
              then
                echo -e \"\033[33;1mUsing existing Coverity Build Utility\033[0m\"
              else
                sudo mkdir -p #{cov_analysis_base_dir}/versions
                sudo chown -R $USER #{cov_analysis_base_dir}
                if [ ! -f #{TMP_TAR} ]; then
                  echo -e \"\033[33;1mDownloading Coverity Build Utility\033[0m\"
                  wget -O #{TMP_TAR} #{download_url} --post-data "token=$COVERITY_SCAN_TOKEN&project=#{@config[:project][:name]}"
                  if [ $? -ne 0 ]; then
                    echo -e \"\033[33;1mError downloading Coverity Build Utility\033[0m\"
                    exit 1
                  fi
                fi
                pushd #{cov_analysis_base_dir}/versions
                echo -e \"\033[33;1mExtracting Coverity Build Utility\033[0m\"
                tar xf #{TMP_TAR}
                if [ $? -ne 0 ]; then
                  echo -e \"\033[33;1mError untarring Coverity Build Utility\033[0m\"
                  exit 1
                else
                  DIR=`tar tf #{TMP_TAR} | head -1`
                  ln -s #{cov_analysis_base_dir}/versions/$DIR #{cov_analysis_dir}
                fi
                popd
              fi
            BASH
          end

          def cov_analysis_base_dir
            "#{INSTALL_DIR}/cov-analysis"
          end

          def cov_analysis_dir
            "#{cov_analysis_base_dir}/cov-analysis-$COVERITY_PLATFORM"
          end

          def export_env
            %q{export COVERITY_PLATFORM=`uname`}
          end

        end
      end
    end
  end
end
