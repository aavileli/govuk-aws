#!/bin/bash

terraform_version="\"= 0.10.6\""

for file in "$(find terraform/projects/*/main.tf)"; do

  # Get the file paths of all of the files with specified Terraform versions.
  required_terraform_version_file_paths=$(grep -H "required_version =" $file | sort | awk '{ print $1 }' | sed 's/://');
  echo $required_terraform_version_file_paths

  echo "-------------"

  # Get the file paths of the files with the correct Terraform version.
  correct_terraform_version_file_paths=$(grep -H "required_version = ${terraform_version}" $file | sort | awk '{ print $1 }' | sed 's/://');
  echo $correct_terraform_version_file_paths

  echo "-------------"

  # Diff the two variables.
  # TODO: Diff probably needs some options. The file_path variables print as
  # one line, so we should split their contents on spaces, otherwise there's a
  # huge blob which doesn't diff in any sensible way.
  diff <(echo ${correct_terraform_version_file_paths}) <(echo ${required_terraform_version_file_paths});
done
