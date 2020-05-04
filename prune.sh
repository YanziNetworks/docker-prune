#!/usr/bin/env sh

# Shell sanity
set -eu

# Dynamic vars
cmdname=$(basename "${0}")
appname=${cmdname%.*}

# Root directory of the script
ROOT_DIR=$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )
# Our library for scripts and dependencies. Overly complex, but built with
# installation flexibility in mind.
LIB_DIR=
for _lib in lib libexec "share/$appname"; do
    [ -z "${LIB_DIR}" ] && [ -d "${ROOT_DIR}/$_lib" ] && LIB_DIR="${ROOT_DIR}/$_lib"
    [ -z "${LIB_DIR}" ] && [ -d "${ROOT_DIR}/../$_lib" ] && LIB_DIR="${ROOT_DIR}/../$_lib"
done
[ -z "$LIB_DIR" ] && echo "Cannot find library directory!" >&2 && exit 1
# Top directory for yu.sh
YUSH_DIR="$LIB_DIR/yu.sh"
! [ -d "$YUSH_DIR" ] && echo "Cannot find yu.sh directory!" >&2 && exit 1

# shellcheck disable=SC1090
. "$YUSH_DIR/log.sh"
# shellcheck disable=SC1090
. "$YUSH_DIR/date.sh"


# All (good?) defaults
DRYRUN=0
BUSYBOX=${BUSYBOX:-busybox:1.31.0-musl}
MAXFILES=${MAXFILES:-0}
NAMES=${NAMES:-}
EXCLUDE=${EXCLUDE:-}
RESOURCES=${RESOURCES:-"images volumes containers"}
AGE=${AGE:-"6m"}
ANCIENT=${ANCIENT:-}
NAMESGEN=https://raw.githubusercontent.com/moby/moby/master/pkg/namesgenerator/names-generator.go
TIMEOUT=${TIMEOUT:-"30s"}
INTERMEDIATE=0

# Print usage on stderr and exit
usage() {
    [ -n "$1" ] && echo "$1" >&2
    exitcode="${2:-1}"
    cat << USAGE >&2


Description:

  $cmdname performs some conservative Docker system pruning

Usage:
  $cmdname [-option arg --long-option(=)arg] [--] command

  where all dash-led options are as follows (long options can be followed by
  an equal sign):
    --dry(-)run      Do not remove, print out only.
    -r | --resources Space separated list of Docker resources to consider for
                     removal, defaults to "images volumes containers".
    -l | --limit     Maximum number of files in a dangling volume to consider
                     it "empty" and consider it for removal (default: 0)
    -n | --names     Regular expression matching names of dangling volumes and
                     exited containers to consider for removal (default: empty,
                     e.g. all)
    -x | --exclude   Regular expression to exclude from names selected above,
                     this eases selecting away important containers/volumes.
    -a | --age       Age of dangling image to consider it for removal (default:
                     6m). The age can be expressed in yush_human_period-readable
                     format, e.g. 6m (== 6 months), 3 days, etc.
    --ancient        Age of ancient container. Matching or unnamed containers
                     at least this old will be forced removed. Default is empty,
                     no removal at all!
    -t | --timeout   Timeout to wait for created containers to change status,
                     they will be consideyush_red as stale and removed if status
                     has not changed. This can be expressed in human-readable
                     format. Default is 30 seconds, e.g. 30s.
    --busybox        Docker busybox image tag to be used for volume content
                     collection.
    --namesgen       URL to go implementation for Docker container names
                     generator, defaults to latest at Moby GitHub project.
    -v | --verbose   Specify verbosity level: from error, down to trace
    -h | --help      Print this helt and exit

  Everything that follows these options, preferably separated from the options
  using -- is any command that will be executed, if present, at the end of the
  script.

USAGE
    exit "$exitcode"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -l | --limit)
            MAXFILES="$2"; shift 2;;
        --limit=*)
            MAXFILES="${1#*=}"; shift 1;;

        -n | --names)
            NAMES="$2"; shift 2;;
        --names=*)
            NAMES="${1#*=}"; shift 1;;

        -x | --exclude)
            EXCLUDE="$2"; shift 2;;
        --exclude=*)
            EXCLUDE="${1#*=}"; shift 1;;

        -r | --resources)
            RESOURCES="$2"; shift 2;;
        --resources=*)
            RESOURCES="${1#*=}"; shift 1;;

        -a | --age)
            AGE="$2"; shift 2;;
        --age=*)
            AGE="${1#*=}"; shift 1;;

        --ancient)
            ANCIENT="$2"; shift 2;;
        --ancient=*)
            ANCIENT="${1#*=}"; shift 1;;

        -t | --timeout)
            TIMEOUT="$2"; shift 2;;
        --timeout=*)
            TIMEOUT="${1#*=}"; shift 1;;

        --busybox)
            BUSYBOX="$2"; shift 2;;
        --busybox=*)
            BUSYBOX="${1#*=}"; shift 1;;

        --dry-run | --dryrun)
            DRYRUN=1; shift 1;;

        --intermediate)
            INTERMEDIATE=1; shift 1;;

        --names-gen | --names-generator | --namesgen)
            NAMESGEN="$2"; shift 2;;
        --names-gen=* | --names-generator=* | --namesgen=*)
            NAMESGEN="${1#*=}"; shift 1;;

        -v | --verbose)
            # shellcheck disable=SC2034
            YUSH_LOG_LEVEL=$2; shift 2;;
        --verbose=*)
            # shellcheck disable=SC2034
            YUSH_LOG_LEVEL="${1#*=}"; shift 1;;

        --non-interactive | --no-colour | --no-color)
            # shellcheck disable=SC2034
            YUSH_LOG_COLOUR=0; shift 1;;

        -h | --help)
            usage "" 0;;

        --)
            shift; break;;
        -*)
            usage "Unknown option: $1 !";;
        *)
            break;;
    esac
done

abort() {
    yush_error "$1"
    exit 1
}


# Given a name passed as argument, return 0 if it shouldn't be considered for
# removal, 1 otherwise. This implements the logic behind the --names and
# --exclude command-line options. The second argument should be the type of the
# resource to consider for removal and is only used for logging.
consider() {
    CONSIDER=0
    if [ -n "$NAMES" ]; then
        if printf %s\\n "$1"|grep -Eqo "$NAMES"; then
            if [ -z "$EXCLUDE" ]; then
                yush_info "Considering $2 $1 for removal, matching $NAMES"
                CONSIDER=1
            elif [ -n "$EXCLUDE" ] && printf %s\\n "$1"|grep -Eqov "$EXCLUDE"; then
                yush_info "Considering $2 $1 for removal, matching $NAMES but not $EXCLUDE"
                CONSIDER=1
            else
                yush_info "Skipping removal of $2 $(yush_green "$1"), matching $NAMES but also matching $EXCLUDE"
            fi
        else
            yush_info "Skipping removal of $2 $(yush_green "$1"), does not match $NAMES"
        fi
    else
        yush_info "Considering $2 $1 for removal"
        CONSIDER=1
    fi
    echo "$CONSIDER"
}

rm_container() {
    CONSIDER=0
    # Try matching the name of the container against the latest list of names
    # used by Docker to generate good random names.
    if printf %s\\n "$1" | grep -Eqo '\w+_\w+'; then
        if [ -n "$NAMES_DICTIONARY" ]; then
            left=$(printf %s\\n "$1" | sed -E 's/(\w+)_(\w+)/\1/')
            right=$(printf %s\\n "$1" | sed -E 's/(\w+)_(\w+)/\2/')
            if printf %s\\n "$NAMES_DICTIONARY" | grep -qo "$left" && printf %s\\n "$NAMES_DICTIONARY" | grep -qo "$right"; then
                yush_info "Container $1 has an automatically generated name considering it for removal"
                CONSIDER=1
            fi
        else
            yush_warn "Container $1 could be a generated one, but no names dictionary to detect"
        fi
    fi

    if [ "$CONSIDER" = "0" ]; then
        CONSIDER=$(consider "$1" container)
    fi

    if [ "$CONSIDER" = "1" ]; then
        if [ "$DRYRUN" = "1" ]; then
            yush_info "Would remove container $(yush_yellow "$1")"
        else
            yush_notice "Removing exited container $(yush_red "$1")"
            docker container rm --force --volumes "$1"
        fi
    else
        yush_debug "Keeping container $(yush_green "$1")"
    fi
}

rm_image() {
    now=$(date -u +'%s')
    # Collect image information for improved logging
    tags=$(docker image inspect --format '{{.RepoTags}}' "$1"|sed -e 's/^\[//' -e 's/\]$//')
    digests=$(docker image inspect --format '{{.RepoDigests}}' "$1"|sed -e 's/^\[//' -e 's/\]$//')

    # Compute time from image creation in seconds, old images will be considered
    # for removal.
    CONSIDER=0
    creation=$(docker image inspect --format '{{.Created}}' "$1")
    howold=$(( now - $(yush_iso8601 "$creation") ))
    if [ -z "$tags" ] && [ -z "$digests" ]; then
        CONSIDER=1
    elif [ -n "$AGE" ] && [ "$howold" -ge "$AGE" ]; then
        CONSIDER=1
    fi

    if [ "$CONSIDER" = "1" ]; then
        if [ "$DRYRUN" = "1" ]; then
            yush_info "Would remove $2 image $(yush_yellow "$1") (from $(printf %s\\n "$digests" | sed -E -e 's/@sha256:[0-9a-f]{64}//g')), $(yush_human_period "$howold")old"
        else
            # Removing an image might fail if it is in use, this is normal.
            yush_notice "Removing $2 image $(yush_red "$1") (from $(printf %s\\n "$digests" | sed -E -e 's/@sha256:[0-9a-f]{64}//g')), $(yush_human_period "$howold")old"
            docker image rm --force "$1"
        fi
    else
        yush_debug "Keeping $2 image $(yush_green "$1"), $(yush_human_period "$howold")old"
    fi
}

to_seconds() {
    if [ -n "$1" ]; then
        if printf %s\\n "$1"|grep -Eq '[0-9]+[[:space:]]*[A-Za-z]+'; then
            NEWAGE=$(yush_howlong "$1")
            if [ -n "$NEWAGE" ]; then
                yush_debug "Converted human-readable age $1 to $NEWAGE seconds"
                printf %d\\n "$NEWAGE"
            else
                abort "Could not convert human-readable $1 to a period!"
            fi
        fi
    fi
}

# Convert human-readable periods
AGE=$(to_seconds "$AGE")
ANCIENT=$(to_seconds "$ANCIENT")

NAMES_DICTIONARY=
if [ -n "$NAMESGEN" ]; then
    yush_debug "Reading random container names database from $NAMESGEN"
    if [ -x "$(command -v curl)" ]; then
        NAMES_DICTIONARY=$(curl -qsSL -o- "$NAMESGEN"|grep -E '^\s*\"(\w+)\",'|sed -Ee 's/^\s*\"(\w+)\",/\1/g')
    elif [ -x "$(command -v wget)" ]; then
        NAMES_DICTIONARY=$(wget -q -O- "$NAMESGEN"|grep -E '^\s*\"(\w+)\",'|sed -Ee 's/^\s*\"(\w+)\",/\1/g')
    else
        yush_warn "Cannot load container name dictionary, neither curl, nor wget available"
    fi
fi

# Start by cleaning up containers so we can free as many (dependent) resources
# as possible.
if printf %s\\n "$RESOURCES" | grep -qo "container"; then
    yush_notice "Cleaning up exited, dead and ancient containers..."
    for cnr in $(docker container ls -a --filter status=exited --filter status=dead --format '{{.Names}}'); do
        rm_container "$cnr"
    done
    created=$(docker container ls -a --filter status=created --format '{{.Names}}')
    if [ -n "$created" ]; then
        # Convert yush_human_period-readable timeout, if necessary.
        if printf %s\\n "$TIMEOUT"|grep -Eq '[0-9]+[[:space:]]*[A-Za-z]+'; then
            NEWTMOUT=$(yush_howlong "$TIMEOUT")
            yush_debug "Converted human-readable timeout $TIMEOUT to $NEWTMOUT seconds"
            TIMEOUT=$NEWTMOUT
        fi
        # Wait for timeout seconds and see which containers still are in the
        # created state. Try remove logic on the ones that remained in the
        # created state for those timeout seconds.
        yush_notice "Cleaning up stale created containers (waiting for $TIMEOUT sec(s))..."
        sleep "$TIMEOUT"
        for cnr in $(docker container ls -a --filter status=created --format '{{.Names}}'); do
            if printf %s\\n "$created" | grep -qo "$cnr"; then
                rm_container "$cnr"
            else
                yush_debug "Skipping container $(yush_green "$cnr"), changed state within the past $TIMEOUT sec(s)"
            fi
        done
    fi

    if [ -n "$ANCIENT" ]; then
        now=$(date -u +'%s')
        for cnr in $(docker container ls --filter status=running --format '{{.Names}}'); do
            started=$(docker container inspect --format '{{.State.StartedAt}}' "$cnr")
            started_secs=$(yush_iso8601 "$started")
            howold=$(( now - started_secs ))
            if [ "$howold" -gt "$ANCIENT" ]; then
                yush_info "Container $cnr is $(yush_human_period "$howold")ancient"
                rm_container "$cnr"
            else
                yush_debug "Container $cnr is still young"
            fi
        done
    fi
fi

if printf %s\\n "$RESOURCES" | grep -qo "volume"; then
    yush_notice "Cleaning up dangling volumes..."
    for vol in $(docker volume ls -qf dangling=true); do
        CONSIDER=0
        if printf %s\\n "$vol" | grep -Eqo '[0-9a-f]{64}'; then
            CONSIDER=1
            yush_debug "Counting files in unnamed, dangling volume: $vol"
        else
            CONSIDER=$(consider "$vol" volume)
        fi

        if [ "$CONSIDER" = "1" ]; then
            files=$(docker run --rm -v "${vol}":/data "$BUSYBOX" find /data -type f -xdev -print | wc -l)
            if [ "$files" -le "$MAXFILES" ]; then
                if [ "$DRYRUN" = "1" ]; then
                    yush_info "Would remove dangling volume $(yush_yellow "$vol") with less than $MAXFILES file(s)"
                else
                    yush_notice "Removing dangling volume $(yush_red "$vol"), with less than $MAXFILES file(s)"
                    docker volume rm --force "${vol}"
                fi
            else
                yush_info "Keeping dangling volume $(yush_green "$vol") with $files file(s)"
            fi
        fi
    done
fi

if printf %s\\n "$RESOURCES" | grep -qo "image"; then
    yush_notice "Cleaning up dangling images..."
    for img in $(docker image ls -qf dangling=true); do
        rm_image "$img" "dangling"
    done

    yush_info "Cleaning up orphan images..."
    # Get SHA256 of image used by all existing containers. This isn't the same
    # as docker container ls -aq --format {{.Image}} as this command omits the
    # tag and tries to resolve to names. We want the SHA256 to guarantee
    # uniqueness.
    yush_info "Collecting images used by existing containers (whichever status), this may take time..."
    in_use=""
    for cnr in $(docker container ls -aq); do
        nm=$(docker container inspect --format '{{.Name}}' "$cnr")
        yush_debug "Collecting images and dependencies for container $nm ($cnr)"
        img=$(docker container inspect --format '{{.Image}}' "$cnr")
        in_use=$(printf -- "%s\n%s" "$in_use" "$img")
        for dep in $(docker image history -q --no-trunc "$img" | grep -v 'missing'); do
            [ "$img" != "$dep" ] && in_use=$(printf -- "%s\n\t%s" "$in_use" "$dep")
        done
    done
    # Try remove logic on all images that are not in use in any container.
    if [ "$INTERMEDIATE" = "0" ]; then
        images=$(docker image ls -q)
    else
        images=$(docker image ls -qa)
    fi
    for img in $images; do
        sha256=$(docker inspect --format '{{.Id}}' "$img")
        tags=$(docker inspect --format '{{.RepoTags}}' "$img")
        if printf %s\\n "$in_use" | grep -qo "$sha256"; then
            yush_debug "Keeping image $(yush_green "$img") ($tags), used by existing container"
        else
            rm_image "$img" "orphan"
        fi
    done
fi

[ -n "$RESOURCES" ] && yush_info "Done cleaning: $RESOURCES"


# Execute remaining arguments as a command, if any
if [ $# -ne "0" ]; then
    yush_info "Executing $*"
    exec "$@"
fi
