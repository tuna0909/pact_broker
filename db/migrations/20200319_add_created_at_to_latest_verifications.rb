Sequel.migration do
  change do
    add_column(:latest_verification_id_for_pact_version_and_provider_version, :created_at, DateTime)
  end
end
