require 'puppet'
require 'find'

module Puppet::Parser::Functions
    # expects an args containing:
    # args[0] 
    # - The source module and directory inside of templates
    # - We will insert templates/ after the module name in this code
    # - required: true
    #
    # args[1]
    # - The destination directory for the interpolated templates to
    # - go on the client machine
    # - required: true
    #
    # args[2]
    # - The file mode for the finished files on the client
    # - required: false
    # - default: 0600
    #
    # args[3]
    # - The owner of the file
    # - required: false
    # - default: owner of puppet running process
    #
    # args[4]
    # - The group ownership of the file
    # - required: false
    # - default: owner of puppet running process
    #
    newfunction(:recurse_directory, :type => :rvalue) do |args|
        source_dir = args[0]
        destination_dir = args[1]
        file_mode = args[2]
        if not file_mode or file_mode == ''
            file_mode = '0600'
        end
        file_owner = args[3]
        file_group = args[4]
        dir_mode = args[5]

        creatable_resources = Hash.new
        source_dir_array = source_dir.split(/\//)

        # Insert /templates to the modulename as our base search path
        source_dir_array[0] = "#{source_dir_array[0]}/templates"
        search_path = source_dir_array.join('/')

        # Traverse possible multiple modulepath options to determine template location
        moduledir_array = Puppet[:modulepath].split(/:/)
        moduledir_found = 0
        moduledir = ""

        moduledir_array.each do |path|
            # Check to see if the path/search_path exists:
            if FileTest.directory?("#{path}/#{search_path}")
                # If the search_path exists in this modulepath, then we've got our moduledir and it's time to break out of here
                moduledir = path
                moduledir_found = 1
                debug("Template path #{search_path} found in #{path}! Setting moduledir to #{moduledir}.")

                break
            else
                debug("Template path #{search_path} not found in #{path}. Trying next modulepath...")
            end
        end

        if moduledir_found == 0
            abort("ERROR: #{moduledir} Template path #{search_path} not found in any modulepath (" + moduledir_array.to_s + "), please ensure proper source_dir")
        end

        file_path = "#{moduledir}/#{search_path}"

        Find.find(file_path) do |f|
            f.slice!(file_path + "/")
            if f == file_path or f == '' or !f
                next
            end
            if not File.directory?("#{file_path}/#{f}")
                ensure_mode = 'file'
                title = f.gsub(/\.erb$/,'')
                debug("File in loop #{f}")
                debug("Title in loop #{title}")
                destination_full_path = "#{destination_dir}/#{title}"
                file = "#{file_path}/#{f}"
                debug "Retrieving template #{file}"

                wrapper = Puppet::Parser::TemplateWrapper.new(self)
                wrapper.file = file
                begin
                    wrapper.result
                    rescue => detail
                    info = detail.backtrace.first.split(':')
                    raise Puppet::ParseError,
                        "Failed to parse template #{file}:\n  Filepath: #{info[0]}\n  Line: #{info[1]}\n  Detail: #{detail}\n"
                end
                template_content = wrapper.result

                creatable_resources[destination_full_path] = {
                    'ensure' => ensure_mode,
                    'content' => template_content,
                }
                if file_owner
                    creatable_resources[destination_full_path]['owner'] = file_owner
                end
                if file_group
                    creatable_resources[destination_full_path]['group'] = file_group
                end
                if file_mode
                    creatable_resources[destination_full_path]['mode'] = file_mode
                end
            elsif File.directory?("#{file_path}/#{f}") and f != '.' and f != '..'
                title = f
                destination_full_path = "#{destination_dir}/#{title}"
                creatable_resources[destination_full_path] = {
                    'ensure' => 'directory',
                    'owner' => file_owner,
                    'group' => file_group,
                }
                if dir_mode
                    creatable_resources[destination_full_path]['mode'] = dir_mode
                end
            end
        end

        debug("Source Dir #{source_dir}")
        debug("Destination Dir #{destination_dir}")
        debug("Module Dir #{moduledir}")
        debug("File Path #{file_path}")
        debug("Creatable Resources #{creatable_resources}")
        return creatable_resources

    end
end
