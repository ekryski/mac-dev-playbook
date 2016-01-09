# Mac Development Ansible Playbook

This playbook installs and configures most of the software I use on my Mac for web and software development. Some things in OS X are difficult to automate (notably, the Mac App Store and certain tools from Apple), so I still have some manual installation steps, but at least it's all documented here.

This is a work in progress, and is mostly a means for me to document my current Mac's setup. I'll be adding settings and packages to this repository over time. It was originally forked from [geerlingguy/mac-dev-playbook](https://github.com/geerlingguy/mac-dev-playbook).

## Installation

  1. [Install Ansible](http://docs.ansible.com/intro_installation.html).
  2. Download and install Xcode.
  3. Ensure Apple's command line tools are installed (`xcode-select --install` to launch the installer).
  4. Clone this repository to your local drive.
  5. Run the command `$ ansible-galaxy install -r requirements.txt` inside this directory to install required Ansible roles.
  6. Run `ansible-playbook main.yml -i inventory --ask-sudo-pass` from the same directory as this README file.

## Included Applications / Configuration

View the [main.ym]() file to see what applications are installed.

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

  - I have vim configuration in the repo, but I still need to add the actual installation:
    ```
    mkdir -p ~/.vim/autoload
    mkdir -p ~/.vim/bundle
    cd ~/.vim/autoload
    curl https://raw.githubusercontent.com/tpope/vim-pathogen/master/autoload/pathogen.vim > pathogen.vim
    cd ~/.vim/bundle
    git clone git://github.com/scrooloose/nerdtree.git
    ```

## Testing the Playbook

Many people have asked me if I often wipe my entire workstation and start from scratch just to test changes to the playbook. Nope! Instead, I use Jeff Geerling's posted instructions for how to build a [Mac OS X VirtualBox VM](https://github.com/geerlingguy/mac-osx-virtualbox-vm), on which I can continually run and re-run this playbook to test changes and make sure things work correctly.
