# Conservative Docker Resource Pruning

This script is a conservative alternative to [`docker system prune`][prune]. It
is tuned for automatic cleanup, but can be used directly from the command-line.
In this case, you should probably first run it with the option `--dry-run` in
order to assess what will be removed. The script also comes as Docker [image].

  [prune]: https://docs.docker.com/engine/reference/commandline/system_prune/
  [image]: https://hub.docker.com/r/yanzinetworks/prune  

By default, the script will prune exited containers, dangling volumes and
dangling images with the following twist. All defaults are conservative, they
can be changed for more aggressive decisions.

+ All exited containers will be removed, and this provides filtering
  capabilities similar to the [prune][cprune] command. When removing containers,
  the script can used the `--names` and `--exclude` command-line options to
  consider only a subset of the containers.
+ All dangling images will be removed. This also provides filtering capabilities
  similar to the [prune][iprune] command. When removing images, the script will
  only consider images that were created a long time ago (6 months by default,
  but this can be changed using the `--age` option).
+ All "empty" dangling volumes will be removed. The script will count the files
  inside the volumes, only removing the ones which have less than `--limit`
  files, which defaults to `0`. In addition, the script will respect the value
  of `--names` and `--exclude` in order to better focus on subsets of the
  dangling volumes. File count is achieved through mounting the volumes into a
  temporary [busybox] container.

  [cprune]: https://docs.docker.com/engine/reference/commandline/container_prune/
  [iprune]: https://docs.docker.com/engine/reference/commandline/image_prune/
  [busybox]: https://hub.docker.com/_/busybox

## Command-Line Options

The script accepts both short "one-letter" options, and double-dashed longer
options. Long options can be written with an `=` sign or with their argument
separated from the option using a space separator. The options are as follows:

### `-v` or `--verbose`

This will increase the verbosity of the script, output will be sent to the
`stderr` and lines will contain the name of the script, together with the
timestamp. When used in interactive mode, the script will automatically colour
the log.

### `-h` or `--help`

Print out help and exit.

### `--dry-run` or `--dryrun`

Just print out what would be perform, do not remove anything at all. This option
can be used to assess what the script would do when experimenting with options
such as `--names`, `--exclude` or `--age`.

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
expressed in human-readable format, e.g. `6m` (for 6 months), `3 days`, etc.

### `--busybox`

Docker busybox image tag to be used for volume content collection. You shouldn't
have to change this in most cases.

## Docker

This script also comes as a Docker [image]. To be able to run it from a
container, you will have to pass the Docker socket to the container, e.g.

```shell
docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock:ro yanzinetworks/prune --help
```