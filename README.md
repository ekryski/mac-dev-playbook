# Mac Development Ansible Playbook

This playbook installs and configures most of the software I use on my Mac for web and software development. Some things in OS X are difficult to automate (notably, the Mac App Store and certain tools from Apple), so I still have some manual installation steps, but at least it's all documented here.

This is a work in progress, and is mostly a means for me to document my current Mac's setup. I'll be adding settings and packages to this repository over time. It was originally forked from [geerlingguy/mac-dev-playbook](https://github.com/geerlingguy/mac-dev-playbook).

## Installation

  1. [Install Ansible](http://docs.ansible.com/intro_installation.html).
  2. Download and install Xcode.
  3. Ensure Apple's command line tools are installed (`xcode-select --install` to launch the installer).
  4. Clone this repository to your local drive.
  5. Run `ansible-playbook main.yml -i inventory --ask-sudo-pass` from the same directory as this README file or run it in Vagrant using the instructions below.

## Included Applications / Configuration

View this [main.yml](https://github.com/ekryski/mac-dev-playbook/blob/master/vars/main.yml) file to see what applications are installed.

My [dotfiles](https://github.com/ekryski/dotfiles) are also installed into the current user's home directory, including the `.osx` dotfile for configuring many aspects of Mac OS X for better performance and ease of use.

Finally, there are a few other preferences and settings added on for various apps and services.

## Future additions

### Things that still need to be done manually

It's my hope that I can get the rest of these things wrapped up into Ansible playbooks soon, but for now, these steps need to be completed manually (assuming you already have Xcode and Ansible installed, and have run this playbook).

  1. Generate SSH key and upload it to Github and Bitbucket
  2. Set Homebrew Github access token:
  
      ```
      Try again in 44 minutes 12 seconds, or create a personal access token:
      https://github.com/settings/tokens/new?scopes=&description=Homebrew and then set the token as: HOMEBREW_GITHUB_API_TOKEN
      ```
  
  3. Install [Sublime Package Manager](http://sublime.wbond.net/installation).
  4. Install all the other apps (see below).
  5. Configure extra Mail and/or Calendar accounts (e.g. Google, Exchange, etc.).
  6. Install RVM for Ruby dev
  7. Install virtual_env for python dev
  8. Install latest stable ruby
  9. Install latest stable nodejs

### Applications/packages to be added:
I also use the following apps at least once or twice per week, but unfortunately, they are not able to be grabbed and installed via CLI, or any other way I can find (so far), I have to manually install all of these apps from within the App Store or from direct downloads.

  - Airmail
  - Amphetamine
  - Spotify
  - Speak
  - Screenhero
  - Sketch
  - Pixelmator
  - Principle for Mac
  - Paste
  - Omnigraffle
  - 1Password
  - Pages
  - Keynote
  - Numbers

### Configuration to be added:

  - I have Vim configuration in the repo, but I still need to add the actual installation:
  
    ```
    mkdir -p ~/.vim/autoload
    mkdir -p ~/.vim/bundle
    cd ~/.vim/autoload
    curl https://raw.githubusercontent.com/tpope/vim-pathogen/master/autoload/pathogen.vim > pathogen.vim
    cd ~/.vim/bundle
    git clone git://github.com/scrooloose/nerdtree.git
    ```

## Testing the Playbook

I don't need to wipe my entire workstation and start from scratch just to test changes to the playbook. That would suck! Instead I use Vagrant to spin up an OSX virtual machine, on which I can continually run and re-run this playbook to test changes and make sure things work correctly.

To do this simply run:

1. `vagrant init jhcook/osx-elcapitan-10.11;`
2. Add your provisioners:

  ```ruby
  Vagrant.configure(2) do |config|

    # Install Ansible first because ansible_local isn't supported
    # in Vagrant on OS X (at least not El Capitan)
    config.vm.provision "shell", inline: <<-SHELL
      sudo easy_install pip
      sudo pip install ansible
    SHELL
    
    # Run Ansible Playbook from your host machine on
    # the Vagrant Host
    config.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "playbook.yml"
      ansible.sudo = true
      ansible.inventory_path = "inventory"
    end

  end
  ```

3. `vagrant up`


### A bit more Neckbeardy

If you want to build the VirtualBox Vagrant box manually and customize it, you can follow Tim Sutton's [amazing work](https://github.com/timsutton/osx-vm-templates) to build a Mac OS X VM image with [Packer](http://packer.io).

#### TL; DR

> **NOTE:** You need to have Vagrant installed

1. Download the El Capitan installer though the app store (or whatever OSX version you want).
2. `brew install virtualbox, virtualbox-extension-pack`
3. `git clone https://github.com/timsutton/osx-vm-templates`
4. `cd osx-vm-templates`
5. `sudo prepare_iso/prepare_iso.sh -D DISABLE_REMOTE_MANAGEMENT "/Applications/Install OS X El Capitan.app" out`
6. `packer build -var iso_checksum=dc34e0dcf6c34e626a85c40f19e9a85d -var iso_url=../out/OSX_InstallESD_10.11.2_15C50.dmg -only virtualbox-iso template.json`
7. `vagrant box add virtualbox-osx-el-capitan-10.1.1 ./packer_virtualbox-iso_virtualbox.box`
8. `vagrant init virtualbox-osx-el-capitan-10.1.1`
9. Add this to your Vagrantfile:

  ```
  config.vm.provider "virtualbox" do |vb|
    # Display the VirtualBox GUI when booting the machine
    # vb.gui = true
  
    # Customize the amount of memory on the VM:
    vb.memory = "2048"

    # Setup the synced directory
    config.vm.synced_folder ".", "/vagrant", type: "rsync"
  end
  ```

10. `vagrant up`

#### Taking it a step further

Once you have tested your Ansible playbook and are happy with it. You can solidify it a bit more by setting it up as a provisioner in Packer like so:

```
{
  "type": "ansible-local",
  "playbook_file": "main.yml"
}
```

Then you can rebuild your Vagrant Box and the final image will have all your changes in Ansible applied as well!
