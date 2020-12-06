require 'pact_broker/domain/tag'

module PactBroker
  module Domain
    describe Tag do
      before do
        td.create_consumer("foo")
          .create_consumer_version("1")
          .create_consumer_version_tag("dev")
          .create_consumer_version_tag("prod")
          .create_consumer_version("2")
          .create_consumer_version_tag("dev")
          .create_consumer_version_tag("bloop")
          .create_consumer_version("3")
          .create_consumer_version_tag("dev")
          .create_consumer("bar")
          .create_consumer_version("1")
          .create_consumer_version_tag("test")
      end

      describe "#latest_tags_for_pacticipant_ids" do
        it "returns the latest tags for the given pacticipant ids" do
          pacticipant = PactBroker::Domain::Pacticipant.order(:id).first
          tags = Tag.latest_tags_for_pacticipant_ids([pacticipant.id]).all
          expect(tags.collect(&:name).sort).to eq %w{bloop dev prod}
          expect(tags.find{ |t| t.name == "dev" }.version.number).to eq "3"
          expect(tags.find{ |t| t.name == "prod" }.version.number).to eq "1"
          expect(tags.find{ |t| t.name == "bloop" }.version.number).to eq "2"
          expect(tags.collect(&:version_id).compact.size).to eq 3
          expect(tags.collect(&:created_at).compact.size).to eq 3
        end
      end

      describe "latest_tags" do
        it "returns the tags that belong to the most recent version with that tag/pacticipant" do
          tags = Tag.latest_tags.all
          expect(tags.collect(&:name).sort).to eq %w{bloop dev prod test}
          expect(tags.find{ |t| t.name == "dev" }.version.number).to eq "3"
          expect(tags.find{ |t| t.name == "prod" }.version.number).to eq "1"
          expect(tags.find{ |t| t.name == "bloop" }.version.number).to eq "2"
          expect(tags.collect(&:version_id).compact.size).to eq 4
          expect(tags.collect(&:created_at).compact.size).to eq 4
        end
      end

      describe "latest_for_pacticipant?" do
        before do
          # Foo v1 Bar1
          # Foo v1 Bar2
          # Foo v2 Bar1
          td.create_pact_with_verification_and_tags("Foo", "1", ["dev", "prod"], "Bar1")
            .create_provider("Bar2")
            .create_pact
            .create_pact_with_verification_and_tags("Foo", "2", ["dev"], "Bar1")
            .create_consumer_version("3")
            .create_consumer_version_tag("dev")
        end

        it "returns true if there are no other tags with that name for that pacticipant for a later version" do
          version_1 = PactBroker::Versions::Repository.new.find_by_pacticipant_name_and_number("Foo", "1")
          expect(version_1.tags.find { |t| t.name == "prod" }.latest_for_pacticipant?).to be true
          expect(version_1.tags.find { |t| t.name == "dev" }.latest_for_pacticipant?).to be false
        end
      end

      describe "head_tags_for_pact_publication" do
        before do
          # Foo v1 Bar1
          # Foo v1 Bar2
          # Foo v2 Bar1
          td.create_pact_with_verification_and_tags("Foo", "1", ["dev", "prod"], "Bar1")
            .create_provider("Bar2")
            .create_pact
            .create_pact_with_verification_and_tags("Foo", "2", ["dev"], "Bar1")
            .create_consumer_version("3")
            .create_consumer_version_tag("dev")
        end

        it "returns the names of the tags for which this pact publication is the latest" do
          pact_0 = PactBroker::Pacts::PactPublication.find(id: PactBroker::Pacts::Repository.new.find_pact("Foo", "1", "Bar1").id)
          expect(pact_0.consumer_version.tags.collect(&:name).sort).to eq ["dev", "prod"]
          expect(Tag.head_tags_for_pact_publication(pact_0).collect(&:name).sort).to eq ["prod"]

          pact_1 = PactBroker::Pacts::PactPublication.find(id: PactBroker::Pacts::Repository.new.find_pact("Foo", "2", "Bar1").id)
          expect(Tag.head_tags_for_pact_publication(pact_1).collect(&:name).sort).to eq ["dev"]

          pact_2 = PactBroker::Pacts::PactPublication.find(id: PactBroker::Pacts::Repository.new.find_pact("Foo", "1", "Bar2").id)
          expect(Tag.head_tags_for_pact_publication(pact_2).collect(&:name).sort).to eq ["dev", "prod"]
        end
      end
    end
  end
end

# Table: tags
# Primary Key: (name, version_id)
# Columns:
#  name       | text                        |
#  version_id | integer                     |
#  created_at | timestamp without time zone | NOT NULL
#  updated_at | timestamp without time zone | NOT NULL
# Indexes:
#  tags_pk      | PRIMARY KEY btree (version_id, name)
#  ndx_tag_name | btree (name)
# Foreign key constraints:
#  tags_version_id_fkey | (version_id) REFERENCES versions(id)
