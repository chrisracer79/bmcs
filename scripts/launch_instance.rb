require 'oraclebmc'


public_key_file = "/Users/cparent/.oraclebmc/id_rsa.pub"
ADS = ["KVnC:PHX-AD-1", "KVnC:PHX-AD-2", "KVnC:PHX-AD-3"]
OCI_compartment_id = "ocid1.compartment.oc1..aaaaaaaad3lx3grr64g4s6i3s3moxf4pfgacz2rc42grki4up5rytmhoz7xa"
image_name="Oracle-Linux-7.3-2016.12.23-0"
image_id='ocid1.image.oc1.phx.aaaaaaaaifdnkw5d7xvmwfsfw2rpjpxe56viepslmmisuyy64t3q4aiquema'

shape_name="VM.Standard1.4"

ssh_public_key = File.open(File.expand_path(public_key_file), "rb").read

# Create an image
client = OracleBMC::Core::ComputeClient.new 
response = client.list_images(OCI_compartment_id)
puts response.data.to_s


request = OracleBMC::Core::Models::LaunchInstanceDetails.new
request.availability_domain = ADS[0] # TODO: Set an availability domain, such as 'kIdk:PHX-AD-2'
request.compartment_id = OCI_compartment_id # TODO: set your compartment ID here
request.display_name = 'cmp_instance'
request.image_id = image_id
request.shape = shape_name
request.subnet_id = "ocid1.subnet.oc1.phx.aaaaaaaadq2cx4pobiwuxzwy4zhcgjrdda37eluf6rgwx4ft2gbkvoy5l57q"  # TODO: set your subnet ID here
request.metadata = {'ssh_authorized_keys' => ssh_public_key}

api = OracleBMC::Core::ComputeClient.new
response = api.launch_instance(request)
instance_id = response.data.id
response = api.get_instance(instance_id).wait_until(:lifecycle_state, OracleBMC::Core::Models::Instance::LIFECYCLE_STATE_RUNNING)