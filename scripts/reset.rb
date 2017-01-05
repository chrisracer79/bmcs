require 'oraclebmc'

vcn_id = 'ocid1.vcn.oc1.phx.aaaaaaaa74ehfyu567vim7qi7qaxvzn4ktvd2m2be5ufov6opklc56r4pgvq'
tenancy_id = 'ocid1.tenancy.oc1..aaaaaaaa6gtmn46bketftho3sqcgrlvdfsenqemqy3urkbthlpkos54a6wsa'

# get list of Compartments

iams = OracleBMC::Identity::IdentityClient.new 
response = iams.list_compartments tenancy_id
compartments = response.data

#puts compartments.to_s

# get list of subnets 

api = OracleBMC::Core::VirtualNetworkClient.new

compartments.each do |c| 
	response = api.list_subnets c.id, vcn_id
	
	# loop through each subnet
	response.data.each do |s|
		puts " Removing subnet: " + s.display_name
		
		subnet = api.get_subnet(s.id)
		status = api.delete_subnet(s.id)
		response = subnet.wait_until(:lifecycle_state, OracleBMC::Core::Models::Instance::LIFECYCLE_STATE_TERMINATING)
		
		#puts status.status.to_s
		
	end
end


# loop through each compartment 
compartments.each do |c| 
	
	# delete sec lists
	response = api.list_security_lists c.id, vcn_id
	response.data.each do |sl|
		
		if sl.display_name.match('Default.*')
			puts "found the default"
		else
			puts "Removing security list: " + sl.display_name
			status = api.delete_security_list sl.id
			response = api.get_security_list(sl.id).wait_until(:lifecycle_state, OracleBMC::Core::Models::Instance::LIFECYCLE_STATE_TERMINATING)
		end
	end
end

compartments.each do |c| 

	# delete route table
	response = api.list_route_tables c.id, vcn_id
	response.data.each do |rt|
		puts rt.id
		
		if rt.display_name.match('Default')
			puts "found the default"
		else
			puts "Removing route table " + rt.display_name
			api.delete_route_table(rt.id)
			response = api.get_route_table(rt.id).wait_until(:lifecycle_state, OracleBMC::Core::Models::Instance::LIFECYCLE_STATE_TERMINATING)
		end
	end
	
	
	
end

compartments.each do |c| 
# delete internet gateway
	
	response = api.list_internet_gateways c.id, vcn_id
	
	response.data.each do |ig|
		puts "Removing IG: " + ig.display_name
		status = api.delete_internet_gateway(ig.id)
		response = api.get_internet_gateway(ig.id).wait_until(:lifecycle_state, OracleBMC::Core::Models::Instance::LIFECYCLE_STATE_TERMINATING)
	end
end

puts "removing VCN"

api.delete_vcn vcn_id



#puts response.data.to_s

