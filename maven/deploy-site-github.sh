#!/bin/bash
#
# deploy-site-github.sh -- Deploy a Maven site to GitHub pages.
#
# Copyright (c) 2013-2014 by Malte Isberner (https://github.com/misberner).
# 
# Licensed under the MIT License. For details, see the accompanying
# LICENSE file


# Print detailed usage information on stderr
print_usage() {
	cat >&2 <<EOF
Usage: $0 [options]

Allowed options (all options are optional):
 -h                 Print this help message and exit
 -U <url>           The Git URL to use
                      (default: the first GitHub remote used for pushing)
 -d <maven-dir>     The Maven project directory to use
                      (default: current working directory)
 -s <staging-dir>   The Maven Site staging directory to use
                      (default: determine using Maven)
 -p                 Purge the contents of the site directory before copying
 -u <username>      User name to use in automatic commit message
                      (default: determine using git config)
 -m <message>       Custom commit message
                      (default: \`Site deployment by <username> (<rfc-2822-date>)')
 -V 				Append version number to site path
 -l  				Create a shortcut named latest-(snapshot|release) (implies -V)
 -1                 Skip the site generation phase
 -2                 Skip the staging phase (implies -1)
 -b <branch>        The Git branch to use for site deployment
                      (default: \`gh-pages')
 -P <path>          The relative path of the Maven site
                      (default: \`/maven-site/')
EOF
}

info() {
	[ "$QUIET" != "yes" ] && echo "$@"
}

# Perform an echo on stderr
eecho() {
	echo >&2 "$@"
}

# Print an error message and exit with an error exit code
die() {
	eecho "$@"
	exit 1
}

set -o pipefail



# Option defaults
MVN_PROJECT_DIR=.
PURGE=no
SKIP_SITE=no
SKIP_STAGING=no
GIT_BRANCH=gh-pages
RELATIVE_SITE_PATH=/maven-site/
APPEND_VERSION=no
LINK_LATEST=no


# Parse options
while getopts ":hr:d:ps:u:m:12b:P:qVl" opt; do
	case "$opt" in
		h)
			print_usage
			exit 0
			;;
		U)
			GIT_URL="$OPTARG"
			;;
		d)
			MVN_PROJECT_DIR="$OPTARG"
			;;
		p)
			PURGE="yes"
			;;
		s)
			STAGING_DIR="$OPTARG"
			;;
		u)
			USERNAME="$OPTARG"
			;;
		m)
			COMMIT_MESSAGE="$OPTARG"
			;;
		1)
			SKIP_SITE=yes
			;;
		2)
			SKIP_SITE=yes
			SKIP_STAGING=yes
			;;
		b)
			GIT_BRANCH="$OPTARG"
			;;
		P)
			RELATIVE_SITE_PATH="$OPTARG"
			;;
		q)
			QUIET="yes"
			;;
		V)
			APPEND_VERSION="yes"
			;;
		l)
			APPEND_VERSION="yes"
			LINK_LATEST="yes"
			;;
		\?)
			die "Invalid option: -$OPTARG"
			;;
		:)
			die "Option -$OPTARG requires an argument"
			;;
	esac
done



# Test prerequisites
[ -z "$MVN" ] && MVN=`which mvn`
[ -z "$GIT" ] && GIT=`which git`

[ -x "$MVN" ] || die "Cannot use Maven executable \`$MVN'"
[ -x "$GIT" ] || die "Cannot use Git executable \`$GIT'"



# Determine Git URL
if [ -z "$GIT_URL" ]; then
	GIT_URL=`git remote -v | egrep 'github\.com.*\(push\)$' | head -n 1 | awk '{print$2}'`

	if [ "$?" -ne 0 -o -z "$GIT_URL" ]; then
		die "Could not determine Git URL and none specified. Exiting ..."
	fi
fi

info "Git URL is $GIT_URL"


cd "$MVN_PROJECT_DIR"

PROJECT_VERSION=`"$MVN" help:evaluate -Dexpression=project.version | egrep -v '^\['`

if [ "$PROJECT_VERSION" = "null object or invalid expression" -o -z "$PROJECT_VERSION" ]; then
	die "Unable to determine Maven project version. Exiting ..."
fi


if [ "$SKIP_STAGING" != "yes" ]; then
	if [ "$SKIP_SITE" != "yes" ]; then
		info "Creating site ..."
		"$MVN" site:site || die "Failed to create site. Exiting ..."
	fi
	info "Staging site ..."
	"$MVN" site:stage || die "Failed to stage site. Exiting ..."
fi



# Determine staging directory
if [ -z "$STAGING_DIR" ]; then
	STAGING_DIR=`$MVN help:evaluate -Dexpression=stagingDirectory | egrep -v '^\['`

	if [ "$STAGING_DIR" = "null object or invalid expression" ]; then
		STAGING_DIR=`$MVN help:evaluate -Dexpression=project.build.directory | egrep -v '^\['`/staging
	fi
fi
STAGING_DIR=`readlink -f "$STAGING_DIR"`
if [ $? -ne 0 -o ! -d "$STAGING_DIR" ]; then
	die "Staging directory $STAGING_DIR does not exist or is not a directory. Exiting ..."
fi

# Temporary directory for cloning site branch
TEMP_DIR=`mktemp -d --suffix=deploy-github-site`
cd "$TEMP_DIR"

info "Cloning branch $GIT_BRANCH into $TEMP_DIR ..."
"$GIT" clone "$GIT_URL" -b "$GIT_BRANCH" --single-branch .
if [ $? -ne 0 ]; then
	info "Okay, that did not work. Trying to create empty branch."
	"$GIT" init || die "Git error. Exiting ..."
	"$GIT" checkout --orphan "$GIT_BRANCH" || die "Git error. Exiting ..."
	touch ".gitignore" || die "Git error. Exiting ..."
	"$GIT" add ".gitignore" || die "Git error. Exiting ..."
	"$GIT" commit -m "Initialized empty site branch." || die "Git error. Exiting ..."
	"$GIT" remote add sitehost "$GIT_URL" || die "Git error. Exiting ..."
	"$GIT" push -u sitehost "$GIT_BRANCH" || die "Git error. Exiting ..."
fi

LOCAL_SITE_PATH="./$RELATIVE_SITE_PATH"
if [ "$APPEND_VERSION" == "yes" ]; then
	LOCAL_SITE_PATH="./$RELATIVE_SITE_PATH/$PROJECT_VERSION"
fi


if [ "$PURGE" = "yes" ]; then
	rm -rf "$LOCAL_SITE_PATH"
fi

mkdir -p "$LOCAL_SITE_PATH"

cp -r -T "$STAGING_DIR" "$LOCAL_SITE_PATH"

if [ "$LINK_LATEST" == "yes" ]; then
	if [[ "$PROJECT_VERSION" == *-SNAPSHOT ]]; then
		ALIAS_NAME="latest-snapshot"
	else
		ALIAS_NAME="latest-release"
	fi

	LOCAL_ALIAS_PATH="./$RELATIVE_SITE_PATH/$ALIAS_NAME"
	rm -rf "$LOCAL_ALIAS_PATH"
	mkdir -p "$LOCAL_ALIAS_PATH"
	cp -r -T "$LOCAL_SITE_PATH" "$LOCAL_ALIAS_PATH"
fi

cd "$TEMP_DIR"
"$GIT" add "$LOCAL_SITE_PATH"
if [ "$LINK_LATEST" == "yes" ]; then
	"$GIT" add "$LOCAL_ALIAS_PATH"
fi

if [ -z "$USERNAME" ]; then
	USERNAME=`git config --get user.name`
fi

if [ -z "$COMMIT_MESSAGE" ]; then
	COMMIT_MESSAGE="Site deployment by $USERNAME (`date --rfc-2822`)"
fi

"$GIT" commit -am "$COMMIT_MESSAGE" || { echo "Commit failed. Exiting ..."; exit 1; }

"$GIT" push || { echo "Push failed. Exiting ..."; exit 1; }

info "Site deployment successful."

cd
# rm -rf "$TEMP_DIR"
