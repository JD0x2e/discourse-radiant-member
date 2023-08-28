# frozen_string_literal: true

# name: discourse-radiant-member
# about: Add/remove Radiant members from a group
# version: 0.0.1
# authors: pfaffman
# url: https://github.com/literatecomputing/discourse-radiant-member
# required_version: 2.7.0

enabled_site_setting :radiant_member_enabled
module ::RadiantMemberModule
  PLUGIN_NAME = "discourse-radiant-member"
end

require_relative "lib/radiant_member_module/engine"
load File.expand_path("lib/radiant/balance.rb", __dir__)

after_initialize do
  # Code which should run after Rails has finished booting
  # register_user_custom_field_type("radiant_dollars", :float)

  add_to_class(User, "radiant_dollars") { return Radiant.get_rdnt_amount(self) }
  
  add_to_class(User, "siweAddress") { return Radiant.get_siwe_address_by_user(self) }

  add_to_serializer(:current_user, :radiant_dollars) { Radiant.get_rdnt_amount(object) }
  add_to_serializer(:current_user, :siweAddress) {  Radiant.get_siwe_address_by_user(object) }


  # add_model_callback(User, :before_save) do
  #   puts "saving user #{self.username}"
  #   self.custom_fields["radiant_dollars"] = Radiant.get_rdnt_amount(self)
  # end
end
