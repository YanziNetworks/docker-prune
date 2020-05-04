# Conservative Docker Resource Pruning

This script is a conservative alternative to [`docker system prune`][prune]. It
is tuned for automatic cleanup, but can be used directly from the command-line.
In this case, you should probably first run it with the option `--dry-run` in
order to assess what will be removed. The script also comes as Docker [image].
The script depends on [yu.sh], which is made explicit through a git [submodule].
You probably want to use the `--recurse-submodules` flag when running `clone`
the first time.

  [prune]: https://docs.docker.com/engine/reference/commandline/system_prune/
  [image]: https://hub.docker.com/r/yanzinetworks/prune
  [yu.sh]: https://github.com/YanziNetworks/yu.sh
  [submodule]: https://git-scm.com/book/en/v2/Git-Tools-Submodules

## Removal Decisions

By default, the script will prune exited containers, dangling volumes and
dangling images with the following twist. All defaults are conservative, they
can be changed for more aggressive decisions.

### Containers

All exited, dead and stale containers will be removed, and this provides
filtering capabilities similar to the [prune][cprune] command. Containers that
have a name that was automatically generated by Docker at creation time are
automatically selected. In addition, when removing containers, the script can
use the `--names` and `--exclude` command-line options to consider only a subset
of the containers.

Exited and dead containers are as reported by Docker. Stale containers are
containers that are created but have not moved to any other state after a given
timeout.

In addition, it is possible to forcedly remove ancient, but still running
containers using the `--ancient` option. This might be a dangerous operation,
and it is turned off by default.

  [cprune]: https://docs.docker.com/engine/reference/commandline/container_prune/

### Images

All dangling and orphan images will be removed. This also provides filtering
capabilities similar to the [prune][iprune] command. When removing images, the
script will only consider images that were created a long time ago (6 months by
default, but this can be changed using the `--age` option).

Dangling images are layers that have no relationship to any tagged images.
Orphan images are images that are not used by any container, whichever state the
container is in (including created or exited state).

  [iprune]: https://docs.docker.com/engine/reference/commandline/image_prune/

### Volumes

All "empty" dangling volumes will be removed. The script will count the files
inside the volumes, only removing the ones which have less than `--limit` files,
which defaults to `0`. In addition, the script will respect the value of
`--names` and `--exclude` in order to better focus on subsets of the dangling
volumes. Volumes that have a name that was automatically generated are
automatically selected. File count is achieved through mounting the volumes into
a temporary [busybox] container.

  [busybox]: https://hub.docker.com/_/busybox

## Command-Line Options

The script accepts both short "one-letter" options, and double-dashed longer
options. Long options can be written with an `=` sign or with their argument
separated from the option using a space separator. The options are as described
below. In addition, all remaining arguments will be understood as a command to
execute once cleanup has finished, if relevant. It is possible to separate the
options and their values, from the remaining finalising command using a double
dash, `--`.


### `-v` or `--verbose`

This will select the verbosity of the script (default: `info`), output will be
sent to the `stderr` and lines will contain the name of the script, together
with the timestamp. When used in interactive mode, the script will automatically
colour the log. Available levels are: `error`, `warn`, `notice`, `info`,
`debug`.

### `--non-interactive`, `--no-colour` or `--no-color`

Forcedly remove colouring from logs. Otherwise, logs will be coloured in
interactive mode, but kept without colouring when invoked within pipes or
without a (pseudo-)tty.

### `-h` or `--help`

Print out help and exit.

### `--dry-run` or `--dryrun`

Just print out what would be perform, do not remove anything at all. This option
can be used to assess what the script would do when experimenting with options
such as `--names`, `--exclude`, `--age` or `--ancient`.

### `-r` or `--resources`

Space separated list of Docker resources to consider for removal, defaults to
`images volumes containers`. This can be used to focus on a subset of the
dangling resources to remove.

### `-l` or `--limit`

Maximum number of files in a dangling volume to consider it "empty" and consider
it for removal. Defaults to `0`.

### `-n` or `--names`

Regular expression matching names of dangling volumes and exited containers to
consider for removal. The option defaults to an empty expression, which will be
understood as all. When selecting with `--names`, it is possible to remove a few
resources from that subset with `--exclude`.

### `-x` or `--exclude`

Regular expression to exclude from particular volume and container names using
the `--names` option. This eases selecting away important containers/volumes
that should be kept.

### `-a` or `--age`

Age of dangling images to consider for removal (default: `6m`). The age can be
expressed in human-readable format, e.g. `6m` (for 6 months), `3 days`, etc. Set
this to an empty string to skip removal of named dangling images totally.

### `--ancient`

Age of running containers to consider for removal (default: empty). The age can
be expressed in human-readable format, e.g. `6m` (for 6 months), `3 days`, etc.
Unnamed containers or containers that match the `--names` and `--exclude` filter
and exclusion will be forced removed. This operation cannot be undone! The
default is an empty sting, in which case no running container will ever be
stopped and removed.

### `-t` or `--timeout`

Time to wait for created containers to not change state before they are deemed
stale and considered for removal. This can be expressed in human-readable format
similarly to `--age`, and defaults to `30s`.

### `--intermediate`

When given, this flag will consider intermediate images for removal. As these
images are usually the result of calls to `docker build`, they do not carry any
tags. This means that even recent intermediate images will be removed, leading
to removal of cached build data. This may not be what you would expect and
exists, consequently as a flag that needs to be explicitely turned on.

### `--busybox`

Docker busybox image tag to be used for volume content collection. You shouldn't
have to change this in most cases.

### `--namesgen` or `--names-gen` or `--names-generator`

Should point to the [source] of the [golang] implementation of the Docker random
container names generator. Content from this file will dynamically be read and
parsed at run-time to detect if containers are "unnamed" containers.

  [source]: https://raw.githubusercontent.com/moby/moby/master/pkg/namesgenerator/names-generator.go
  [golang]: https://golang.org/

## Environment Variables

This script also recognises a number of environment variables, these can be used
instead of (some of) the command-line options. Command-line options always have
precedence over the environment variables. Recognised variables are:

- `BUSYBOX`: same as `--busybox`
- `MAXFILES`: same as `--limit`
- `NAMES`: same as `--names`
- `EXCLUDE`: same as `--exclude`
- `RESOURCES`: same as `--resources`
- `AGE`: same as `--age`
- `ANCIENT`: same as `--ancient`
- `TIMEOUT`: same as `--timeout`

## Docker

This script also comes as a Docker [image]. To be able to run it from a
container, you will have to pass the Docker socket to the container, e.g.

```shell
docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock:ro yanzinetworks/prune --help
```

## Examples

### GitLab Runners

GitLab [runners] might leave Docker containers behind. To conservatively clean
possible remainings from your CI/CD pipelines, you could run the following
command. You probably want to add the `--dry-run` flag the first time in order
to double check what the command would do...

```shell
./prune.sh \
    --verbose debug \
    --names '^runner-[[:alnum:]_]+-project-[0-9]+-.*' \
    --age 2d
```

  [runners]: https://docs.gitlab.com/runner/