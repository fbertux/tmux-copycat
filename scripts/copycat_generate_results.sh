#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$CURRENT_DIR/helpers.sh"

search_pattern="$1"

capture_pane() {
	local file=$1
	# copying 9M lines back will hopefully fetch the whole scrollback
	tmux capture-pane -S -9000000 -p > "$file"
}

# doing 2 things in 1 step so that we don't write to disk too much
reverse_and_create_copycat_file() {
	local file=$1
	local copycat_file=$2
	local grep_pattern=$3
	local file_search_key="$(get_tmux_option "@copycat_file_search" "C-f")"
	local file_search_pattern="$(get_tmux_option "@copycat_search_${file_search_key}" "")"

	if [ -n "$file_search_pattern" ] && [ "$grep_pattern" == "$file_search_pattern" ]; then
		$AWK_CMD '
			/\][$#][[:space:]]+ls([[:space:]]+.*)?$/ {
				in_ls = ($0 !~ /\^C$/)
				print
				next
			}
			/\][$#]([[:space:]]|$)/ || /^[[:space:]]*$/ {
				in_ls = 0
				print
				next
			}
			in_ls && $0 !~ /^[[:space:]]*(total[[:space:]]+[0-9]+|[0-9]*[[:space:]]*[d.lcbps-][rwxstST-]{9})/ {
				line = ""
				for (i = 1; i <= NF; i++) {
					if ($i != "." && $i != ".." && $i ~ /^[[:alnum:]_.#$%&+=@~-]+$/) {
						line = line (line ? " " : "") "\xef\x90\x90 " $i
					} else {
						line = line (line ? " " : "") $i
					}
				}
				print line
				next
			}
			{ print }
		' "$file" | (tac 2>/dev/null || tail -r) | \grep -aoniP -- "$grep_pattern" > "$copycat_file"
	else
		(tac 2>/dev/null || tail -r) < "$file" | \grep -aoniP -- "$grep_pattern" > "$copycat_file"
	fi
}

delete_old_files() {
	local scrollback_filename="$(get_scrollback_filename)"
	local copycat_filename="$(get_copycat_filename)"
	rm -f "$scrollback_filename" "$copycat_filename"
}

generate_copycat_file() {
	local grep_pattern="$1"
	local scrollback_filename="$(get_scrollback_filename)"
	local copycat_filename="$(get_copycat_filename)"
	mkdir -p "$(_get_tmp_dir)"
	chmod 0700 "$(_get_tmp_dir)"
	capture_pane "$scrollback_filename"
	reverse_and_create_copycat_file "$scrollback_filename" "$copycat_filename" "$grep_pattern"
}

if_no_results_exit_with_message() {
	local copycat_filename="$(get_copycat_filename)"
	# check for empty filename
	if ! [ -s "$copycat_filename" ]; then
		display_message "No results!"
		exit 0
	fi
}

main() {
	local grep_pattern="$1"
	if in_copycat_mode; then
		reset_copycat_position
		unset_copycat_mode
		copycat_decrease_counter
	fi
	reset_copycat_position
	delete_old_files
	generate_copycat_file "$grep_pattern"
	if_no_results_exit_with_message
	set_copycat_mode
	copycat_increase_counter
}
main "$search_pattern"
