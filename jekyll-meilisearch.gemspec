# frozen_string_literal: true

require_relative "lib/jekyll-meilisearch/version"

Gem::Specification.new do |spec|
  spec.name = "jekyll-meilisearch"
  spec.version = Jekyll::Meilisearch::VERSION
  spec.licenses = ["MIT"]
  spec.summary = "A Jekyll plugin to index site content in Meilisearch."
  spec.description = "This plugin incrementally indexes Jekyll collections into Meilisearch for fast search capabilities."
  spec.authors = ["unicolored"]
  spec.email = "hello@gilles.dev"
  spec.homepage = "https://github.com/unicolored/jekyll-meilisearch"
  spec.metadata = { "source_code_uri" => "https://github.com/unicolored/jekyll-meilisearch" }

  spec.files = Dir["lib/**/*"]
  spec.extra_rdoc_files = Dir["README.md"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7"

  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "jekyll", ">= 3.7", "< 5.0"
  spec.add_dependency "json", "~> 2.10", ">= 2.10.2"
  spec.add_dependency "logger", "~> 1.6", ">= 1.6.6"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "nokogiri", "~> 1.6"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop-jekyll", "~> 0.14.0"
  spec.add_development_dependency "typhoeus", ">= 0.7", "< 2.0"
end
