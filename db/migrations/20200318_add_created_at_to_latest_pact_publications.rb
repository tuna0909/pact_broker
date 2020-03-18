Sequel.migration do
  change do
    add_column(:latest_pact_publication_ids_for_consumer_versions, :created_at, DateTime)
  end
end
