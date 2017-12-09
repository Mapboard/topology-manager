
function cfg {
  here="$(dirname "$(readlink -f "$0")")"
  $here/bin/geologic-map-config $1
}

base=$(cfg basedir)
dbname=$(cfg connection.database)
host=$(cfg connection.host)
srid=$(cfg srid)

db_connection=PG:"dbname='$dbname' host='$host'"

function sql {
  psql $dbname -h $host $@
}
