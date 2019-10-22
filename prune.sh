#!/bin/sh

# Dynamic vars
cmdname=$(basename "${0}")
appname=${cmdname%.*}

# All (good?) defaults
VERBOSE=0
DRYRUN=0
BUSYBOX=busybox:1.31.0-musl
MAXFILES=0
NAMES=
EXCLUDE=
RESOURCES="images volumes containers"
AGE=6m
if [ -t 1 ]; then
    INTERACTIVE=1
else
    INTERACTIVE=0
fi

# Print usage on stderr and exit
usage() {
    exitcode="$1"
    cat <<USAGE >&2

Description:

  $cmdname performs some conservative Docker system pruning

Usage:
  $cmdname [-option arg --long-option(=)arg]

  where all dash-led options are as follows (long options can be followed by
  an equal sign):
    -v | --verbose   Be more verbose
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
                     6m). The age can be expressed in human-readable format, e.g.
                     6m (== 6 months), 3 days, etc.
    --busybox        Docker busybox image tag to be used for volume content
                     collection.

USAGE
    exit "$exitcode"
}

while [ $# -gt 0 ]; do
    case "$1" in
    -v | --verbose)
        VERBOSE=1; shift 1;;

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

    --busybox)
        BUSYBOX="$2"; shift 2;;
    --busybox=*)
        BUSYBOX="${1#*=}"; shift 1;;

    --dry-run | --dryrun)
        DRYRUN=1; shift 1;;

    -h | --help)
        usage 1; exit;;

    --)
        shift; break;;

    -*)
        usage 1; exit;;

    *)
        break
        ;;
    esac
done

green() {
    if [ $INTERACTIVE = "1" ]; then
        printf '\033[1;31;32m%b\033[0m' "$1"
    else
        printf -- "%b" "$1"
    fi
}

red() {
    if [ $INTERACTIVE = "1" ]; then
        printf '\033[1;31;40m%b\033[0m' "$1"
    else
        printf -- "%b" "$1"
    fi
}

yellow() {
    if [ $INTERACTIVE = "1" ]; then
        printf '\033[1;31;33m%b\033[0m' "$1"
    else
        printf -- "%b" "$1"
    fi
}

blue() {
    if [ $INTERACTIVE = "1" ]; then
        printf '\033[1;31;34m%b\033[0m' "$1"
    else
        printf -- "%b" "$1"
    fi
}

# Conditional logging
verbose() {
    if [ "$VERBOSE" = "1" ]; then
        echo "[$(blue "$appname")] [$(yellow info)] [$(date +'%Y%m%d-%H%M%S')] $1"
    fi
}

warn() {
    echo "[$(blue "$appname")] [$(red WARN)] [$(date +'%Y%m%d-%H%M%S')] $1"
}

abort() {
    warn "$1"
    exit 1
}


howlong() {
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[yY]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[yY].*/\1/p')
        expr "$len" \* 31536000
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Mm][Oo]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Mm][Oo].*/\1/p')
        expr "$len" \* 2592000
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*m'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*m.*/\1/p')
        expr "$len" \* 2592000
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Ww]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Ww].*/\1/p')
        expr "$len" \* 604800
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Dd]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Dd].*/\1/p')
        expr "$len" \* 86400
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Hh]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Hh].*/\1/p')
        expr "$len" \* 3600
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Mm][Ii]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Mm][Ii].*/\1/p')
        expr "$len" \* 60
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*M'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*M.*/\1/p')
        expr "$len" \* 60
        return
    fi
    if echo "$1"|grep -Eqo '[0-9]+[[:space:]]*[Ss]'; then
        len=$(echo "$1"  | sed -En 's/([0-9]+)[[:space:]]*[Ss].*/\1/p')
        echo "$len"
        return
    fi
    if echo "$1"|grep -E '[0-9]+'; then
        echo "$1"
        return
    fi
}

human(){
    t=$1

    d=$((t/60/60/24))
    h=$((t/60/60%24))
    m=$((t/60%60))
    s=$((t%60))

    if [ $d -gt 0 ]; then
            [ $d = 1 ] && printf "%d day " $d || printf "%d days " $d
    fi
    if [ $h -gt 0 ]; then
            [ $h = 1 ] && printf "%d hour " $h || printf "%d hours " $h
    fi
    if [ $m -gt 0 ]; then
            [ $m = 1 ] && printf "%d minute " $m || printf "%d minutes " $m
    fi
    if [ $d = 0 ] && [ $h = 0 ] && [ $m = 0 ]; then
            [ $s = 1 ] && printf "%d second" $s || printf "%d seconds" $s
    fi
    printf '\n'
}

# Returns the number of seconds since the epoch for the ISO8601 date passed as
# an argument. This will only recognise a subset of the standard, i.e. dates
# with milliseconds, microseconds or none specified, and timezone only specified
# as diffs from UTC, e.g. 2019-09-09T08:40:39.505-07:00 or
# 2019-09-09T08:40:39.505214+00:00. The implementation actually computes the
# ms/us whenever they are available, but discards them.
iso8601() {
    # Arrange for ns to be the number of nanoseconds.
    ds=$(echo "$1"|sed -E 's/([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.([0-9]{3,9}))?([+-]([0-9]{2}):([0-9]{2})|Z)?/\8/')
    ns=0
    if [ -n "$ds" ]; then
        if [ "${#ds}" = "10" ]; then
            ds=$(echo "$ds" | sed 's/^0*//')
            ns=$ds
        elif [ "${#ds}" = "7" ]; then
            ds=$(echo "$ds" | sed 's/^0*//')
            ns=$((1000*ds))
        else
            ds=$(echo "$ds" | sed 's/^0*//')
            ns=$((1000000*ds))
        fi
    fi


    # Arrange for tzdiff to be the number of seconds for the timezone.
    tz=$(echo "$1"|sed -E 's/([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.([0-9]{3,9}))?([+-]([0-9]{2}):([0-9]{2})|Z)?/\9/')
    tzdiff=0
    if [ -n "$tz" ]; then
        if [ "$tz" = "Z" ]; then
            tzdiff=0
        else
            hrs=$(printf "%d" "$(echo "$tz" | sed -E 's/[+-]([0-9]{2}):([0-9]{2})/\1/')")
            mns=$(printf "%d" "$(echo "$tz" | sed -E 's/[+-]([0-9]{2}):([0-9]{2})/\2/')")
            sign=$(echo "$tz" | sed -E 's/([+-])([0-9]{2}):([0-9]{2})/\1/')
            secs=$((hrs*3600+mns*60))
            if [ "$sign" = "-" ]; then
                tzdiff=$((-secs))
            else
                tzdiff=$secs
            fi
        fi
    fi

    # Extract UTC date and time into something that date can understand, then
    # add the number of seconds representing the timezone.
    utc=$(echo "$1"|sed -E 's/([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.([0-9]{3,9}))?([+-]([0-9]{2}):([0-9]{2})|Z)?/\1-\2-\3 \4:\5:\6/')
    if [ "$(uname -s)" = "Darwin" ]; then
        secs=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$utc" +"%s")
    else
        secs=$(date -u -d "$utc" +"%s")
    fi
    expr "$secs" + \( "$tzdiff" \)
}

# Convert period
if echo "$AGE"|grep -Eq '[0-9]+[[:space:]]*[A-Za-z]+'; then
    NEWAGE=$(howlong "$AGE")
    verbose "Converting human-readable age $AGE to $NEWAGE seconds"
    AGE=$NEWAGE
fi

if echo "$RESOURCES" | grep -qo "container"; then
    verbose "Cleaning up exited containers..."
    for cnr in $(docker container ls --filter status=exited --format '{{.Names}}'); do
        CONSIDER=0
        if [ -n "$NAMES" ] && echo "$cnr"|grep -Eqo "$NAMES"; then
            if [ -z "$EXCLUDE" ]; then
                verbose "  Considering exited container $cnr for removal, matching $NAMES"
                CONSIDER=1
            elif [ -n "$EXCLUDE" ] && echo "$cnr"|grep -Eqov "$EXCLUDE"; then
                verbose "  Considering exited container $cnr for removal, matching $NAMES but not $EXCLUDE"
                CONSIDER=1
            else
                verbose "  Skipping removal of container $(green "$cnr"), matching $NAMES but also matching $EXCLUDE"
            fi

            if [ "$CONSIDER" = "1" ]; then
                if [ "$DRYRUN" = "1" ]; then
                    verbose "  Would remove container $(yellow "$cnr")"
                else
                    verbose "  Removing exited container $(red "$cnr")"
                    docker image rm -f "${img}"
                fi
            else
                verbose "  Keeping container $(green "$cnr")"
            fi
        fi
    done
fi

if echo "$RESOURCES" | grep -qo "volume"; then
    verbose "Cleaning up dangling volumes..."
    for vol in $(docker volume ls -qf dangling=true); do
        CONSIDER=0
        if echo "$vol" | grep -Eqo '[0-9a-f]{64}'; then
            CONSIDER=1
            verbose "  Counting files in unnamed, dangling volume: $vol"
        elif [ -n "$NAMES" ] && echo "$vol"|grep -Eqo "$NAMES"; then
            if [ -z "$EXCLUDE" ]; then
                verbose "  Counting files in dangling volume: $vol, matching $NAMES"
                CONSIDER=1
            elif [ -n "$EXCLUDE" ] && echo "$vol"|grep -Eqov "$EXCLUDE"; then
                verbose "  Counting files in dangling volume: $vol, matching $NAMES but not $EXCLUDE"
                CONSIDER=1
            else
                verbose "  Skipping dangling volume: $(green "$vol"), matching $NAMES but also matching $EXCLUDE"
            fi
        fi

        if [ "$CONSIDER" = "1" ]; then
            files=$(docker run --rm -v "${vol}":/data "$BUSYBOX" find /data -type f -xdev -print | wc -l)
            if [ "$files" -le "$MAXFILES" ]; then
                if [ "$DRYRUN" = "1" ]; then
                    verbose "  Would remove dangling volume $(yellow "$vol") with less than $MAXFILES file(s)"
                else
                    verbose "  Removing dangling volume $(red "$vol"), with less than $MAXFILES file(s)"
                    docker volume rm -f "${vol}"
                fi
            else
                verbose "  Keeping dangling volume $(green "$vol") with $files file(s)"
            fi
        fi
    done
fi

if echo "$RESOURCES" | grep -qo "image"; then
    verbose "Cleaning up dangling images..."
    now=$(date -u +'%s')
    for img in $(docker image ls -qf dangling=true); do
        tags=$(docker image inspect --format '{{.RepoTags}}' "$img"|sed -e 's/^\[//' -e 's/\]$//')
        digests=$(docker image inspect --format '{{.RepoDigests}}' "$img"|sed -e 's/^\[//' -e 's/\]$//')

        CONSIDER=0
        creation=$(docker image inspect --format '{{.Created}}' "$img")
        howold=$((now-$(iso8601 "$creation")))
        if [ -z "$tags" ] && [ -z "$digests" ]; then
            CONSIDER=1
        elif [ "$howold" -ge "$AGE" ]; then
            CONSIDER=1
        fi

        if [ "$CONSIDER" = "1" ]; then
            if [ "$DRYRUN" = "1" ]; then
                verbose "  Would remove dangling image $(yellow "$img") (from $(echo "$digests" | sed -E -e 's/@sha256:[0-9a-f]{64}//g')), $(human "$howold")old"
            else
                verbose "  Removing dangling image $(red "$img") (from $(echo "$digests" | sed -E -e 's/@sha256:[0-9a-f]{64}//g')), $(human "$howold")old"
                docker image rm -f "${img}"
            fi
        else
            verbose "  Keeping dangling image $(green "$img"), $(human "$howold")old"
        fi
    done
fi
