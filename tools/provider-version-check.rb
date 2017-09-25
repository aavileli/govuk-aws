terraform_version = "\"= 0.10.6\""

Dir['terraform/projects/*/main.tf'].each do |file|
  @actual_tf_version = %x[grep -H 'required_version =' #{file} | sort | awk '{ print $1 }' | sed 's/://'].split(" ").to_a
  @up_to_date_tf_version = %x[grep -H 'required_version = #{terraform_version}' #{file} | sort | awk '{ print $1 }' | sed 's/://'].split(" ").to_a
end

bad_tf_versions = (@actual_tf_version - @up_to_date_tf_version).join(", ")
verb = bad_tf_versions.split(", ").count == 1 ? "is" : "are"
puts "#{bad_tf_versions} #{verb} not on Terraform version #{terraform_version.split("= ")[1].chomp('"')}."
