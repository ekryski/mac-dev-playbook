# -*- mode: ruby -*-
# vi: set ft=ruby :

VAGRANTFILE_API_VERSION = 2

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.define "localhost"

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://atlas.hashicorp.com/search.
  # We're using a local box that we built.
  config.vm.box = "virtualbox-el-capitan"

  # Provider-specific configuration for VirtualBox
  config.vm.provider "virtualbox" do |vb|
    # Display the VirtualBox GUI when booting the machine
    # vb.gui = true
  
    # Customize the amount of memory on the VM:
    vb.memory = "2048"

    # Setup the synced directory. Needs to be RSync. Regular
    # synced_folder doesn't work. Maybe NFS would work
    config.vm.synced_folder ".", "/vagrant", type: "rsync"
  end

  # Install Ansible first because ansible_local isn't supported
  # in Vagrant on OS X (at least not El Capitan)
  config.vm.provision "shell", inline: <<-SHELL
    sudo easy_install pip
    sudo pip install ansible
  SHELL
  
  #
  # Run Ansible Playbook from your host machine on
  # the Vagrant Host
  #
  config.vm.provision "ansible_local" do |ansible|
    ansible.playbook = "playbook.yml"
    ansible.sudo = true
    ansible.inventory_path = "inventory"
  end
end
