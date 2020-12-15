require 'pact_broker/db'
require 'pact_broker/repositories/helpers'

module PactBroker
  module Domain
    class Tag < Sequel::Model
      plugin :timestamps, update_on_create: true
      plugin :insert_ignore, identifying_columns: [:name, :version_id]

      unrestrict_primary_key
      associate(:many_to_one, :version, :class => "PactBroker::Domain::Version", :key => :version_id, :primary_key => :id)

      dataset_module do
        include PactBroker::Repositories::Helpers

        def latest_tags
          self_join = {
            Sequel[:tags][:pacticipant_id] => Sequel[:tags_2][:pacticipant_id],
            Sequel[:tags][:name] => Sequel[:tags_2][:name]
          }

          PactBroker::Domain::Tag
            .select_all_qualified
            .left_join(:tags, self_join, { table_alias: :tags_2 }) do | t, jt, js |
              Sequel[:tags_2][:version_order] > Sequel[:tags][:version_order]
            end
            .where(Sequel[:tags_2][:name] => nil)
        end

        # Does NOT care about whether or not there is a pact publication
        # for the version
        def latest_tags_for_pacticipant_ids(pacticipant_ids)
          self_join = {
            Sequel[:tags][:pacticipant_id] => Sequel[:tags_2][:pacticipant_id],
            Sequel[:tags][:name] => Sequel[:tags_2][:name],
            Sequel[:tags_2][:pacticipant_id] => pacticipant_ids,
          }

          Tag
            .select_all_qualified
            .left_join(:tags, self_join, { table_alias: :tags_2 }) do | t, jt, js |
              Sequel[:tags_2][:version_order] > Sequel[:tags][:version_order]
            end
            .where(Sequel[:tags_2][:name] => nil)
            .where(Sequel[:tags][:pacticipant_id] => pacticipant_ids)
        end

        # ignores tags that don't have a pact publication
        def head_tags_for_consumer_id(consumer_id)
          lp = :latest_pact_publication_ids_for_consumer_versions
          tags_versions_join = {
            Sequel[:tags][:version_id] => Sequel[:versions][:id],
            Sequel[:versions][:pacticipant_id] => consumer_id
          }

          versions_pact_publications_join = {
            Sequel[:versions][:id] => Sequel[lp][:consumer_version_id],
            Sequel[lp][:consumer_id] => consumer_id
          }
          # head tags for this consumer
          # the latest tag, pacticipant_id, version order
          # for versions that have a pact publication
          Tag
            .select_group(Sequel[:tags][:name], Sequel[:versions][:pacticipant_id])
            .select_append{ max(order).as(latest_consumer_version_order) }
            .join(:versions, tags_versions_join)
            .join(lp, versions_pact_publications_join)
        end

        def head_tags_for_pact_publication(pact_publication)
          # self_join = {
          #   Sequel[:tags][:pacticipant_id] => Sequel[:tags_2][:pacticipant_id],
          #   Sequel[:tags][:name] => Sequel[:tags_2][:name],
          #   Sequel[:tags_2][:pacticipant_id] => pact_publication.consumer_id,
          # }

          # select_all_qualified
          # .join(:pact_publications)

          # Tag
          #   .select_all_qualified
          #   .left_join(:tags, self_join, { table_alias: :tags_2 }) do | t, jt, js |
          #     Sequel[:tags_2][:version_order] > Sequel[:tags][:version_order]
          #   end
          #   .where(Sequel[:tags_2][:name] => nil)
          #   .where(Sequel[:tags][:pacticipant_id] => pacticipant_ids)


          # Tag.select_all_qualified
          #   .select_append(Sequel[:p][:id])



          # head_tags_versions_join = {
          #   Sequel[:head_tags][:latest_consumer_version_order] => Sequel[:versions][:order],
          #   Sequel[:head_tags][:pacticipant_id] => Sequel[:versions][:pacticipant_id],
          #   Sequel[:versions][:pacticipant_id] => pact_publication.consumer_id
          # }

          # # Find the head tags that belong to this pact publication
          # # Note: The tag model has the name and version_id,
          # # but does not have the created_at value set - but don't need it for now
          # head_tags_for_consumer_id(pact_publication.consumer_id).from_self(alias: :head_tags)
          #   .select(Sequel[:head_tags][:name], Sequel[:versions][:id].as(:version_id))
          #   .join(:versions, head_tags_versions_join)
          #   .where(Sequel[:versions][:id] => pact_publication.consumer_version_id)


          Tag.where(version_id: pact_publication.consumer_version_id).all.select do | tag |
            tag_pp_join = {
              Sequel[:pact_publications][:consumer_version_id] => Sequel[:tags][:version_id],
              Sequel[:pact_publications][:consumer_id] => pact_publication.consumer_id,
              Sequel[:pact_publications][:provider_id] => pact_publication.provider_id,
              Sequel[:tags][:name] => tag.name
            }
            Tag.join(:pact_publications, tag_pp_join) do
              Sequel[:tags][:version_order] > tag.version_order
            end
            .where(pacticipant_id: pact_publication.consumer_id)
            .limit(1)
            .empty?
          end
        end
      end

      def before_save
        if version
          if version.order && self.version_order.nil?
            self.version_order = version.order
          end

          if self.pacticipant_id.nil?
            if version.pacticipant_id
              self.pacticipant_id = version.pacticipant_id
            elsif version&.pacticipant&.id
              self.pacticipant_id = version.pacticipant.id
            end
          end
        end

        if version_order.nil? || pacticipant_id.nil?
          raise PactBroker::Error.new("Need to set version_order and pacticipant_id for tags now")
        else
          super
        end
      end

      def latest_for_pacticipant?
        if defined?(@is_latest_for_pacticipant)
          @is_latest_for_pacticipant
        else
          own_version_order = self.version_order
          @is_latest_for_pacticipant = Tag.where(pacticipant_id: pacticipant_id, name: name)
            .where{ version_order > own_version_order }
            .limit(1)
            .empty?
        end
      end

      def latest_for_pact_publication?(pact_publication)
        tag_pp_join = {
          Sequel[:pact_publications][:consumer_version_id] => Sequel[:tags][:version_id],
          Sequel[:pact_publications][:consumer_id] => pact_publication.consumer_id,
          Sequel[:pact_publications][:provider_id] => pact_publication.provider_id,
          Sequel[:tags][:name] => name
        }
        own_version_order = self.version_order
        Tag.join(:pact_publications, tag_pp_join) do
          Sequel[:tags][:version_order] > own_version_order
        end
        .where(pacticipant_id: pact_publication.consumer_id)
        .limit(1)
        .empty?
      end

      def <=> other
        name <=> other.name
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
