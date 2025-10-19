#!/bin/bash

component=$1
env=$2

# Install Ansible and pip
dnf install -y ansible python3-pip

# Install boto3 and botocore for Ansible
pip3 install --upgrade boto3 botocore

# Set Ansible to use Python 3
export ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3

# Run Ansible playbook with correct hostnames
ansible-pull -U https://github.com/gurunani/ansible-roboshop-roles-tf.git \
  -e component=$component \
  -e env=$env \
  -e MONGODB_HOST=mongodb-${env}.gurulabs.xyz \
  -e REDIS_HOST=redis-${env}.gurulabs.xyz \
  -e MYSQL_HOST=mysql-${env}.gurulabs.xyz \
  -e RABBITMQ_HOST=rabbitmq-${env}.gurulabs.xyz \
  main.yaml
