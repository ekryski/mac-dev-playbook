# Ansible Role: Dotfiles

Installs a set of dotfiles from a given Git repository. By default, it will install my (ekryski's) [dotfiles](https://github.com/ekryski/dotfiles), but you can use any set of dotfiles you'd like, as long as they follow a conventional format.

## Requirements

None.

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

    dotfiles_repo: "https://github.com/ekryski/dotfiles.git"

The git repository to use for retrieving dotfiles. Dotfiles should generally be laid out within the root directory of the repository.

    dotfiles_repo_local_destination: "~/Documents/dotfiles"

The local path where the `dotfiles_repo` will be cloned.

    dotfiles_home: "~"

The home directory where dotfiles will be linked. Generally, the default should work, but in some circumstances, or when running the role as sudo on behalf of another user, you may want to specify the full path.

    dotfiles_files:
      - .bash_profile
      - .gitignore
      - .inputrc
      - .vimrc

Which files from the dotfiles repository should be linked to the `dotfiles_home`.

## Dependencies

None

## Example Playbook

    - hosts: localhost
      roles:
        - { role: ekryski.dotfiles }

## License

MIT
