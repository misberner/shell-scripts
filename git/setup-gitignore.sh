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

TARGET="./.gitignore"

[ $# -eq 1 ] || die "Usage: $0 [style]"

[ -x "$GIT" ] || die  "Could not determine git executable"
[ -x "$WGET" ] || die "Could not determine wget executable"

[ ! -f "$TARGET" ] || die ".gitignore file already exists"


STYLE="$1"

AUTO_ADD="yes"
AUTO_COMMIT="no"

SUCCESS=0

TEMPFILE="`mktemp`"

for root in "${GITIGNORE_ROOTS[@]}"; do
	FILENAME="$STYLE.gitignore"
	wget "$root/$FILENAME" -q -O "$TEMPFILE"
	if [ $? -eq 0 ]; then
		mv "$TEMPFILE" "$TARGET"
		echo "Successfully retrieved $FILENAME from $root"
		if [ "$AUTO_ADD" = "yes" ]; then
			"$GIT" add "$TARGET"
			if [ "$AUTO_COMMIT" = "yes" ]; then
				"$GIT" commit -m "Added .gitignore" "$TARGET"
			fi
		fi
		exit 0
	else
		rm "$TEMPFILE"
	fi
done

eecho "Could not find .gitignore of style $STYLE"
exit 1
