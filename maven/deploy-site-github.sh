#!/bin/bash
#
# deploy-site-github.sh -- Deploy a Maven site to GitHub pages.
#
# Copyright (c) 2013 by Malte Isberner (https://github.com/misberner).
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

print_usage() {
	cat <<EOF
Usage: $0 [options]

Allowed options (all options are optional):
 -h                 Print this help message and exit
 -r <remote>        The Git remote to use
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
 -1                 Skip the site generation phase
 -2                 Skip the staging phase (implies -1)
 -b <branch>        The Git branch to use for site deployment
                      (default: \`gh-pages')
 -P <path>          The relative path of the Maven site
                      (default: \`/maven-site/')
EOF
}


set -o pipefail


MVN_PROJECT_DIR=.
PURGE=no
SKIP_SITE=no
SKIP_STAGING=no
GIT_BRANCH=gh-pages
RELATIVE_SITE_PATH=/maven-site/

MVN=`which mvn`
GIT=`which git`


while getopts ":hr:d:ps:u:m:12b:P:" opt; do
	case "$opt" in
		h)
			print_usage
			exit 0
			;;
		r)
			GIT_REMOTE="$OPTARG"
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
		\?)
			echo >&2 "Invalid option: -$OPTARG"
			exit 1
			;;
		:)
			echo >&2 "Option -$OPTARG requires an argument"
			exit 1
			;;
	esac
done




if [ -z "$GIT_REMOTE" ]; then
	GIT_REMOTE=`git remote -v | egrep 'github\.com.*\(push\)$' | head -n 1 | awk '{print$2}'`

	if [ "$?" -ne 0 -o -z "$GIT_REMOTE" ]; then
		echo "Could not determine Git remote and none specified. Exiting ..."
		exit 1
	fi
fi

echo "Git remote is $GIT_REMOTE"

cd "$MVN_PROJECT_DIR"

if [ "$SKIP_STAGING" != "yes" ]; then
	if [ "$SKIP_SITE" != "yes" ]; then
		echo "Creating site ..."
		"$MVN" site:site || { echo "Failed to create site. Exiting ..."; exit 1; }
	fi
	echo "Staging site ..."
	"$MVN" site:stage || { echo "Failed to stage site. Exiting ..."; exit 1; }
fi

if [ -z "$STAGING_DIR" ]; then
	STAGING_DIR=`$MVN help:evaluate -Dexpression=stagingDirectory | egrep -v '^\['`

	if [ "$STAGING_DIR" = "null object or invalid expression" ]; then
		STAGING_DIR=`$MVN help:evaluate -Dexpression=project.build.directory | egrep -v '^\['`/staging
	fi
fi
STAGING_DIR=`readlink -f "$STAGING_DIR"`
if [ $? -ne 0 -o ! -d "$STAGING_DIR" ]; then
	echo "Staging directory $STAGING_DIR does not exist or is not a directory. Exiting ..."
	exit 1
fi


TEMP_DIR=`mktemp -d --suffix=deploy-github-site`
cd "$TEMP_DIR"

echo "Cloning branch $GIT_BRANCH into $TEMP_DIR ..."
"$GIT" clone "$GIT_REMOTE" -b "$GIT_BRANCH" --single-branch
if [ $? -ne 0 ]; then
	echo "Okay, that did not work. Trying to create empty branch."
	"$GIT" init || { echo "Git error. Exiting ..."; exit 1; }
	"$GIT" checkout --orphan "$GIT_BRANCH" || { echo "Git error. Exiting ..."; exit 1; }
	touch ".gitignore" || { echo "Git error. Exiting ..."; exit 1; }
	"$GIT" add ".gitignore" || { echo "Git error. Exiting ..."; exit 1; }
	"$GIT" commit -m "Initialized empty site branch." || { echo "Git error. Exiting ..."; exit 1; }
	"$GIT" remote add sitehost "$GIT_REMOTE" || { echo "Git error. Exiting ..."; exit 1; }
	"$GIT" push -u sitehost "$GIT_BRANCH" || { echo "Git error. Exiting ..."; exit 1; }
fi

LOCAL_SITE_PATH="$TEMP_DIR/$RELATIVE_SITE_PATH"

if [ "$PURGE" = "yes" ]; then
	rm -rf "$LOCAL_SITE_PATH"
fi

mkdir -p "$LOCAL_SITE_PATH"

cp -r -T "$STAGING_DIR" "$LOCAL_SITE_PATH"

cd "$TEMP_DIR"
"$GIT" add "$LOCAL_SITE_PATH"

if [ -z "$USERNAME" ]; then
	USERNAME=`git config --get user.name`
fi

if [ -z "$COMMIT_MESSAGE" ]; then
	COMMIT_MESSAGE="Site depoloyment by $USERNAME (`date --rfc-2822`)"
fi

"$GIT" commit -am "$COMMIT_MESSAGE" || { echo "Commit failed. Exiting ..."; exit 1; }

"$GIT" push || { echo "Push failed. Exiting ..."; exit 1; }

echo "Site deployment successful."

cd
rm -rf "$TEMP_DIR"
