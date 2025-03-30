# frozen_string_literal: true

module JekyllMeilisearch
  class MeilisearchIndexer < Jekyll::Generator
    safe true
    priority :lowest

    # Main plugin action, called by Jekyll-core
    def generate(site)
      @site = site
      if disabled_in_development?
        Jekyll.logger.info "Jekyll Meilisearch:", "Skipping meilisearch indexation in development"
        return
      end
      Jekyll.logger.info "Starting Meilisearch incremental indexing..."
      return unless validate_config

      @documents = build_documents
      sync_with_meilisearch
    end

    private

    # Returns the plugin's config or an empty hash if not set
    def config
      @config ||= begin
        meilisearch_config = @site.config["meilisearch"] || {}
        meilisearch_config["url"] = meilisearch_config["url"].chomp("/") if meilisearch_config["url"]
        meilisearch_config
      end
    end

    def validate_config
      unless config["url"]
        Jekyll.logger.info "Error: Meilisearch URL not set in config. Skipping indexing."
        return false
      end
      unless config["api_key"]
        Jekyll.logger.info "Error: Meilisearch API key not set in config. Skipping indexing."
        return false
      end
      true
    end

    def build_headers(api_key)
      {
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer #{api_key}",
      }
    end

    def build_documents
      documents = []
      collections_config = config["collections"] || { "posts" => { "fields" => %w(title content url date) } }

      collections_config.each do |collection_name, collection_settings|
        collection = @site.collections[collection_name]
        if collection
          Jekyll.logger.info "Processing collection: '#{collection_name}'..."
          fields_to_index = collection_settings["fields"] || %w(title content url date)
          id_format = collection_settings["id_format"] || :default

          collection_docs = collection.docs.map do |doc|
            # Skip if no front matter
            next unless doc.data.any?

            sanitized_id = generate_id(doc, collection_name, id_format)
            doc_data = {
              "id"      => sanitized_id,
              "content" => doc.content&.strip,
              "url"     => doc.url,
            }
            fields_to_index.each do |field|
              next if %w(id content url).include?(field)

              value = doc.data[field]
              doc_data[field] = field == "date" && value ? value.strftime("%Y-%m-%d") : value
            end
            doc_data
          end
          documents.concat(collection_docs)
        else
          Jekyll.logger.info "Warning: Collection '#{collection_name}' not found. Skipping."
        end
      end

      if documents.empty?
        Jekyll.logger.info "No documents found across configured collections: #{collections_config.keys.join(", ")}. Cleaning up index..."
      end
      documents
    end

    def generate_id(doc, collection_name, id_format)
      # Helper method to normalize strings
      normalize = lambda do |str|
        str.tr("/", "-")
          .gsub(%r![^a-zA-Z0-9_-]!, "-").squeeze("-")
          .downcase
          .slice(0, 100)
      end

      case id_format
      when :default, :id
        normalize.call(doc.id)
      when :url
        normalize.call(doc.url)
      else
        doc.data["number"] ? "#{collection_name}-#{doc.data["number"]}" : normalize.call(doc.id)
      end
    end

    def sync_with_meilisearch
      headers = build_headers(config["api_key"])
      index_name = config["index_name"] || "jekyll_documents"
      create_index_if_missing(config["url"], index_name, headers)

      meili_docs = fetch_all_documents(config["url"], index_name, headers)
      if meili_docs.nil?
        Jekyll.logger.info "Failed to fetch existing documents. Falling back to full indexing."
        return full_index(config["url"], index_name, @documents, headers)
      end

      meili_ids = meili_docs.map { |doc| doc["id"] }
      jekyll_ids = @documents.map { |doc| doc["id"] }

      delete_obsolete_documents(config["url"], index_name, meili_ids - jekyll_ids, headers)
      index_new_documents(config["url"], index_name, @documents, headers) if @documents.any?
    end

    def fetch_all_documents(url, index_name, headers)
      documents = []
      offset = 0
      limit = 1000
      loop do
        response = attempt_request(
          lambda {
            HTTParty.get("#{url}/indexes/#{index_name}/documents?limit=#{limit}&offset=#{offset}", :headers => headers,
                                                                                                   :timeout => 30)
          },
          "fetching documents"
        )
        return nil unless response&.success?

        results = JSON.parse(response.body)["results"]
        documents.concat(results)
        break if results.size < limit

        offset += limit
      end
      documents
    end

    def delete_obsolete_documents(url, index_name, ids_to_delete, headers)
      return Jekyll.logger.info "No documents to delete from Meilisearch." if ids_to_delete.empty?

      Jekyll.logger.info "Deleting #{ids_to_delete.size} obsolete documents from Meilisearch..."
      response = attempt_request(
        lambda {
          HTTParty.post("#{url}/indexes/#{index_name}/documents/delete-batch", :body => ids_to_delete.to_json, :headers => headers,
                        :timeout => 30)
        },
        "deleting documents"
      )
      if response&.success?
        Jekyll.logger.info "Delete task queued successfully."
      elsif response
        Jekyll.logger.info "Failed to delete obsolete documents: #{response.code}"
      end
    end

    def index_new_documents(url, index_name, documents, headers)
      Jekyll.logger.info "Indexing #{documents.size} documents to Meilisearch..."
      batch_size = 1000
      documents.each_slice(batch_size) do |batch|
        response = attempt_request(
          lambda {
            HTTParty.post("#{url}/indexes/#{index_name}/documents", :body => batch.to_json, :headers => headers, :timeout => 30)
          },
          "indexing documents"
        )
        if response&.code == 202
          if response.body
            task = JSON.parse(response.body)
            Jekyll.logger.info "Task queued: UID #{task["taskUid"]}. Check status at #{url}/tasks/#{task["taskUid"]}"
          else
            Jekyll.logger.info "Task queued (202), but no response body received."
          end
        elsif response.nil?
          Jekyll.logger.info "Failed to queue indexing task: No response received from Meilisearch."
        else
          Jekyll.logger.info "Failed to queue indexing task: #{response.code}"
        end
      end
    end

    def create_index_if_missing(url, index_name, headers)
      Jekyll.logger.info "Checking if index '#{index_name}' exists..."
      response = HTTParty.get("#{url}/indexes/#{index_name}", :headers => headers, :timeout => 30)
      return if response.success?

      if response.code == 404
        Jekyll.logger.info "Index '#{index_name}' not found. Creating it..."
        response = attempt_request(
          -> { HTTParty.post("#{url}/indexes", :body => { "uid" => index_name }.to_json, :headers => headers, :timeout => 30) },
          "creating index"
        )
        if response&.success? || response&.code == 202
          Jekyll.logger.info "Index '#{index_name}' created successfully."
        elsif response
          Jekyll.logger.info "Failed to create index: #{response.code}"
        end
      else
        Jekyll.logger.info "Error checking index: #{response.code} - #{response.response}"
      end
    end

    def full_index(url, index_name, documents, headers)
      Jekyll.logger.info "Performing full index reset as fallback..."
      response = attempt_request(
        -> { HTTParty.delete("#{url}/indexes/#{index_name}/documents", :headers => headers, :timeout => 30) },
        "resetting index"
      )
      unless response&.success? || response&.code == 404
        if response.nil?
          Jekyll.logger.info "Failed to reset index: No response received from Meilisearch."
        else
          Jekyll.logger.info "Failed to reset index: #{response.code}"
        end
        return
      end

      index_new_documents(url, index_name, documents, headers) if documents.any?
    end

    def attempt_request(request, action, retries: 3)
      retries.times do |i|
        response = request.call
        return response if response.success? || [202, 404].include?(response.code)
      rescue HTTParty::Error => e
        Jekyll.logger.info "Attempt #{i + 1} failed while #{action}: #{e.message}"
        sleep(2**i) # Exponential backoff
      end
      Jekyll.logger.info "All retries failed for #{action}."
      nil
    end

    def disabled_in_development?
      config && config["disable_in_development"] && Jekyll.env == "development"
    end
  end
end
