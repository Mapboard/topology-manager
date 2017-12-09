here="$(dirname "$(readlink -f "$0")")"

base=${here}
dbname="Naukluft"
host="localhost"
srid=32619

db_connection=PG:"dbname='$dbname' host='$host'"

function sql {
  psql $dbname -h $host $@
}
