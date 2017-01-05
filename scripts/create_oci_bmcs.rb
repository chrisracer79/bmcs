#!/usr/bin/env ruby
# ------------------------------------------------------------
# Create GBU networking objects in BMaaS
#
# Bare Metal Ruby SDK can be downloaded from here:
# https://docs.us-phoenix-1.oraclecloud.com/tools/ruby/1.0.1/frames.html
# ------------------------------------------------------------
 
require 'oraclebmc'
require 'pp'
 
# ------------------------------------------------------------
# Data/Constants
# ------------------------------------------------------------
 
GBUREGION = OracleBMC::Regions::REGION_US_PHOENIX_1
MASTER_CNAME = "Master"
MASTER_COMPARTMENT_ID = "ocid1.compartment.oc1..aaaaaaaamu6dhp3sdbtb3ojopk5ii7iphpmwqpzgi4fhalup2aiocstaej4q"
MASTER_VCN_CIDR = "10.0.0.0/16"
MASTER_ABBR = "cmp-test-master"
ADS = ["KVnC:PHX-AD-1", "KVnC:PHX-AD-2", "KVnC:PHX-AD-3"]
 
# Subnets list of lists for each AD
gbuData = [
  ["oci", "OCI", [["10.0.1.0/24"], ["10.0.2.0/24"], ["10.0.3.0/24"]]],
  ["ocisb", "OCI-Sandbox", [["10.0.4.0/24"], ["10.0.5.0/24"], ["10.0.6.0/24"]]]
]
 
# ------------------------------------------------------------
# Define and populate data structures
# ------------------------------------------------------------
 
# Class to hold info about each GBU
class GBUInfo
 
  attr_accessor(
    :cname,                   # compartment display_name
    :compartment_id,          # OCID of compartment
    :ad_nets,                 # nested list of subnets within AD
    :ad_net_ids,              # nested list of subnet OCID within AD
    :route_table_id,          # OCID
    :sec_list_id              # OCID
    )
 
  def initialize(c, azn)
    @cname = c
    @ad_nets = azn
  end
 
end
 

def cleanup

end

 
def createGBUHash(data)
  h = Hash.new
  data.each { |g| h[g[0]] = GBUInfo.new(g[1], g[2])}
  return h
end
 
gbuDataH = createGBUHash(gbuData)
 
# ------------------------------------------------------------
#
# ------------------------------------------------------------
 
 
# ------------------------------------------------------------
# Execute Object Creation
# ------------------------------------------------------------
 
# Get an API object for VirtualNetworkClient
api = OracleBMC::Core::VirtualNetworkClient.new(region: GBUREGION)
 
# Create the Master VCN
vcnModel = OracleBMC::Core::Models::CreateVcnDetails.new
vcnModel.cidr_block = MASTER_VCN_CIDR
vcnModel.compartment_id = MASTER_COMPARTMENT_ID
vcnModel.display_name = MASTER_ABBR + "-vcn"
response = api.create_vcn(vcnModel)
# Get the model object from the response
myVCN = response.data
 
# Create the Internet Gateway in Master VCN
igwModel = OracleBMC::Core::Models::CreateInternetGatewayDetails.new
igwModel.compartment_id = MASTER_COMPARTMENT_ID
igwModel.display_name = MASTER_ABBR + "-igw"
igwModel.is_enabled = true
igwModel.vcn_id = myVCN.id
response = api.create_internet_gateway(igwModel)
myIGW = response.data

puts "VCN: " + response.data.to_s
puts "VCN status: " + response.status.to_s

 
# ------------------------------------------------------------
# Collect Compartment ID's and build a hash from name to id
# ------------------------------------------------------------
 
# Get an API object for IAM
iamApi = OracleBMC::Identity::IdentityClient.new(region: GBUREGION)
# Get a list of all Compartment objects
response = iamApi.list_compartments(OracleBMC.config.tenancy)
myCompartments = response.data
 
myCompIDs = Hash.new
myCompartments.each { |c| myCompIDs[c.name] = c.id }
 
# Save in gbuDataH
gbuDataH.each_value { |k| k.compartment_id = myCompIDs[k.cname] }
 
# ------------------------------------------------------------
# Create route table and sec list for each GBU
# ------------------------------------------------------------
 
# Route rule(s) to assign to each routing table
rrModel = OracleBMC::Core::Models::RouteRule.new
rrModel.cidr_block = "0.0.0.0/0"
rrModel.network_entity_id = myIGW.id
 
# Template route table model
rtModel = OracleBMC::Core::Models::CreateRouteTableDetails.new
rtModel.route_rules = [rrModel]
rtModel.vcn_id = myVCN.id
 
# SecList rules
# Dumped from default sec list as arrays of hashes to be used by build_from_hash
ingressSLData = [
  {:protocol=>"6", :source=>"0.0.0.0/0", :tcpOptions=>{:destinationPortRange=>{:max=>22, :min=>22}}},
  {:icmpOptions=>{:code=>4, :type=>3}, :protocol=>"1", :source=>"0.0.0.0/0"},
  {:icmpOptions=>{:type=>3}, :protocol=>"1", :source=>"10.0.0.0/16"}
]
 
egressSLData = [
  {:destination=>"0.0.0.0/0", :protocol=>"all"}
]
 
ingRules = Array.new
ingressSLData.each do | d |
  ingRules.push(OracleBMC::Core::Models::IngressSecurityRule.new.build_from_hash(d))
end
 
egrRules = Array.new
egressSLData.each do | d |
  egrRules.push(OracleBMC::Core::Models::EgressSecurityRule.new.build_from_hash(d))
end
 
slModel = OracleBMC::Core::Models::CreateSecurityListDetails.new
slModel.egress_security_rules = egrRules
slModel.ingress_security_rules = ingRules
slModel.vcn_id = myVCN.id
 
# Subnet Model
snModel = OracleBMC::Core::Models::CreateSubnetDetails.new
snModel.vcn_id = myVCN.id
snModel.dhcp_options_id = myVCN.default_dhcp_options_id
 
# Iterate over GBUs
gbuDataH.each_pair do | gbu, gbudata |
 
  rtModel.compartment_id = gbudata.compartment_id
  rtModel.display_name = gbu + "_rt"
  response = api.create_route_table(rtModel)
  # Save id with GBU Info
  gbudata.route_table_id = response.data.id
 
  slModel.compartment_id = gbudata.compartment_id
  slModel.display_name = gbu + "_sl"
  response = api.create_security_list(slModel)
  # Save id with GBU Info
  gbudata.sec_list_id = response.data.id
 
  # Create subnets (joint iteration over AD's and subnets)
  gbudata.ad_net_ids = Array.new
  ad_number = 0
  ADS.zip(gbuDataH[gbu].ad_nets).each do | ad, sns |
    ids = Array.new
    ad_number += 1
 
    sn_number = 0
    sns.each do | sn |
      sn_number += 1
      # Create the subnet
      snModel.availability_domain = ad
      snModel.cidr_block = sn
      snModel.compartment_id = gbudata.compartment_id
      snModel.route_table_id = gbudata.route_table_id
      snModel.security_list_ids = [gbudata.sec_list_id]
      snModel.display_name = gbu + "_ad_" + ad_number.to_s + "_sn_" + sn_number.to_s
      response = api.create_subnet(snModel)
      ids.push(response.data.id)
    end
    gbudata.ad_net_ids.push(ids)
  end
end
 