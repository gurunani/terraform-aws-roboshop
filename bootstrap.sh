  #!/bin/bash

component=$1
env=$2

# install ansible and pip
dnf install -y ansible python3-pip

# make sure boto3 and botocore are installed for Ansible's interpreter
pip3 install --upgrade boto3 botocore

# explicitly tell Ansible to use python3
export ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3

# pull and run the playbook
ansible-pull -U https://github.com/daws-84s/ansible-roboshop-roles-tf.git \
  -e component=$component \
  -e env=$env \
  -e MONGODB_HOST=mongodb-${env}.gurulabs.xyz \
  main.yaml