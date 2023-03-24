#!/usr/bin/env bash

# This containers common functions for shell scripts. Its
# meant to be source included into another script.

## HELPER FUNCS

# Send a green message to stdout, followed by a new line
say() {
	[ -t 1 ] && [ -n "$TERM" ] &&
		echo "$(tput setaf 2)[$MY_NAME]$(tput sgr0) $*" ||
		echo "[$MY_NAME] $*"
}

# Send a green message to stdout, without a trailing new line
say_noln() {
	[ -t 1 ] && [ -n "$TERM" ] &&
		echo -n "$(tput setaf 2)[$MY_NAME]$(tput sgr0) $*" ||
		echo "[$MY_NAME] $*"
}

# Send a red message to stdout, followed by a new line
say_err() {
	[ -t 2 ] && [ -n "$TERM" ] &&
		echo -e "$(tput setaf 1)[$MY_NAME] $*$(tput sgr0)" 1>&2 ||
		echo -e "[$MY_NAME] $*" 1>&2
}

# Send a yellow message to stdout, followed by a new line
say_warn() {
	[ -t 1 ] && [ -n "$TERM" ] &&
		echo "$(tput setaf 3)[$MY_NAME] $*$(tput sgr0)" ||
		echo "[$MY_NAME] $*"
}

# Send a yellow message to stdout, without a trailing new line
say_warn_noln() {
	[ -t 1 ] && [ -n "$TERM" ] &&
		echo -n "$(tput setaf 3)[$MY_NAME] $*$(tput sgr0)" ||
		echo "[$MY_NAME] $*"
}

# Exit with an error message and (optional) code
# Usage: die [-c <error code>] <error message>
die() {
	code=1
	[[ "$1" = "-c" ]] && {
		code="$2"
		shift 2
	}
	say_err "$@"
	exit "$code"
}

# Exit with an error message if the last exit code is not 0
ok_or_die() {
	code=$?
	[[ $code -eq 0 ]] || die -c $code "$@"
}

## MAIN
main() {
    if [ $# = 0 ]; then
    die "No command provided. Please use \`$0 help\` for help."
    fi

    # Parse main command line args.
    while [ $# -gt 0 ]; do
        case "$1" in
            -h | --help)
                cmd_help
                exit 1
                ;;
            -*)
                die "Unknown arg: $1. Please use \`$0 help\` for help."
			;;
            *)
                break
            ;;
        esac
        shift
    done

    # $1 is now a command name. Check if it is a valid command and, if so,
    # run it.
    #
    declare -f "cmd_$1" >/dev/null
    ok_or_die "Unknown command: $1. Please use \`$0 help\` for help."

    cmd=cmd_$1
    shift

    # $@ is now a list of command-specific args
    #
    $cmd "$@"
}