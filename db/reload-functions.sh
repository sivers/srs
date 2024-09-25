#!/bin/sh
# RELOAD SQL FUNCTIONS WITHOUT LOSING DATA

# Assumes you have already created database & tables:
# createuser srs
# createdb -O srs srs
# psql -U srs -d srs -f tables.sql

psql -U srs -d srs -c "drop schema srs cascade"
psql -U srs -d srs -c "create schema srs"
psql -U srs -d srs -c "set search_path = srs,public"
psql -U srs -d srs -f functions.sql
psql -U srs -d srs -f api.sql

psql -U srs -d srs
