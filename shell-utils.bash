# shell-utils.bash
#
# An integrated collection of utilites for shell scripting.
# The .bash version uses $"..." for translation and one other bashism in cmd().

umount_all() {
    local dev=$1  mounted

    mounted=$(mount | egrep "^$dev[^ ]*" | cut -d" " -f3 | grep .) || return 0

    # fatal "One or more partitions on device %s are mounted at: %s"
    # This makes it easier on the translators (and my validation)
    local msg=$"One or more partitions on device %s are mounted at"
    force umount || yes_NO_fatal "umount" \
        $"Do you want those partitions unmounted?" \
        "$(printf $"Use %s to always have us unmount mounted target partitions" "$(pq "--force=umount")" )" \
        "$msg:\n  %s" "$dev" "$(echo $mounted)"

    local i part
    for part in $(mount | egrep -o "^$dev[^ ]*"); do
        umount --all-targets $part 2>/dev/null
    done

    mount | egrep -q "^$dev[^ ]*" || return 0

    for i in $(seq 1 10); do
        mount | egrep -q "^$dev[^ ]*" || return 0
        for part in $(mount | egrep -o "^$dev[^ ]*"); do
            umount $part 2>/dev/null
        done
        sleep .1
    done

    # Make translation and validation easier
    msg=$"One or more partitions on device %s are in use at"
    mounted=$(mount | egrep "^$dev[^ ]*" | cut -d" " -f3 | grep .) || return 0
    fatal "$msg:\n  %s"  "$dev" "$(echo $mounted)"
    return 1
}

my_mount() {
    local dev=$1  dir=$2
    is_mountpoint $dir           && fatal $"Directory '%s' is already a mountpoint" "$dir"
    PRETEND= cmd mkdir -p $dir   || fatal $"Failed to create directory '%s'" "$dir"
    PRETEND= cmd mount $dev $dir || fatal $"Could not mount %s at %s" "$dev" "$dir"
    is_mountpoint $dir           || fatal $"Failed to mount %s at %s" "$dev" "$dir"
}

need() {
    local cmd=$1  cmd2=${1%%-*}
    echo "$CMDS" | egrep -q "(^| )($cmd|$cmd2|all)( |$)" || return 1
    Msg "=> $cmd"
    return 0
}

force() {
    local this=$1  option_list=${2:-$FORCE}
    case ,$option_list, in
        *,$this,*|*,all,*) return 0 ;;
    esac
    return 1
}

check_force() {
    local cmds=$1  all=$2  force_opt
    for force_opt in ${cmds//,/ }; do
        force $force_opt "$all" || fatal $"Unknown force option: %s" "$force_opt"
    done
}


# Test for valid commands and process cmd+ commands
# Allow a trailing "+" if ordered is given and use that to add all commands
# after the given one
check_cmds() {
    local cmds_nam=$1  all=" $2 "  ordered=$3 cmds_in cmds_out

    eval "local cmds_in=\$$cmds_nam"

    local cmd plus_cnt=0 plus
    [ "$ordered" ] && plus="+"

    for cmd in $cmds_in; do

        case $all in
            *" ${cmd%$plus} "*) ;;
            *) fatal $"Unknown command: %s" $cmd ;;
        esac

        [ -z "${cmd%%*+}" ] || continue

        cmd=${cmd%+}
        cmds_out="$cmds_out $(echo "$ORDERED_CMDS" | sed -rn "s/.*($cmd )/\1/p")"
        plus_cnt=$((plus_cnt + 1))
        [ $plus_cnt -gt 1 ] && fatal $"Only one + command allowed"
    done

    [ ${#cmds_out} -gt 0 ] && eval "$cmds_nam=\"$cmds_in \$cmds_out\""
}

write_file() {
    file=$1
    shift
    echo "$*" > $file
}

is_usb_or_removeable() {
    test -b $1 || return 1
    local drive=$(get_drive $1)
    local dir=/sys/block/$drive flag
    read flag 2>/dev/null < $dir/removable
    [ "$flag" = 1 ] && return 0
    local devpath=$(readlink -f $dir/device)
    [ "$devpath" ] || return 1
    echo $devpath | grep -q /usb
    return $?
}

do_flock() {
    file=$1  me=$2

    if which flock &> /dev/null; then
        exec 18> $file
        flock -n 18 || fatal 101 $"A %s process is running.  If you think this is an error, remove %s" "$me" "$file"
        echo $$ >&18
        return
    fi

    force flock && return

    yes_NO_fatal "flock" \
        $"Do you want to continue without locking?" \
        "$(printf $"Use %s to always ignore this warning" "$(pq "--force=flock")" )" \
        $"The %s program was not found." "flock"
}

get_drive() {
    local drive part=${1##*/}
    case $part in
        mmcblk*) echo ${part%p[0-9]}                       ;;
              *) drive=${part%[0-9]} ; echo ${drive%[0-9]} ;;
    esac
}

expand_device() {
    case $1 in
        /dev/*)  [ -b "$1"      ] && echo "$1"      ;;
         dev/*)  [ -b "/$1"     ] && echo "/$1"     ;;
            /*)  [ -b "/dev$1"  ] && echo "/dev$1"  ;;
             *)  [ -b "/dev/$1" ] && echo "/dev/$1" ;;
    esac
}

get_partition() {
    local dev=$1  num=$2

    case $dev in
        *mmcbk*) echo  ${dev}p$num  ;;
              *) echo  ${dev}$num   ;;
    esac
}

read_early_params() {
    local arg SHIFT

    while [ $# -gt 0 ]; do
        arg=$1
        shift
        [ ${#arg} -gt 0 -a -z "${arg##-*}" ] || continue
        arg=${arg#-}
        # Expand stacked single-char arguments
        case $arg in
            [$SHORT_STACK][$SHORT_STACK]*)
                if echo "$arg" | grep -q "^[$SHORT_STACK]\+$"; then
                    local old_cnt=$#
                    set -- $(echo $arg | sed -r 's/([a-zA-Z])/ -\1 /g') "$@"
                    SHIFT=$((SHIFT - $# + old_cnt))
                    continue
                fi;;
        esac
        takes_param "$arg" && shift
        eval_early_argument "$arg"
    done
}

read_all_cmdline_mingled() {

    : ${PARAM_CNT:=0}

    while [ $# -gt 0 ]; do
        read_params "$@"
        shift $SHIFT
        while [ $# -gt 0 -a ${#1} -gt 0 -a -n "${1##-*}" ]; do
            PARAM_CNT=$((PARAM_CNT + 1))
            assign_parameter $PARAM_CNT "$1"
            shift
        done
    done
}

#-------------------------------------------------------------------------------
# Send "$@".  Expects
#
#   SHORT_STACK               variable, list of single chars that stack
#   fatal(msg)                routine,  fatal([errnum] [errlabel] "error message")
#   takes_param(arg)          routine,  true if arg takes a value
#   eval_argument(arg, [val]) routine,  do whatever you want with $arg and $val
#
# Sets "global" variable SHIFT to the number of arguments that have been read.
#-------------------------------------------------------------------------------
read_params() {
    # Most of this code is boiler-plate for parsing cmdline args
    SHIFT=0
    # These are the single-char options that can stack

    local arg val

    # Loop through the cmdline args
    while [ $# -gt 0 -a ${#1} -gt 0 -a -z "${1##-*}" ]; do
        arg=${1#-}
        shift
        SHIFT=$((SHIFT + 1))

        # Expand stacked single-char arguments
        case $arg in
            [$SHORT_STACK][$SHORT_STACK]*)
                if echo "$arg" | grep -q "^[$SHORT_STACK]\+$"; then
                    local old_cnt=$#
                    set -- $(echo $arg | sed -r 's/([a-zA-Z])/ -\1 /g') "$@"
                    SHIFT=$((SHIFT - $# + old_cnt))
                    continue
                fi;;
        esac

        # Deal with all options that take a parameter
        if takes_param "$arg"; then
            [ $# -lt 1 ] && fatal $"Expected a parameter after: %s" "-$arg"
            val=$1
            [ -n "$val" -a -z "${val##-*}" ] \
                && fatal $"Suspicious argument after %s: %s" "-$arg" "$val"
            SHIFT=$((SHIFT + 1))
            shift
        else
            case $arg in
                *=*)  val=${arg#*=} ;;
                  *)  val="???"     ;;
            esac
        fi

        eval_argument "$arg" "$val"
    done
}

cmd() {
    echo " > $*" >> $LOG_FILE
    [ "$BE_VERBOSE" ] && echo " >" "$@" | sed "s|$WORK_DIR|.|g"
    [ "$PRETEND"    ] && return 0
    "$@" 2>&1 | tee -a $LOG_FILE
    # Warning: Bashism
    return ${PIPESTATUS[0]}
}

my_mkdir() {
    dir=$1
    mkdir -p "$dir" || fatal $"Could not make directory '%s'" "$dir"
}

du_size() {
    du --apparent-size -scm "$@" 2>/dev/null | tail -n 1 | cut -f1
}

set_colors() {
    local noco=$1  loco=$2

    local e=$(printf "\e")
     black="$e[0;30m";    blue="$e[0;34m";    green="$e[0;32m";    cyan="$e[0;36m";
       red="$e[0;31m";  purple="$e[0;35m";    brown="$e[0;33m"; lt_gray="$e[0;37m";
   dk_gray="$e[1;30m"; lt_blue="$e[1;34m"; lt_green="$e[1;32m"; lt_cyan="$e[1;36m";
    lt_red="$e[1;31m"; magenta="$e[1;35m";   yellow="$e[1;33m";   white="$e[1;37m";
     nc_co="$e[0m";

    cheat_co=$white;      err_co=$red;       hi_co=$white;   quest_co=$green;
      cmd_co=$white;     from_co=$lt_green;  mp_co=$magenta;   num_co=$magenta;
      dev_co=$magenta;   head_co=$yellow;     m_co=$lt_cyan;    ok_co=$lt_green;
       to_co=$lt_green;  warn_co=$yellow;  bold_co=$yellow;
}

pq()  { echo "$hi_co$*$m_co"           ;}
pqw() { echo "$warn_co$*$hi_co"        ;}
pqe() { echo "$hi_co$*$err_co"         ;}
pqh() { echo "$m_co$*$hi_co"           ;}
bq()  { echo "$yellow$*$m_co"          ;}
cq()  { echo "$cheat_co$*$m_co"        ;}

# The order is weird but it allows the *error* message to work like printf
# The purpose is to make it easy to put questions into the error log.
yes_NO_fatal() {
    local code=$1  question=$2  continuation=$3  fmt=$4
    shift 4
    local msg=$(printf "$fmt" "$@")

    if [ "$AUTO_MODE" ]; then
        FATAL_QUESTION=$question
        fatal "$code" "$fmt" "$@"
    fi
    warn "$fmt" "$@"
    [ ${#continuation} -gt 0 ] && question="$question\n($m_co$continuation$quest_co)"
    yes_NO "$question" && return 0
    fatal "$code" "$fmt" "$@"
}

yes_NO() { _yes_no 0 "$1" ;}
YES_no() { _yes_no 0 "$1" ;}

_yes_no() {
    local answer default=$1  question=$2

    [ "$AUTO_MODE" ] && return $default
    local yes=$"yes"  no=$"no"  quit=$"quit"  default=$"default"
    local menu def_entry
    case default in
        0) menu=$(printf "  1) $yes ($default)\n  2) $no\n  0) $quit") ; def_entry=1;;
        *) menu=$(printf "  1) $yes\n  2) $no (default)\n  0) $quit")  ; def_entry=2;;
    esac
    local data=$(printf "1:1\n2:2\n0:0")
    my_select_2 "$quest_co$question$nc_co" answer $def_entry "$data" "$menu"
    case $answer in
        1) return 0 ;;
        2) return 1 ;;
        0) exit 0   ;;
        *) fatal "Should never get here 111" ;;
    esac
}

my_select() {
    local title=$1  var=$2  width=${3:-0}  default=$4
    shift 4

    local data menu lab cnt=0 dcnt
    for lab; do
        cnt=$((cnt+1))
        dcnt=$cnt

        [ "$lab" = "quit" ] && dcnt=0
        data="${data}$dcnt:$lab\n"

        [ "$lab" = "quit" ] && lab=$bold_co$lab$nc_co
        [ $cnt = "$default" ] && lab=$(printf "%${width}s (%s)" "$lab" "$(cq "default")")
        menu="${menu}$(printf "$quest_co%2d$white)$cyan %${width}s" $dcnt "$lab")\n"
    done

    my_select_2 "$title" $var "$default" "$data" "$menu"
}

my_select_2() {
    local title=$1  var=$2  default=$3  data=$4  menu=$5
    local def_prompt=$(printf "Press <%s> for the default selection" "$(cq "enter")")

    local val input err_msg
    while [ -z "$val" ]; do

        echo -e "$hi_co$title$nc_co"

        printf "$menu\n" | colorize_menu
        [ "$err_msg" ] && printf "$err_co%s$nc_co\n" "$err_msg"
        [ "$default" ] && printf "$m_co%s$nc_co\n" "$def_prompt"
        echo -n "$green>$nc_co "

        read input
        err_msg=
        [ -z "$input" -a -n "$default" ] && input=$default

        if ! echo "$input" | grep -q "^[0-9]\+$"; then
            err_msg="You must enter a number"
            [ "$default" ] && err_msg="You must enter a number or press <enter>"
            continue
        fi

        val=$(echo -e "$data" | sed -n "s/^$input://p" | cut -d: -f1)

        if [ -z "$val" ]; then
            err_msg=$(printf "The number <%s> is out of range" "$(pqe $input)")
            continue
        fi

        eval $var=\$val
        break
    done
}

colorize_menu() {
    sed -r -e "s/(^| )([0-9]+)\)/\1$green\2$white)$cyan/g" -e "s/\(([^)]+)\)/($white\1$cyan)/g" -e "s/$/$nc_co/"
}

rpad() {
    local width=$1  str=$2
    local pad=$((width - $(echo $str | wc -m)))
    [ $pad -le 0 ] && pad=0
    printf "%s%${pad}s" "$str" ""
}

lpad() {
    local width=$1  str=$2
    local pad=$((width - $(echo $str | wc -m)))
    [ $pad -le 0 ] && pad=0
    printf "%${pad}s%s" "" "$str"
}

show_elapsed() {
    local dt=$(($(date +%s) - START_T))
    [ $dt -gt 10 ] && msg "\n$ME took $(elapsed $START_T)."
    echo >> $LOG_FILE
}

elapsed() {
    local sec min hour ans

    sec=$((-$1 + $(date +%s)))

    if [ $sec -lt 60 ]; then
        plural $sec "%n second%s"
        return
    fi

    min=$((sec / 60))
    sec=$((sec - 60 * min))
    if [ $min -lt 60 ]; then
        ans=$(plural $min "%n minute%s")
        [ $sec -gt 0 ] && ans="$ans and $(plural $sec "%n second%s")"
        echo -n "$ans"
        return
    fi

    hour=$((min / 60))
    min=$((min - 60 * hour))

    plural $hour "%n hour%s"
    if [ $min -gt 0 ]; then
        local min_str=$(plural $min "%n minute%s")
        if [ $sec -gt 0 ]; then
            echo -n ", $min_str,"
        else
            echo -n " and $min_str"
        fi
    fi
    [ $sec -gt 0 ] && plural $sec " and %n second%s"
}

plural() {
    local n=$1 str=$2
    case $n in
        1) local s=  ies=y   are=is   were=was  es= num=one;;
        *) local s=s ies=ies are=are  were=were es=es num=$n;;
    esac
    case $n in
        0) num=no
    esac
    echo -n "$str" | sed -e "s/%s\>/$s/g" -e "s/%ies\>/$ies/g" \
        -e "s/%are\>/$are/g" -e "s/%n\>/$num/g" -e "s/%were\>/$were/g" \
        -e "s/%es\>/$es/g" -e "s/%3d\>/$(printf "%3d" $n)/g"
}

Msg() {
    local fmt=$1
    shift
    printf "$fmt\n" "$@" | strip_color >> $LOG_FILE
    printf "$m_co$fmt$nc_co\n" "$@"
}

msg() {
    local fmt=$1
    shift
    printf "$fmt\n" "$@" | strip_color >> $LOG_FILE
    [ -z "$QUIET" ] && printf "$m_co$fmt$nc_co\n" "$@"
}

fatal() {
    local code

    if echo "$1" | grep -q "^[0-9]\+$"; then
        EXIT_NUM=$1
        shift
    fi

    if echo "$1" | grep -q "^[a-z-]*$"; then
        code=$1
        shift
    fi

    local fmt=$1
    shift
    printf "${err_co}Fatal error:$hi_co $fmt$nc_co\n" "$@" >&2
    printf "Fatal error: $fmt\n" "$@" | strip_color >> $LOG_FILE
    fmt=$(echo "$fmt" | sed 's/\\n/ /g')
    printf "$code:$fmt\n" "$@"        | strip_color >> $ERR_FILE
    [ -n "$FATAL_QUESTION" ] && echo "Q:$FATAL_QUESTION" >> $ERR_FILE
    my_exit ${EXIT_NUM:-100}
}

strip_color() {
    local e=$(printf "\e")
    sed -r -e "s/$e\[[0-9;]+[mK]//g"
}

warn() {
    local fmt=$1
    shift
    printf "${warn_co}Warning:$hi_co $fmt$nc_co\n" "$@" >&2
    printf "${warn_co}Warning:$hi_co $fmt$nc_co\n" "$@" | strip_color >> $LOG_FILE
}

reset_conf() {
    local temp_file=$(mktemp /tmp/$ME-config-XXXXXX) || fatal $"Could not make a temporary file under %s" "/tmp"
    sed -rn "/^#=+\s*BEGIN_CONFIG/,/^#=+\s*END_CONFIG/p" "$ME" > $temp_file
    source $temp_file
    rm -f $temp_file || fatal $"Could not remove temporary file %s" "$temp_file"
}

is_mountpoint() {
    local file=$1
    cut -d" " -f2 /proc/mounts | grep -q "^$(readlink -f $file)$"
    return $?
}

require() {
    local stage=$1  prog ret=0
    shift;
    for prog; do
        which $prog &>/dev/null && continue
        warn $"Could not find program %s.  Skipping %s." "$(pqh $prog)" "$(pqh $stage)"
        ret=2
    done
    return $ret
}

need_prog() {
    local prog
    for prog; do
        which $prog &>/dev/null && continue
        fatal "Could not find required program '%s'" "$(pqh $prog)"
    done
}

is_writable() {
    local dir=$1
    test -d "$dir" || fatal "Directory %s does not exist" "$dir"
    local temp=$(mktemp -p $dir 2> /dev/null) || return 1
    rm -f "$temp"
    return 0
}
