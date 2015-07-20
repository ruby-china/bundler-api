require 'rack/test'
require 'spec_helper'
require 'bundler_api/web'
require 'support/gem_builder'
require 'support/etag'

describe BundlerApi::Web do
  include Rack::Test::Methods

  let(:builder) { GemBuilder.new($db) }
  let(:rack_id) { builder.create_rubygem("rack") }

  before do
    builder.create_version(rack_id, "rack")
  end

  def app
    BundlerApi::Web.new($db, $db)
  end

  context "GET /" do
    let(:request) { "/" }

    it "redirects to rubygems.org" do
      get request

      expect(last_response).to be_redirect
      expect(last_response.headers['Location']).
        to eq('https://www.rubygems.org')
    end
  end

  context "GET static files" do
    let(:request) { "/robots.txt" }

    it "redirects to rubygems.org" do
      get request
      expect(last_response).to be_ok
    end
  end

  context "GET nonexistent files'" do
    let(:request) { "/nonexistent" }

    it "redirects to rubygems.org" do
      get request
      expect(last_response).to be_not_found
    end
  end

  context "GET /api/v1/dependencies" do
    let(:request) { "/api/v1/dependencies" }

    context "there are no gems" do
      it "returns an empty string" do
        get request

        expect(last_response).to be_ok
        expect(last_response.body).to eq("")
      end
    end

    context "there are gems" do
      it "returns a marshal dump" do
        result = [{
          name:         'rack', number:       '1.0.0',
          platform:     'ruby',
          rubygems_version: nil,
          ruby_version: nil,
          checksum: nil,
          dependencies: []
        }]

        get "#{request}?gems=rack"

        expect(last_response).to be_ok
        expect(Marshal.load(last_response.body)).to eq(result)
      end
    end
  end


  context "GET /api/v1/dependencies.json" do
    let(:request) { "/api/v1/dependencies.json" }

    context "there are no gems" do
      it "returns an empty string" do
        get request

        expect(last_response).to be_ok
        expect(last_response.body).to eq("")
      end
    end

    context "there are gems" do
      it "returns a marshal dump" do
        result = [{
          "name"             => 'rack',
          "number"           => '1.0.0',
          "platform"         => 'ruby',
          "rubygems_version" =>  nil,
          "ruby_version" => nil,
          "checksum"         => nil,
          "dependencies" => []
        }]

        get "#{request}?gems=rack"

        expect(last_response).to be_ok
        expect(JSON.parse(last_response.body)).to eq(result)
      end
    end
  end

  context "POST /api/v1/add_spec.json" do
    let(:url){ "/api/v1/add_spec.json" }
    let(:payload){ {:name => "rack", :version => "1.0.1",
      :platform => "ruby", :prerelease => false} }

    it "adds the spec to the database" do
      post url, JSON.dump(payload)

      expect(last_response).to be_ok
      res = JSON.parse(last_response.body)
      expect(res["name"]).to eq("rack")
      expect(res["version"]).to eq("1.0.1")
    end
  end

  context "POST /api/v1/remove_spec.json" do
    let(:url){ "/api/v1/remove_spec.json" }
    let(:payload){ {:name => "rack", :version => "1.0.0",
      :platform => "ruby", :prerelease => false} }

    it "removes the spec from the database" do
      post url, JSON.dump(payload)

      expect(last_response).to be_ok
      res = JSON.parse(last_response.body)
      expect(res["name"]).to eq("rack")
      expect(res["version"]).to eq("1.0.0")
    end
  end

  context "GET /quick/Marshal.4.8/:id" do
    it "redirects" do
      get "/quick/Marshal.4.8/rack"

      expect(last_response).to be_redirect
    end
  end

  context "GET /fetch/actual/gem/:id" do
    it "redirects" do
      get "/fetch/actual/gem/rack"

      expect(last_response).to be_redirect
    end
  end

  context "GET /gems/:id" do
    it "redirects" do
      get "/gems/rack"

      expect(last_response).to be_redirect
    end
  end

  context "/latest_specs.4.8.gz" do
    it "redirects" do
      get "/latest_specs.4.8.gz"

      expect(last_response).to be_redirect
    end
  end

  context "/specs.4.8.gz" do
    it "redirects" do
      get "/specs.4.8.gz"

      expect(last_response).to be_redirect
    end
  end

  context "/prerelease_specs.4.8.gz" do
    it "redirects" do
      get "/prerelease_specs.4.8.gz"

      expect(last_response).to be_redirect
    end
  end

  context "/names" do
    it_behaves_like "return 304 on second hit" do
      let(:url) { "/names" }
    end

    before do
      %w(a b c d).each {|gem_name| builder.create_rubygem(gem_name) }
    end

    it "returns an array" do
      get "/names"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(<<-NAMES.chomp.gsub(/^        /, ''))
        ---
        a
        b
        c
        d
        rack

      NAMES
    end
  end

  context "/versions" do
    it_behaves_like "return 304 on second hit" do
      let(:url) { "/versions" }
    end

    let(:data) { "a 1.0.0,1.0.1\nb 1.0.0\nc 1.0.0-java\na 2.0.0\na 2.0.1" }
    before do
      CompactIndex.stub('versions').and_return(data)
    end
    let(:expected_etag) { Digest::MD5.hexdigest(data) }

    it "returns versions.list" do
      get "/versions"

      expect(last_response).to be_ok
      expect(last_response.header["ETag"]).to eq(expected_etag)
      expect(last_response.body).to eq(data)
    end
  end

  context "/info/:gem" do
    it_behaves_like "return 304 on second hit" do
      let(:url) { "/info/rack" }
    end

    context "when has no required ruby version" do
      before do
        info_test = builder.create_rubygem('info_test')
        builder.create_version(info_test, 'info_test', '1.0.0', 'ruby', checksum: 'abc123')

        info_test101= builder.create_version(info_test, 'info_test', '1.0.1', 'ruby', checksum: 'qwerty')
        [['foo', '= 1.0.0'], ['bar', '>= 2.1, < 3.0']].each do |dep, requirements|
          dep_id = builder.create_rubygem(dep)
          builder.create_dependency(dep_id, info_test101, requirements)
        end
      end

      let(:expected_deps) do
        <<-DEPS.gsub(/^          /, '')
          ---
          1.0.0 |checksum:abc123
          1.0.1 bar:>= 2.1&< 3.0,foo:= 1.0.0|checksum:qwerty
        DEPS
      end
      let(:expected_etag) { Digest::MD5.hexdigest(expected_deps) }

      it "should return the gem list" do
        get "/info/info_test"

        expect(last_response).to be_ok
        expect(last_response.body).to eq(expected_deps)
        expect(last_response.header["ETag"]).to eq(expected_etag)
      end
    end

    context "when has a required ruby version" do
      before do
        a = builder.create_rubygem("a")
        builder_args = { checksum: "abc123", required_ruby: ">1.9", rubygems_version: ">2.0" }
        a_version = builder.create_version(a, 'a', '1.0.1', 'ruby', builder_args )
        [['a_foo', '= 1.0.0'], ['a_bar', '>= 2.1, < 3.0']].each do |dep, requirements|
          dep_id = builder.create_rubygem(dep)
          builder.create_dependency(dep_id, a_version, requirements)
        end
      end

      let(:expected_deps) do
        <<-DEPS.gsub(/^          /, '')
          ---
          1.0.1 a_bar:>= 2.1&< 3.0,a_foo:= 1.0.0|checksum:abc123,ruby:>1.9,rubygems:>2.0
        DEPS
      end

      it "should return the gem list with the required ruby version" do
        get "/info/a"
        expect(last_response).to be_ok
        expect(last_response.body).to eq(expected_deps)
      end
    end
  end
end
