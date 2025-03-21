Gem::Specification.new do |s|
  s.name        = 'jekyll-meilisearch'
  s.version     = '0.2.0'
  s.summary     = 'A Jekyll plugin to index site content in Meilisearch.'
  s.description = 'This plugin incrementally indexes Jekyll collections into Meilisearch for fast search capabilities.'
  s.authors     = ['unicolored']
  s.email       = 'hello@gilles.dev'
  s.files       = %w[lib/jekyll-meilisearch.rb lib/jekyll/meilisearch_indexer.rb]
  s.homepage    = 'https://github.com/unicolored/jekyll-meilisearch'
  s.license     = 'MIT'

  s.required_ruby_version = '>= 2.7'

  s.add_dependency 'httparty', '~> 0.21'
  s.add_dependency 'jekyll', '>= 3.0', '< 5.0'
  s.add_development_dependency 'bundler', '~> 2.0'
  s.add_development_dependency 'rake', '~> 13.0'
end
