#!/bin/bash
#initial file obtained from https://bl.ocks.org/mbostock/5562380
#worked with Staunton Sample and Matthew Bryson

# EPSG:3310 California Albers
PROJECTION='d3.geoTransverseMercator().rotate([159, -54])'
#PROJECTION='d3.geoAlbers().parallels([34, 4.05]).rotate([100, 0])'

# The state FIPS code.
STATE=02

# The ACS 5-Year Estimate vintage.
YEAR=2014

# The display size.
WIDTH=960
HEIGHT=1100

# Download the census tract boundaries.
# Extract the shapefile (.shp) and dBASE (.dbf).
if [ ! -f cb_${YEAR}_${STATE}_tract_500k.shp ]; then
  curl -o cb_${YEAR}_${STATE}_tract_500k.zip \
    "https://www2.census.gov/geo/tiger/GENZ${YEAR}/shp/cb_${YEAR}_${STATE}_tract_500k.zip"
  unzip -o \
    cb_${YEAR}_${STATE}_tract_500k.zip \
    cb_${YEAR}_${STATE}_tract_500k.shp \
    cb_${YEAR}_${STATE}_tract_500k.dbf
fi

# Download the census tract population estimates.
if [ ! -f cb_${YEAR}_${STATE}_tract_B01003.json ]; then
  curl -o cb_${YEAR}_${STATE}_tract_B01003.json \
    "https://api.census.gov/data/${YEAR}/acs5?get=B01003_001E&for=tract:*&in=state:${STATE}"
fi

# 1. Convert to GeoJSON.
# 2. Project.
# 3. Join with the census data.
# 4. Compute the population density.
# 5. Simplify.
# 6. Compute the county borders.
#code modified to handle the state borders and to limit state borders to relevant arcs
geo2topo -n \
  tracts=<(ndjson-join 'd.id' \
    <(shp2json cb_${YEAR}_${STATE}_tract_500k.shp \
      | geoproject "${PROJECTION}.fitExtent([[10, 10], [${WIDTH} - 10, ${HEIGHT} - 10]], d)" \
      | ndjson-split 'd.features' \
      | ndjson-map 'd.id = d.properties.GEOID.slice(2), d') \
    <(ndjson-cat cb_${YEAR}_${STATE}_tract_B01003.json \
      | ndjson-split 'd.slice(1)' \
      | ndjson-map '{id: d[2] + d[3], B01003: +d[0]}') \
    | ndjson-map 'd[0].properties = {density: Math.floor(d[1].B01003 / d[0].properties.ALAND * 2589975.2356)}, d[0]') \
  | toposimplify -p 1 -f \
  | topomerge -k 'd.id.slice(0, 1)' states=tracts \
  | topomerge -k 'd.id.slice(0, 3)' counties=tracts \
  | topomerge --mesh -f 'a !== b' counties=counties \
  | topomerge --mesh -f 'a == b' states=states \
  | topoquantize 1e5 \
  > tx-topo.json
