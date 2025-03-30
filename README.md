# Jekyll Meilisearch Plugin

A Jekyll plugin that indexes your site’s content into Meilisearch, a fast and lightweight search engine. This plugin supports incremental indexing, ensuring efficient updates by only syncing changes between your Jekyll site and Meilisearch.

[![Gem Version](https://badge.fury.io/rb/jekyll-meilisearch.svg)](https://badge.fury.io/rb/jekyll-meilisearch)

## Features
- Indexes Jekyll collections (e.g., posts, pages) into Meilisearch.
- Incremental updates: adds new documents, deletes obsolete ones, and skips unchanged content.
- Configurable via _config.yml: customize fields, collections, and ID formats.
- Robust error handling with retries and fallback to full indexing if needed.
- Pagination support for large sites.

## Installation

Add the gem to your Jekyll site’s Gemfile:

```ruby
gem "jekyll-meilisearch"
```

And then add this line to your site's `_config.yml`:

```yml
plugins:
  - jekyll-meilisearch
```

## Configuration
Add the following to your Jekyll _config.yml (or a separate config file like _config.prod.yml):

```yaml
meilisearch:
    url: "http://localhost:7700"  # Your Meilisearch instance URL
    api_key: "your-api-key"       # Meilisearch API key
    index_name: "my_site"         # Optional: defaults to "jekyll_documents"
    collections:
        posts:
          fields: ["title", "content", "url", "date"]  # Fields to index
          id_format: "default"                         # Optional: "default" or "path"
        pages:
          fields: ["title", "content", "url"]
```

## Configuration Options
* `url`: The Meilisearch server URL (required).
* `api_key`: The Meilisearch API key (required). Recommended: use a dedicated api key for your index, not the admin one.
* `index_name`: The name of the Meilisearch index (optional, defaults to jekyll_documents).
* `collections`: A hash of Jekyll collections to index.
  * `fields`: Array of fields to extract from each document (e.g., title, content, url, date).
  * `id_format`: How to generate document IDs:
    * "default" | "id": Uses collection-name-number if a number field exists, otherwise sanitizes the document ID.
    * "url": Uses the document’s URL, sanitized.
    * fallback: if "number" exists, uses "collection_name" + "number"

Run your Jekyll build:

```shell
bundle exec jekyll build
```

Or with multiple config files:

```shell
bundle exec jekyll build --config _config.yml,_config.prod.yml
```

## Usage
Ensure Meilisearch is running and accessible at the configured url.
Configure your _config.yml with the necessary meilisearch settings.
Build your site. The plugin will:
- Create the Meilisearch index if it doesn’t exist.
- Fetch existing documents from Meilisearch.
- Delete obsolete documents.
- Index new or updated documents.
- Logs will output to STDOUT with details about the indexing process.

Include the following for adding search to your front :
```html

<!-- Search Input -->
<div class="border m-6 mb-6 p-4">
  <input type="text" id="search" class="border p-2 w-full" placeholder="Rechercher...">
  <div id="results" class="mt-2 border p-4">Results will appear here.</div>
</div>

<!-- Meilisearch JS SDK -->
<script src="https://cdn.jsdelivr.net/npm/meilisearch@0.40.0/dist/bundles/meilisearch.umd.js"></script>
<script>
  const meilisearchConfig = {
    host: "{{ site.meilisearch.url | default: 'http://localhost:7700' }}",
    apiKey: "{{ site.meilisearch.search_api_key}}"
  };
  const client = new MeiliSearch(meilisearchConfig);
  const index = client.index('{{site.meilisearch.index_name}}');

  document.getElementById('search').addEventListener('input', async (e) => {
    const query = e.target.value;
    if (query.length < 2) {
      document.getElementById('results').innerHTML = '';
      return;
    }
    try {
      const results = await index.search(query);
      document.getElementById('results').innerHTML = results.hits
        .map(hit => `<p><a href="${hit.url}" class="text-blue-500 hover:underline">${hit.title}</a></p>`)
        .join('');
    } catch (error) {
      console.error('Search error:', error);
      document.getElementById('results').innerHTML = '<p class="text-red-500">Search failed. Please try again.</p>';
    }
  });
</script>

```

## Skip development

Use `disable_in_development: true` if you want to turn off meilisearch indexation when `jekyll.environment == "development"`,
but don't want to remove the plugin (so you don't accidentally commit the removal). Default value is `false`.

```yml
meilisearch:
  disable_in_development: true
```

## Contributing

1. Fork it (https://github.com/unicolored/jekyll-meilisearch/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
