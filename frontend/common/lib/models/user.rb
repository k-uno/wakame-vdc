# -*- coding: utf-8 -*-
module Frontend::Models
  class User < BaseNew
    taggable 'u' 
    plugin :single_table_inheritance, :uuid, :model_map=>{}
    plugin :subclasses

    inheritable_schema do
      String :name, :fixed=>true, :size=>200, :null=>false
    end

    many_to_many :accounts,:join_table => :users_accounts
    
    class << self
      def authenticate(login_id,password)
        return nil if login_id.nil? || password.nil?
        u = User.find(:login_id=>login_id, :password => password)
        u.nil? ? false : u
      end
  
      def get_user(uuid)
        return nil if uuid.nil?
        u = User.find(:uuid=>uuid)
        u.nil? ? false : u
      end
      
      def account_name_with_uuid(uuid)
        h = Hash.new
        User.find(:uuid => uuid).accounts.each{|row| h.store(row.name,row.uuid) }
        h
      end
      
      def primary_account_id(uuid)
        User.find(:uuid => uuid).primary_account_id
      end
    end
  end
end