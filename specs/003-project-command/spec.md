# Project command distribution

Users receive project from workBenches setup or the global command installer.
Existing onp/new-project.sh invocations preserve name and parent arguments.
Pin metadata identifies source commit and executable SHA-256. Missing sources,
corrupt bytes and non-regular targets refuse without replacing the command.
Installation must work without network with an explicitly supplied pinned file.
