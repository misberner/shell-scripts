#!/bin/bash
#
# setup-gitignore.sh -- Automatically set up .gitignore files
#
# Copyright (c) 2014 by Malte Isberner (https://github.com/misberner).
# 
# Licensed under the MIT License. For details, see the accompanying
# LICENSE file.

declare -a GITIGNORE_ROOTS=(
	'https://raw.github.com/misberner/gitignore/master/'
	'https://raw.github.com/github/gitignore/master/'
	'https://raw.github.com/github/gitignore/master/Global/'
	)

eecho() {
	echo >&2 "$@"
}

die() {
	eecho "$@"
	exit 1
}

GIT="`which git`"
WGET="`which wget`"

GITIGNORE_AUTO_ADD="yes"
GITIGNORE_AUTO_COMMIT="no"
GITIGNORE_AUTO_PUSH="no"


TARGET="./.gitignore"

[ $# -eq 0 ] && die "Usage: $0 <style1> [...<stylen>]"

[ -x "$GIT" ] || die  "Could not determine git executable"
[ -x "$WGET" ] || die "Could not determine wget executable"

[ ! -f "$TARGET" ] || die ".gitignore file already exists"



declare -a STYLES=("$@")

declare -a TEMPFILES

for style in "${STYLES[@]}"; do
	FILENAME="$style.gitignore"
	SUCCESS=0
	for root in "${GITIGNORE_ROOTS[@]}"; do
		TEMPFILE="`mktemp`"
		wget "$root/$FILENAME" -q -O "$TEMPFILE"
		if [ $? -eq 0 ]; then
			echo "Successfully retrieved $FILENAME from $root"
			TEMPFILES+=("$TEMPFILE")
			SUCCESS=1
			break
		else
			rm "$TEMPFILE"
		fi
	done

	if [ "$SUCCESS" -eq 0 ]; then
		[ "${#TEMPFILES}" -gt 0 ] && rm "${TEMPFILES[@]}"
		die "Failed to retrieve $FILENAME"
	fi
done


cat "${TEMPFILES[@]}" | uniq >"$TARGET"
rm "${TEMPFILES[@]}"

if [ "$GITIGNORE_AUTO_ADD" = "yes" ]; then
	"$GIT" add "$TARGET"
	if [ "$GITIGNORE_AUTO_COMMIT" = "yes" ]; then
		"$GIT" commit -m "Added .gitignore" "$TARGET"
		if [ "$GITIGNORE_AUTO_PUSH" = "yes" ]; then
			"$GIT" push
		fi
	fi
fi

