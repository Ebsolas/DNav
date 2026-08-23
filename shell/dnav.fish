# Fish hook. `source` this file. Spawns zsh -f only when a command runs.
#   set -gx DNAV_DIR /path/to/dnav
#   source $DNAV_DIR/shell/dnav.fish

if set -q _DNAV_HOOKED
    # already loaded
else
set -g _DNAV_HOOKED 1
if not set -q DNAV_DIR
    if set -q XDG_DATA_HOME
        set -gx DNAV_DIR "$XDG_DATA_HOME/dnav"
    else
        set -gx DNAV_DIR "$HOME/.local/share/dnav"
    end
end
set -g _DNAV_BOUND_KEYS

function _dnav_jumps_file
    if set -q DNAV_JUMPS; and test -f "$DNAV_JUMPS"
        echo $DNAV_JUMPS
    else if test -f "$HOME/.config/dnav/jumps"
        echo "$HOME/.config/dnav/jumps"
    else if test -f "$DNAV_DIR/jumps"
        echo "$DNAV_DIR/jumps"
    end
end

function _dnav_cmd
    if not command -q zsh
        echo "dnav: zsh not found" >&2
        return 127
    end
    if not test -f "$DNAV_DIR/dnav"
        echo "dnav: missing $DNAV_DIR/dnav" >&2
        return 1
    end
    set -l rf (mktemp 2>/dev/null; or mktemp -t dnav)
    set -l st 0
    set -gx DNAV_RESULT_FILE $rf
    if test -t 0; and test -t 1; and test -e /dev/tty
        zsh -f -c 'source -- "$1/dnav" || exit 1; cmd=$2; shift 2; "$cmd" "$@"' dnav $DNAV_DIR $argv </dev/tty >/dev/tty
        or set st $status
    else
        zsh -f -c 'source -- "$1/dnav" || exit 1; cmd=$2; shift 2; "$cmd" "$@"' dnav $DNAV_DIR $argv
        or set st $status
    end
    set -e DNAV_RESULT_FILE
    set -l dest
    if test -s $rf
        set dest (cat $rf)
    end
    rm -f $rf
    if test -n "$dest"
        cd -- $dest
        or return
    end
    return $st
end

function dnav; _dnav_cmd dnav $argv; end
function dconfig; _dnav_cmd dconfig $argv; end
function dhelp; _dnav_cmd dhelp $argv; end

function djump
    _dnav_cmd djump $argv
    set -l st $status
    switch $argv[1]
        case add edit remove rm delete del -r --reload
            _dnav_bind_jumps
    end
    return $st
end

function _dnav_bind_jumps
    for k in $_DNAV_BOUND_KEYS
        functions -e d$k
    end
    set -g _DNAV_BOUND_KEYS
    set -l f (_dnav_jumps_file)
    test -n "$f"; and test -f $f; or return 0
    while read -l line
        set line (string trim -- $line)
        test -z "$line"; and continue
        string match -q '#*' -- $line; and continue
        set -l key (string split -n -f1 ' ' -- $line)
        string match -qr '^[A-Za-z_][A-Za-z0-9_]*$' -- $key; or continue
        contains -- d$key dnav djump dconfig dhelp; and continue
        eval "function d$key; _dnav_cmd djump $key; end"
        set -a _DNAV_BOUND_KEYS $key
    end < $f
end

_dnav_bind_jumps
end
