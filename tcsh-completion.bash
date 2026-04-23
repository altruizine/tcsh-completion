#!bash
#
# Copyright (C) 2017 Marc Khouzam <marc.khouzam@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# This script is to be called by the tcsh 'complete' command.
# It should be called by setting up a 'complete' command in the tcsh shell like this:
#
#  complete <toolName> 'p,*,`bash tcsh_completion.bash <completionFunction> <completionScript> "${COMMAND_LINE}"`,'
#  e.g.
#  complete git 'p,*,`bash tcsh_completion.bash __git_wrap__git_main /usr/share/bash-completion/completions/git "${COMMAND_LINE}"`,'

root_path=$(cd `dirname $0` && pwd)
common_functions="${root_path}/common-functions.bash"

# Allow for debug printouts when running the script by hand
if [ "$1" == "-d" ] || [ "$1" == "--debug" ]; then
    debug=true
    shift
fi

skipCommon=$1
completionFunction=$2
completionScript=$3
commandToComplete=$4

if [ "${debug}" == "true" ]; then
    echo =====================================
    echo $0 called towards $completionFunction from $completionScript 
    echo with command to complete: $commandToComplete
fi

if [ ${skipCommon} != "-S" -a -e ${common_functions} ]; then
	source ${common_functions}
fi
if [ -e ${completionScript} ]; then
	source ${completionScript}
fi

# Set the bash completion variables
#
COMP_LINE=${commandToComplete}
#
# TODO: set the below in case the cursor is in the middle of the line
COMP_POINT=${#COMP_LINE}
#
# TODO: Set to an integer value corresponding to the type of completion
# attempted that caused a completion function to be called:
#   9 (TAB) for normal completion,
#   63 ('?') for listing completions after successive tabs,
#   33 ('!') for listing alternatives on partial word completion,
#   64 ('@') to list completions if the word is not unmodified,
#   37 ('%') for menu completion.
COMP_TYPE=9
#
# TODO: The key (or final key of a key sequence) used to invoke the current completion function.
# Could be 9 for TAB but could also be 27 for Esc or maybe something else I didn't think of.
COMP_KEY=9
#
# Remove the colon as a completion separator because tcsh cannot handle it
COMP_WORDBREAKS=${COMP_WORDBREAKS//:}
#
# Set COMP_WORDS in a way that can be handled by the bash script.
COMP_WORDS=(${commandToComplete})

# The cursor is at the end of parameter #1.
# We must check for a space as the last character which will
# tell us that the previous word is complete and the cursor
# is on the next word.
if [ "${commandToComplete: -1}" == " " ]; then
	# The last character is a space, so our location is at the end
	# of the command-line array
	COMP_CWORD=${#COMP_WORDS[@]}
else
	# The last character is not a space, so our location is on the
	# last word of the command-line array, so we must decrement the
	# count by 1
	COMP_CWORD=$((${#COMP_WORDS[@]}-1))
fi

# Wrap compopt builtin to make it work outside of completion function.
compopt () {
    builtin compopt "$@" ${COMP_WORDS[0]}
}

# Wrap compgen builtin to attach "/" to directories
compgen () {
    if [[ ( "$*" == *'-'[f]* || "$*" == *'-A'*file* ) ]] \
	   || ( ( complete -p ${COMP_WORDS[0]} | grep -q filenames ) \
		    && [[ ( "$*" == *'-'[d]* || "$*" == *'-A'*directory* ) ]] )
    then
	local name
	builtin compgen "$@" | while read name
	do
	    if [[ -d "$name" ]]
	    then
		echo "$name/"
	    else
		echo "$name"
	    fi
	done
    else
	builtin compgen "$@"
    fi
}

# uniq_norm: collapse duplicates in a Bash array.
#   * "foo" and "foo/" are treated as the same key.
#   * If both appear, the element **with** the trailing slash is kept.
#   * Order of the result is irrelevant - the function returns the values of
#     the associative array, which are unique by definition.
# Usage: uniq_norm input_array[@] output_array
uniq_norm() {
    local -n src=$1   # source array (by name)
    local -n dst=$2   # destination array (by name)

    declare -A uniq   # key -> stored value (always the slash version if present)

    for elem in "${src[@]}"
    do
        # Canonical key: strip a single trailing slash, if any.
        local key="${elem%/}"

        # If the key is unseen, store the element.
        if [[ -z ${uniq[$key]+_} ]]
	then
            uniq[$key]="$elem"
        else
            # Key already present -> keep the slash version if the current element
            # ends with '/' and the stored one does not.
            if [[ "$elem" == */ && "${uniq[$key]}" != */ ]]
	    then
                uniq[$key]="$elem"
            fi
        fi
    done

    # Return the unique values (order is arbitrary).
    dst=("${uniq[@]}")
}

# Call the completion command in the real bash script
${completionFunction}

if [ "${debug}" == "true" ]; then
    echo =====================================
    echo $0 returned:
    echo "${COMPREPLY[@]}"
fi

IFS=$'\n'
if [ ${#COMPREPLY[*]} -eq 0 ]; then
	# No completions suggested.  In this case, we want tcsh to perform
	# standard file completion.  However, there does not seem to be way
	# to tell tcsh to do that.  To help the user, we try to simulate
	# file completion directly in this script.
	#
	# Known issues:
	#     - Possible completions are shown with their directory prefix.
	#     - Completions containing shell variables are not handled.
	#     - Completions with ~ as the first character are not handled.

	# No file completion should be done unless we are completing beyond
	# the first sub-command.
    # WARNING: This seems like a good idea for the commands I have been
    #          using, however, I may have not noticed issues with other
    #          commands.
	if [ ${COMP_CWORD} -gt 0 ]; then
		TO_COMPLETE="${COMP_WORDS[${COMP_CWORD}]}"

		# We don't support ~ expansion: too tricky.
		if [ "${TO_COMPLETE:0:1}" != "~" ]; then
			# Use ls so as to add the '/' at the end of directories.
			COMPREPLY=(`ls -dp ${TO_COMPLETE}* 2> /dev/null`)
		fi
	fi
fi

if [ "${debug}" == "true" ]; then
    echo =====================================
    echo Completions including tcsh additions:
    echo "${COMPREPLY[@]}"
    echo =====================================
    echo Final completions returned:
fi

# tcsh does not automatically remove duplicates, so we do it ourselves
uniq_norm COMPREPLY uniqed

# Prepend word prefix if not already there, or tcsh will discard the completion.
prefix=${COMP_WORDS[$COMP_CWORD]}

# Identify prefix characters that are not repeated in the completions
if [ ${#uniqed[*]} -gt 0 ]
then
    p1="" p2=$prefix c=${uniqed[0]}
    while [[ "$p2" && "$c" == "${c#$p2}" ]] # p2 doesn't match beginning of c
    do
	p1="${p1}${p2:0:1}"
	p2=${p2:1}
    done
    prefix="$p1"
fi

shopt -qs extglob
echo "${uniqed[*]/#?($prefix)/$prefix}"

# If there is a single completion and it is a directory, we output it
# a second time to trick tcsh into not adding a space after it.
if [ ${#uniqed[*]} -eq 1 ] && [ "${uniqed[0]: -1}" == "/" ]; then
    echo "${uniqed[*]/#?($prefix)/$prefix}"
fi
