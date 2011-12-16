# -*- coding: utf-8 -*-

module Dcmgr
  module VNet
    # This file stores the factories. It is their job to read config files etc. to decide which implementation to use.
    V = Dcmgr::VNet
    class ControllerFactory
      def self.create_controller(node)
        V::Netfilter::NetfilterController.new(node)
      end
    end
    
    class IsolatorFactory
      def self.create_isolator
        V::Isolators::BySecurityGroup.new
        #V::Isolators::DummyIsolator.new
      end
    end
    
    class TaskManagerFactory
      def self.create_task_manager(node)
        manager = V::Netfilter::VNicProtocolTaskManager.new
        manager.enable_ebtables = node.manifest.config.enable_ebtables
        manager.enable_iptables = node.manifest.config.enable_iptables
        manager.verbose_commands = node.manifest.config.verbose_netfilter
        
        manager
      end
    end
    
    class TaskFactory
      extend Dcmgr::Helpers::NicHelper
      include V::Tasks

      def self.create_tasks_for_isolation(vnic,friends,node)
        tasks = []
        enable_logging = node.manifest.config.packet_drop_log
        friend_ips = friends.map {|vnic_map| vnic_map[:ipv4][:address]}
        
        tasks << AcceptARPFromFriends.new(vnic[:ipv4][:address],friend_ips,enable_logging,"A arp friend #{vnic[:uuid]}")
        #tasks << AcceptIpFromFriends(friend_ips)
        
        tasks
      end

      # Returns the tasks required for applying this security group
      def self.create_tasks_for_secgroup(secgroup)
        [SecurityGroup.new(secgroup)]
      end

      # Returns the tasks that drop all traffic
      def self.create_drop_tasks_for_vnic(vnic,node)
        enable_logging = node.manifest.config.packet_drop_log

        #TODO: Add logging to ip drops
        [DropIpFromAnywhere.new, DropArpForwarding.new(enable_logging,"D arp #{vnic[:uuid]}: ")]
      end
      
      # Creates tasks related to network address translation
      def self.create_nat_tasks_for_vnic(vnic,friends,node)
        friend_ips = friends.map {|vnic_map| vnic_map[:ipv4][:address]}
        ipset_enabled = node.manifest.config.use_ipset
        tasks = []
        
        tasks << TranslateMetadataAddress.new(vnic[:ipv4][:network][:metadata_server],vnic[:ipv4][:network][:metadata_server_port]) unless vnic[:ipv4][:network][:metadata_server].nil? || vnic[:ipv4][:network][:metadata_server_port].nil?
        
        # Nat tasks
        if is_natted? vnic          
          # Exclude instances in the same security group form using nat
          if ipset_enabled
            # Not implemented yet
            #tasks << ExcludeFromNatIpSet.new(friend_ips,vnic[:ipv4][:address])
          else
            tasks << ExcludeFromNat.new(friend_ips,vnic[:ipv4][:address])
          end
          
          tasks << StaticNatLog.new(vnic[:ipv4][:address], vnic[:ipv4][:nat_address], "SNAT #{vnic[:uuid]}", "DNAT #{vnic[:uuid]}") if node.manifest.config.packet_drop_log
          tasks << StaticNat.new(vnic[:ipv4][:address], vnic[:ipv4][:nat_address], clean_mac(vnic[:mac_addr]))
        end
        
        tasks
      end

      #Returns the netfilter tasks required for this vnic
      # The _friends_ parameter is an array of vnic_maps that should not be isolated from _vnic_
      def self.create_tasks_for_vnic(vnic,friends,security_groups,node)
        tasks = []

        host_addr = Isono::Util.default_gw_ipaddr
        enable_logging = node.manifest.config.packet_drop_log
        ipset_enabled = node.manifest.config.use_ipset
        
        tasks += self.create_nat_tasks_for_vnic(vnic,friends,node)
        
        # General data link layer tasks
        tasks << AcceptArpBroadcast.new(host_addr,enable_logging,"A arp bc #{vnic[:uuid]}: ")
        tasks << DropIpSpoofing.new(vnic[:ipv4][:address],enable_logging,"D arp sp #{vnic[:uuid]}: ")
        tasks << DropMacSpoofing.new(clean_mac(vnic[:mac_addr]),enable_logging,"D ip sp #{vnic[:uuid]}: ")
        tasks << AcceptARPToHost.new(host_addr,vnic[:ipv4][:address],enable_logging,"A arp to_host #{vnic[:uuid]}: ")
        tasks << AcceptARPFromGateway.new(vnic[:ipv4][:network][:ipv4_gw],enable_logging,"A arp from_gw #{vnic[:uuid]}: ") unless vnic[:ipv4][:network][:ipv4_gw].nil?
        
        # General ip layer tasks
        tasks << AcceptIcmpRelatedEstablished.new
        tasks << AcceptTcpRelatedEstablished.new
        tasks << AcceptUdpEstablished.new
        tasks << AcceptAllDNS.new
        tasks << AcceptWakameDHCPOnly.new(vnic[:ipv4][:network][:dhcp_server]) unless vnic[:ipv4][:network][:dhcp_server].nil?
        # Accept OUTGOING traffic from instances to anywhere in the network
        #tasks << AcceptIpToAnywhere.new
        
        # VM isolation based
        tasks += self.create_tasks_for_isolation(vnic,friends,node)
        
        # Accept ip traffic from the gateway that isn't blocked by other tasks
        tasks << AcceptIpFromGateway.new(vnic[:ipv4][:network][:ipv4_gw]) unless vnic[:ipv4][:network][:ipv4_gw].nil?
        
        # Security group tasks
        security_groups.each { |secgroup|
          tasks += self.create_tasks_for_secgroup(secgroup)
        }
                  
        # Drop any other incoming traffic
        # MAKE SURE THIS TASK IS ALWAYS EXECUTED LAST OR I WILL KILL YOU
        tasks += self.create_drop_tasks_for_vnic(vnic,node)
        
        tasks
      end
    end
      
  end
end
