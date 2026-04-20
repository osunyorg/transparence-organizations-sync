#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'

Bundler.require(:default)

Dotenv.load
OsunyApi.configure do |config|
  config.api_key['X-Osuny-Token'] = ENV["OSUNY_API_KEY"]
  config.base_path = '/api/osuny/v1'
end

# Load organizations from API

api_instance = OsunyApi::UniversityOrganizationApi.new
result = api_instance.university_organizations_get

organizations = result.map { |orga|
  {
    id: orga.id,
    migration_identifier: orga.migration_identifier,
    localizations: {
      fr: {
        migration_identifier: orga.localizations[:fr][:migration_identifier],
        name: orga.localizations[:fr][:name]
      }
    },
    category_ids: orga.category_ids
  }
}

# Load contributions from transparence.osuny.org

transparence_json_url = "https://transparence.osuny.org/?format=json"
transparence_json = URI.parse(transparence_json_url).open do |io|
  JSON.load(io)
end

universities = transparence_json['contributions']['list']
data = []

# For each university:
# - Compute the migration identifier for the API (org-from-university-<id>)
# - Find a matching organization in the API with the same migration identifier
# - Set the data accordingly and add the missing categories
universities.each do |university|
  migration_identifier = "org-from-university-#{university['id']}"
  existing_organization = organizations.find { |orga|
    orga[:migration_identifier] == migration_identifier
  }

  name = existing_organization  ? existing_organization[:localizations][:fr][:name]
                                : university['name']
  category_ids = existing_organization ? existing_organization[:category_ids] : []
  category_ids << ENV["CONTRIBUTION_CATEGORY_ID"] unless category_ids.include?(ENV["CONTRIBUTION_CATEGORY_ID"])

  data << {
    migration_identifier: migration_identifier,
    localizations: {
      fr: {
        migration_identifier: "#{migration_identifier}-fr",
        name: name
      }
    },
    category_ids: category_ids
  }
end

# Call the upsert organizations API endpoint with batches of 100 organizations.

data.each_slice(100) do |batch|
  response = api_instance.university_organizations_upsert_post_with_http_info({
    body: { organizations: batch }
  })
  puts "Batch of #{batch.size} organizations upserted"
end
