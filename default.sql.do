source defs.sh
cat $1 | sql -v srid=$srid >&2

