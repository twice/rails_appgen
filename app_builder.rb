class AppBuilder < Rails::AppBuilder
  def initialize(generator)
    super(generator)

    at_exit do
      postprocess
    end
  end

  def readme
    create_file "README.md", "The #{app_name} Project."
  end

  def gemfile
    create_file 'Gemfile', gems_list
  end

  def test
  end

  def database_yml
    create_file "config/database.yml", postgres_config
  end

  def leftovers
    remove_default_rails_files
    clean_route_file
    set_initialize_on_precompile
    select_puma_or_thin_deployment
  end

  # The last step: postprocess: should occur after bundle install
  def postprocess
    configure_rspec
    configure_database_cleaner
    configure_strong_parameters
    rake 'db:create'
    generate "simple_form:install", "--bootstrap"
    setup_twitter_bootstrap
    setup_flash_messages
    configure_action_mailer
    generate_home_controller
    configure_devise
    rake 'db:migrate'
    configure_rvm_gemset
    git :init
  end

  private 

    def remove_default_rails_files
      remove_file "public/index.html"
      remove_file "app/assets/images/rails.png"
    end

    def clean_route_file
      gsub_file 'config/routes.rb', /Application\.routes\.draw do.*end/m,
        "Application.routes.draw do\nend"
    end

    def set_initialize_on_precompile
      inject_into_file 'config/application.rb', 
        "\n    config.assets.initialize_on_precompile = false",
        after: 'config.assets.enabled = true'
    end

    def configure_rspec
      generate 'rspec:install'
      append_file '.rspec','--profile'
      configure_rspec_generator
      expect_syntax = <<-RUBY

  config.expect_with :rspec do |c|
     c.syntax = :expect
  end

      RUBY

      inject_into_file 'spec/spec_helper.rb', expect_syntax, after: 'RSpec.configure do |config|'
      comment_lines 'spec/spec_helper.rb', /config\.fixture_path/

    end

    def configure_rspec_generator
      application do
        <<-RUBY
    config.generators do |generate|
      generate.test_framework :rspec
      generate.helper false
      generate.stylesheets false
      generate.javascript_engine false
      generate.view_specs false
    end
        RUBY
      end
    end

    def generate_home_controller
      if yes? "Do you want to generate a home controller? (y/n)"
        controller_name = ask(" Supply the home controller name: ").underscore
        generate :controller, "#{controller_name} index"
        route "root to: '#{controller_name}\#index'"
        gsub_file 'config/routes.rb', /get\s+"\w+\/\w+"/, ''
      end
    end

    def configure_database_cleaner
      gsub_file 'spec/spec_helper.rb',
        'config.use_transactional_fixtures = true',
        'config.use_transactional_fixtures = false'
      create_file 'spec/support/database_cleaner.rb', database_cleaner_config
    end

    def configure_strong_parameters
      gsub_file 'config/application.rb',/whitelist_attributes\s*=\s*true/,
        'whitelist_attributes = false'

      initializer "strong_parameters.rb" do
        <<-RUBY.strip_heredoc
          ActiveRecord::Base.send :include, ActiveModel::ForbiddenAttributesProtection
        RUBY
      end
    end

    def setup_flash_messages
      empty_directory 'app/views/application'
      create_file 'app/views/application/_flashes.html.erb', flash_template
    end

    def configure_action_mailer
      inject_into_file 'config/environments/development.rb', mailer_config,before: /^end/
      inject_into_file 'config/environments/production.rb', mailer_config,before: /^end/
      inject_into_file 'config/environments/development.rb', gmail_config,before: /^end/
      inject_into_file 'config/environments/production.rb', mandrill_config,before: /^end/
    end

    def select_puma_or_thin_deployment
      server_name = ask("which server do you prefer? enter 'thin' or 'puma'").downcase
      if server_name == 'thin'
        thin_config 
      elsif server_name == 'puma'
        puma_config
      else
        say "please enter either 'thin' or 'puma'"
        select_puma_or_thin_deployment
      end
    end

    def configure_devise
      generate 'devise:install'
      if yes? "Do you want to generate devise views for customization? (y/n)"
        generate 'devise:views'
      end
      generate 'devise', 'User'
    end

    def mailer_config
      <<-RUBY.strip_heredoc

        # Action mailer settings
        config.action_mailer.default_url_options = { host: 'localhost:3000' }
        config.action_mailer.delivery_method = :smtp
        config.action_mailer.perform_deliveries = false
        config.action_mailer.raise_delivery_errors = false
        config.action_mailer.default charset: 'utf-8'

      RUBY
    end

    def gmail_config
      <<-RUBY.strip_heredoc

        # GMail action mailer settings
        #config.action_mailer.smtp_settings = {
        # address: 'smtp.gmail.com',
        # port: 587,
        # domain: 'example.com',
        # authentication: 'plain',
        # enable_starttls_auto: true,
        # user_name: ENV["GMAIL_USERNAME"],
        # password: ENV["GMAIL_PASSWORD"]
        #}

      RUBY
    end

    def mandrill_config
      <<-RUBY.strip_heredoc

        # Mandrill action mailer configuration: uncomment if you are using mandrill
        # config.action_mailer.smtp_settings = {
        #   address:  'smtp.mandrillapp.com',
        #   port:   25,
        #   user_name: ENV["MANDRILL_USERNAME"],
        #   password: ENV["MANDRILL_API_KEY"]
        # }

      RUBY
    end

    def puma_config
      say 'configuring puma jruby'
      inject_into_file 'Gemfile', 
        "ruby '#{RUBY_VERSION}', engine: 'jruby', engine_version: '1.7.2'",
        after: "source 'https://rubygems.org'\n"
      inject_into_file 'Gemfile', "\ngem 'puma'", after: "gem 'jquery-rails'"
      create_file 'Procfile', "web: bundle exec rails server puma -p $PORT -e $RACK_ENV"
    end

    def thin_config
      say 'configuring thin server'
      inject_into_file 'Gemfile', "ruby '#{RUBY_VERSION}'\n",
        after: "source 'https://rubygems.org'\n"
      inject_into_file 'Gemfile', "\ngem 'thin'", after: "gem 'jquery-rails'"
    end

    def gems_list
      <<-GEMS.strip_heredoc
        source 'https://rubygems.org'


        gem 'rails', '>= 3.2.12'
        gem 'jquery-rails'
        gem 'devise'
        gem 'simple_form'
        gem 'pg'
        gem 'annotate'
        gem 'strong_parameters'
        gem 'bootstrap-sass', '>= 2.2.2.0'
        gem 'bootstrap-datepicker-rails'

        group :assets do
          gem 'sass-rails'
          gem 'coffee-rails'
          gem 'uglifier'
        end

        group :development do
          gem 'binding_of_caller'
          gem 'better_errors'
          gem 'quiet_assets'
        end

        group :development, :test do
          gem 'rspec-rails'
          gem 'factory_girl_rails'
        end

        group :test do
          gem 'capybara'
          gem 'database_cleaner'
          gem 'launchy'
        end
      GEMS
    end

    def postgres_config
      <<-YAML.strip_heredoc
      development:
        adapter : postgresql
        encoding: unicode
        database: #{app_name}_dev
        pool    : 5

      test:
        adapter : postgresql
        encoding: unicode
        database: #{app_name}_test
      YAML
    end

    def database_cleaner_config
      <<-RUBY.strip_heredoc

      RSpec.configure do |config|
        config.before(:suite) do
          DatabaseCleaner.clean_with(:deletion)
        end

        config.before(:each) do
          DatabaseCleaner.strategy = :transaction
        end

        config.before(:each, :js => true) do
          DatabaseCleaner.strategy = :deletion
        end

        config.before(:each) do
          DatabaseCleaner.start
        end

        config.after(:each) do
          DatabaseCleaner.clean
        end
      end

      RUBY
    end

    def flash_template
      <<-ERB.strip_heredoc
        <% flash.each do |key, value| %>
          <div class='alert alert-<%= key %>' id='<%= key %>'>
            <%= value %>
          </div>
        <% end %>
      ERB
    end

    def setup_twitter_bootstrap
      styles_dir = 'app/assets/stylesheets'
      remove_file "#{styles_dir}/application.css"
      remove_file "app/views/layouts/application.html.erb"
      create_file "#{styles_dir}/application.css.scss", application_css_content
      create_file "#{styles_dir}/bootstrap_overrides.css.scss", bootstrap_overrides
      create_file "app/views/layouts/application.html.erb", application_layout
      create_file "app/views/application/_top_bar_links.html.erb", top_bar_links_partial
      create_file "app/views/application/_devise_links.html.erb", devise_links_partial
      inject_into_file "app/assets/javascripts/application.js", 
                       "//= require bootstrap \n",
                       before: "//= require_tree ."
    end

    def configure_rvm_gemset
      create_file '.rvmrc', 
        "rvm --rvmrc --create ruby-#{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}@#{app_name}"
    end

    def application_css_content
      <<-RUBY.strip_heredoc
      /*
       * The css manifest file that will be compiled to application.css and will include
       * all the files listed or referenced below
       *
       *= require_self
       *= require_tree .
       */

      .content {
          background-color: #fff;
          padding: 20px;
          margin: 0 -20px; /* negative indent the amount of the padding to maintain the grid system */
          /* -webkit-border-radius: 0 0 6px 6px;
          -moz-border-radius: 0 0 6px 6px;
          border-radius: 0 0 6px 6px; */
          -webkit-box-shadow: 0 1px 2px rgba(0,0,0,.15);
          -moz-box-shadow: 0 1px 2px rgba(0,0,0,.15);
          box-shadow: 0 1px 2px rgba(0,0,0,.15);
      }
      RUBY
    end

    def bootstrap_overrides
      <<-RUBY.strip_heredoc
        $navbarBrandColor: #f70078;
        $navbarLinkColor: #59a3fc;

        @import "bootstrap";

        body { 
          background-color: #efd;
        }

        h1,h2, h3, h4 {
          font-weight: 300;
        }

        footer {
          margin-top: 17px;
          padding-top: 17px;
          border-top: solid 1px #eee;
          font-size: 12px;
        }

        a.comp-link {
          color: #0063dc;
        }

        /* @import "bootstrap-responsive" */
      RUBY
    end

    def application_layout
      <<-RUBY.strip_heredoc
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" >
          <meta name="viewport" content="width=device-width, initial-scale=1.0" >
          <title>App Name</title>
          <meta name="author" content="Twice Tshwenyane">
          <%= stylesheet_link_tag    "application", :media => "all" %>
          <%= csrf_meta_tags %>
        </head>
        <body>
          <div class='navbar navbar-static-top'>
            <div class='navbar-inner'>
              <div class='container'>
                <a href='#' class='brand'><%= Rails.application.class.parent_name %></a>
                <%= render 'application/top_bar_links' %>
                <%= render 'application/devise_links' %>
              </div>
            </div>
          </div>

          <div class='container'>
            <div class='content'>
              <div class='row'>
                <div class='span12'>
                  <%= render 'application/flashes' %>
                  <%= yield %>
                </div>
              </div>
              <footer>
                <p>
                  Designed and developed by:
                  <a href="www.twicelift.com" class="comp-link">
                  TWICELIFT
                  </a>
                  (Pty) Ltd. 
                </p>
              </footer>
            </div>
          </div>

          <%= javascript_include_tag "application" %>
          <%= yield :javascript %>
        </body>
        </html>
      RUBY
    end

    def top_bar_links_partial
      <<-ERB.strip_heredoc
        <ul class="nav">
          <li><a href="#">Link</a></li>
          <li><a href="#">Link</a></li>
        </ul>
      ERB
    end

    def devise_links_partial
      <<-ERB.strip_heredoc
        <ul class="nav pull-right">
          <% if user_signed_in? %>
            <li class="dropdown">
              <a href="#" class="dropdown-toggle" data-toggle="dropdown">
                <i class="icon-user"></i>
                <span class="hidden-phone"><%= current_user.email %></span>
                <b class="caret"></b>
              </a>
              <ul class="dropdown-menu">
                <li>
                  <%= link_to edit_user_registration_path do %>
                    <i class="icon-edit"></i>
                    Edit Account
                  <% end %>
                </li>
                <li class="divider"></li>
                <li>
                  <%= link_to destroy_user_session_path, method: 'delete' do %>
                    <i class="icon-off"></i>
                    Logout
                  <% end %>
                </li>
              </ul>
          </li>
          <% else %>
            <li>
              <%= link_to new_user_session_path  do %>
                <i class="icon-lock"></i>
                Log in
              <% end %>
            </li>
            <li>
              <%= link_to new_user_registration_path do %>
                <i class="icon-pencil"></i>
                Register
              <% end %>
            </li>
          <% end %>
        </ul>
      ERB
    end

end
