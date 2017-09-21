# Environment Provisioning

This document discusses how to create a new environment in AWS. Discussion as to the decisions taken can be found in the [architecture/decisions](architecture/decisions) directory, of particular note is [the environment bootstrapping process](architecture/decisions/0009-environment-bootstrapping-process.md).

To clarify terms used here there is a [glossary](#glossary). Throughout this document `<foo>` indicates a value you supply (e.g. a stack name) and:
```
$ bar
```
indicates a command to be run from a shell.

## Overview

The general steps for provisioning a new environment are:

1. [Clone all the relevant repositories](#cloning-the-repositories)
2. [Build the S3 bucket for Terraform state](#build-the-s3-bucket)
3. [Provision the base infrastructure](#provision-the-base-infrastructure)
4. [Build the Puppet master](#build-the-puppet-master)
5. [Deploy the puppet code and secrets](#deploy-the-puppet-code-and-secrets)
6. [Build the deploy Jenkins](#build-the-deploy-jenkins)
7. [Do the Jenkins token shuffle](#do-the-jenkins-token-shuffle)
* Rebuild everything else in the usual deployment ways

## Requirements

* [Git](https://git-scm.com/) installed via [Xcode cli tools](http://osxdaily.com/2014/02/12/install-command-line-tools-mac-os-x/)/[brew](https://brew.sh/)
* [Terraform = 0.10.6](https://www.terraform.io/downloads.html) installed via that link 
* [ssh-copy-id](https://www.ssh.com/ssh/copy-id) installed via `brew install ssh-copy-id`
* [aws-cli](https://aws.amazon.com/cli) installed via `brew install awscli` or `pip install awscli`

If you've not used the aws-cli before run
```
$ aws configure
```
to set your access id, secret and the region to use.

## Cloning the repositories

You will need to have cloned the following repositories to your local machine

* [govuk-puppet](https://github.com/alphagov/govuk-puppet)
* [govuk-secrets](https://github.com/alphagov/govuk-secrets)
* [govuk-aws-data](https://github.com/alphagov/govuk-aws-data)
* [govuk-aws (this one)](https://github.com/alphagov/govuk-aws)

e.g.
```
$ git clone git@github.com:alphagov/govuk-secrets.git
```

## Build the S3 bucket

An [S3](https://aws.amazon.com/s3/) bucket needs to be created to store state for Terraform. If you're using an account that already has this set up you can skip this step, check by running:
```
$ export ENVIRONMENT=<environment>
$ export TERRAFORM_BUCKET="govuk-terraform-steppingstone-${ENVIRONMENT}"
$ aws s3 ls $TERRAFORM_BUCKET
```

If the bucket is missing you'll see an error:
```
An error occurred (NoSuchBucket) when calling the ListObjects operation: The specified bucket does not exist
```
otherwise you'll see the bucket's contents, one directory per existing stack:
```
PRE deana/
PRE delana/
PRE govuk/
```

To create an S3 bucket run the following in order to create a bucket and enable versioning on it:
```
$ aws s3 mb "s3://${TERRAFORM_BUCKET}"
$ aws s3api put-bucket-versioning  \
        --bucket ${TERRAFORM_BUCKET} \
        --versioning-configuration Status=Enabled
```


## Provision the base infrastructure

There are several Terraform projects that need to be run to set up the base infrastructure. For each of these you should run `plan` and `apply` in the build script. If you're setting up a new stack you'll also need to create `.backend` files for each project (see [below](#creating-backend-files-for-a-new-stack)), otherwise you should use an existing one (e.g. `integration-green` or `deana`).

```
$ export DATA_DIR=<path to govuk-aws-data repository>/data
$ export STACKNAME=<stackname>
# NOTE: the ENVIRONMENT variable also needs to be set or passed to this script.

$ tools/build-terraform-project.sh -c plan -p name>
...terraform output...
$ tools/build-terraform-project.sh -c apply -p project name>
...terraform output...
```

The projects that need to be initially run in this way are:

1. `infra-vpc`
2. `infra-networking`
3. `infra-root-dns-zones`
4. `infra-stack-dns-zones`
5. `infra-security-groups`

### Creating backend files for a new stack

Each project stores its state in an S3 bucket in AWS. These are configured using a backend file which looks like and lives in the project directory.
```
# terraform/projects/<project name>/<environment>.<stack name>.backend
bucket  = "govuk-terraform-steppingstone-<environment>"
key     = "<stack name>/<project name>.tfstate"
encrypt = true
region  = "<region>"
```


## Build the Puppet Master

Puppet master is provisioned similarly to other Terraform projects but you'll need to make sure that you set the `ssh_public_key` value in `common/<environment>/<stack name>.tfvars` to the public portion of a key that you have the private portion of.

Now run

```
# Make sure STACKNAME & ENVIRONMENT are set
$ tools/build-terraform-project.sh -c plan -p app-puppetmaster
...terraform output...
$ tools/build-terraform-project.sh -c apply -p app-puppetmaster
...terraform output...
```

To test this you should be able to SSH to the puppet master using the Terraform output of the last command:
```
...Other Terraform output...

Outputs:

puppetmaster_bootstrap_elb_dns_name = <stack name>-puppetmaster-bootstrap-1234567890.eu-west-1.elb.amazonaws.com
puppetmaster_internal_elb_dns_name = internal-<stack name>-puppetmaster-0987654321.eu-west-1.elb.amazonaws.com
service_dns_name = puppet.<stack name>.<environment>.govuk-internal.digital

$ export PUPPETMASTER_ELB=<stack name>-puppetmaster-bootstrap-1234567890.eu-west-1.elb.amazonaws.com
$ ssh ubuntu@$PUPPETMASTER_ELB
```

## Deploy the Puppet code and secrets

We currently get the GPG key from the integration puppet master (in future this should be kept in the `deployment/pass` store)
```
$ ssh puppetmaster-1.integration.publishing.service.gov.uk
sudo -i

gpg --homedir /etc/puppet/gpg --export-secret-key -a "Hiera eYAML GPG key for Preview (To be placed on the Puppet Master)"
# Copy the output
exit
exit
```

Save the output of the `gpg` command to a suitable file.

Now run these commands to initialise the puppet master:
```
$ cd tools
$ bash -x ./aws-push-puppet.sh -e ${ENVIRONMENT} \
                               -g <path to the gpg key you copied> \
                               -p <path to puppet repo> \
                               -d <path to govuk-secrets repo> \
                               -t $PUPPETMASTER_ELB
$ ssh ubuntu@$PUPPETMASTER_ELB
> sudo ./aws-copy-puppet-setup.sh -e integration -s <stack name>
```

You can now test that the puppet master is working by running
```
puppet apply -e "notify {'hello world':}"

Notice: Compiled catalog for ip-10-1-2-123.eu-west-1.compute.internal in environment production in 0.02 seconds
Notice: hello world
Notice: /Stage[main]/Main/Notify[hello world]/message: defined 'message' as 'hello world'
Notice: Finished catalog run in 0.01 seconds
```

## Build the deploy Jenkins

You now need to build the deploy Jenkins:
```
$ tools/build-terraform-project.sh -c plan -p app-deploy
...terraform output...
$ tools/build-terraform-project.sh -c apply -p app-deploy
...terraform output...
```

Once this has built and provisioned you should be able to navigate to:
```
deploy.<stackname>.<environment>.govuk.digital
```

NB currently you'll need to manually build the boxes but in future you'll be able to do that via Jenkins too.

## Do the Jenkins token shuffle

For each user, Jenkins automatically generates an API token which is based upon the machine it's installed on, which means that each token is unique to each instance. Additionally, tokens stored on disk are encrypted so we are not able to manage these with Puppet in the Jenkins configuration.

We use Jenkins Job Builder to manage our jobs. This tool requires a Jenkins API user and token to be able to create jobs, and use Puppet to manage these credentials. Therefore we need to generate a token for the API user that Puppet creates, and add this token to our Puppet credentials.

Jenkins does not allow admins to view other users tokens, so there is a manual step involved.

1. SSH to the Jenkins instance
2. Edit the start up options: `sudo vim /etc/default/jenkins`
3. Append the following line to the end of `JAVA_ARGS`:

   `-Djenkins.security.ApiTokenProperty.showTokenToAdmins=true`

   It will probably look something like this:

   `JAVA_ARGS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Djenkins.security.ApiTokenProperty.showTokenToAdmins=true"`

4. Save and quit, and restart the Jenkins service: `sudo service jenkins restart`
5. You should now be able to login by going to https://deploy.\<stackname\>.\<environment\>.govuk.digital
6. Find the API user you want the token from by searching in the top bar (the default is "jenkins_api_user")
7. Click configure, and then "Show API token". Save the token, and update the credentials in the [deployment repo](https://github.digital.cabinet-office.gov.uk/gds/deployment)
8. The hiera key you're looking to update is called: `govuk::node::s_jenkins::jenkins_api_token`
9. As the Deploy_Puppet job won't yet exist, you will be unable to deploy Puppet at this point. Manually edit `/etc/jenkins_jobs/jenkins_jobs.ini` with the new token, and run the update job by running `sudo jenkins-jobs update /etc/jenkins_jobs/jobs/`.

When Jenkins Job Builder has successfully created jobs, you should then be able to deploy Puppet and applications via Jenkins to finish off the rest of the stack.

## Glossary

This just covers how these terms are used in this document.

**Environment** - A collection of stacks, these generally correspond an AWS account. Multiple stacks may exist within a single environment (e.g. "integration-blue" & "integration-green" may both exist in the integration environment).

**Stack** - An arbitrary label for a grouping of deployed resources. In general resources within one stack work together but they may depend on resources from other stacks within the same environment (e.g. blue/green stacks which may share networking resources).

**Project** - The Terraform code to deploy some resources as a single unit. A single project may contain components to support other projects (these are generally prefixed with 'infra' e.g. `infra-security-groups`) or a single project (generally prefixed with 'app' e.g. `app-graphite`).
