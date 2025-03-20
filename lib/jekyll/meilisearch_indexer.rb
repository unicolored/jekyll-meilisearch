require 'httparty'
require 'json'
require 'logger'

module Jekyll
  class MeilisearchIndexer < Generator
    def generate(site)
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO

      log_info("Starting Meilisearch incremental indexing...")
      config = load_config(site)
      return unless validate_config(config)

      documents = build_documents(site, config)
      sync_with_meilisearch(config, documents)
    end

    private

    def log_info(message)
      @logger.info(message)
    end

    def load_config(site)
      site.config['meilisearch'] || {}
    end

    def validate_config(config)
      unless config['url']
        log_info("Error: Meilisearch URL not set in config. Skipping indexing.")
        return false
      end
      unless config['api_key']
        log_info("Error: Meilisearch API key not set in config. Skipping indexing.")
        return false
      end
      true
    end

    def build_headers(api_key)
      {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{api_key}"
      }
    end

    def build_documents(site, config)
      documents = []
      collections_config = config['collections'] || { 'posts' => { 'fields' => ['title', 'content', 'url', 'date'] } }

      collections_config.each do |collection_name, collection_settings|
        collection = site.collections[collection_name]
        if collection
          log_info("Processing collection: '#{collection_name}'...")
          fields_to_index = collection_settings['fields'] || ['title', 'content', 'url', 'date']
          id_format = collection_settings['id_format'] || :default

          collection_docs = collection.docs.map do |doc|
            sanitized_id = generate_id(doc, collection_name, id_format)
            doc_data = {
              'id' => sanitized_id,
              'content' => doc.content.strip,
              'url' => doc.url
            }
            fields_to_index.each do |field|
              next if ['id', 'content', 'url'].include?(field)
              value = doc.data[field]
              doc_data[field] = field == 'date' && value ? value.strftime('%Y-%m-%d') : value
            end
            doc_data
          end
          documents.concat(collection_docs)
        else
          log_info("Warning: Collection '#{collection_name}' not found. Skipping.")
        end
      end

      if documents.empty?
        log_info("No documents found across configured collections: #{collections_config.keys.join(', ')}. Cleaning up index...")
      end
      documents
    end

    def generate_id(doc, collection_name, id_format)
      case id_format
      when :default
        doc.data['number'] ? "#{collection_name}-#{doc.data['number']}" : doc.id.gsub('/', '-')
                                                                             .gsub(/[^a-zA-Z0-9_-]/, '-').gsub(/-+/, '-').downcase.slice(0, 100)
      when :path
        doc.url.gsub('/', '-').downcase.slice(0, 100)
      else
        doc.id.gsub('/', '-').downcase.slice(0, 100)
      end
    end

    def sync_with_meilisearch(config, documents)
      headers = build_headers(config['api_key'])
      index_name = config['index_name'] || 'jekyll_documents'
      create_index_if_missing(config['url'], index_name, headers)

      meili_docs = fetch_all_documents(config['url'], index_name, headers)
      if meili_docs.nil?
        log_info("Failed to fetch existing documents. Falling back to full indexing.")
        return full_index(config['url'], index_name, documents, headers)
      end

      meili_ids = meili_docs.map { |doc| doc['id'] }
      jekyll_ids = documents.map { |doc| doc['id'] }

      delete_obsolete_documents(config['url'], index_name, meili_ids - jekyll_ids, headers)
      index_new_documents(config['url'], index_name, documents, headers) if documents.any?
    end

    def fetch_all_documents(url, index_name, headers)
      documents = []
      offset = 0
      limit = 1000
      loop do
        response = attempt_request(
          -> { HTTParty.get("#{url}/indexes/#{index_name}/documents?limit=#{limit}&offset=#{offset}", headers: headers, timeout: 30) },
          "fetching documents"
        )
        return nil unless response&.success?
        results = JSON.parse(response.body)['results']
        documents.concat(results)
        break if results.size < limit
        offset += limit
      end
      documents
    end

    def delete_obsolete_documents(url, index_name, ids_to_delete, headers)
      return log_info("No documents to delete from Meilisearch.") if ids_to_delete.empty?

      log_info("Deleting #{ids_to_delete.size} obsolete documents from Meilisearch...")
      response = attempt_request(
        -> { HTTParty.post("#{url}/indexes/#{index_name}/documents/delete-batch", body: ids_to_delete.to_json, headers: headers, timeout: 30) },
        "deleting documents"
      )
      if response&.success?
        log_info("Delete task queued successfully.")
      elsif response
        log_info("Failed to delete obsolete documents: #{response.code} - #{response.body}")
      end
    end

    def index_new_documents(url, index_name, documents, headers)
      log_info("Indexing #{documents.size} documents to Meilisearch...")
      batch_size = 1000
      documents.each_slice(batch_size) do |batch|
        response = attempt_request(
          -> { HTTParty.post("#{url}/indexes/#{index_name}/documents", body: batch.to_json, headers: headers, timeout: 30) },
          "indexing documents"
        )
        if response&.code == 202
          if response.body
            task = JSON.parse(response.body)
            log_info("Task queued: UID #{task['taskUid']}. Check status at #{url}/tasks/#{task['taskUid']}")
          else
            log_info("Task queued (202), but no response body received.")
          end
        elsif response.nil?
          log_info("Failed to queue indexing task: No response received from Meilisearch.")
        else
          log_info("Failed to queue indexing task: #{response.code} - #{response.body}")
        end
      end
    end

    def create_index_if_missing(url, index_name, headers)
      log_info("Checking if index '#{index_name}' exists...")
      response = HTTParty.get("#{url}/indexes/#{index_name}", headers: headers, timeout: 30)
      return if response.success?

      if response.code == 404
        log_info("Index '#{index_name}' not found. Creating it...")
        response = attempt_request(
          -> { HTTParty.post("#{url}/indexes", body: { "uid" => index_name }.to_json, headers: headers, timeout: 30) },
          "creating index"
        )
        if response&.success? || response&.code == 202
          log_info("Index '#{index_name}' created successfully.")
        elsif response
          log_info("Failed to create index: #{response.code} - #{response.body}")
        end
      else
        log_info("Error checking index: #{response.code} - #{response.body}")
      end
    end

    def full_index(url, index_name, documents, headers)
      log_info("Performing full index reset as fallback...")
      response = attempt_request(
        -> { HTTParty.delete("#{url}/indexes/#{index_name}/documents", headers: headers, timeout: 30) },
        "resetting index"
      )
      unless response&.success? || response&.code == 404
        if response.nil?
          log_info("Failed to reset index: No response received from Meilisearch.")
        else
          log_info("Failed to reset index: #{response.code} - #{response.body}")
        end
        return
      end

      index_new_documents(url, index_name, documents, headers) if documents.any?
    end

    def attempt_request(request, action, retries: 3)
      retries.times do |i|
        begin
          response = request.call
          return response if response.success? || [202, 404].include?(response.code)
        rescue HTTParty::Error => e
          log_info("Attempt #{i + 1} failed while #{action}: #{e.message}")
          sleep(2 ** i) # Exponential backoff
        end
      end
      log_info("All retries failed for #{action}.")
      nil
    end
  end
end