EXTENSION_VERSION = 1.0
EXTENSION_FILE := istoria--${EXTENSION_VERSION}.sql

main:
	@echo "make ext\nmake install"

ext:
	echo "\echo Use \"CREATE EXTENSION pair\" to load this file. \quit" > istoria--${EXTENSION_VERSION}.sql
	cat tables/*.sql functions/*.sql triggers/*.sql >> ${EXTENSION_FILE}

EXTENSION = istoria
DATA = ${EXTENSION_FILE}

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
