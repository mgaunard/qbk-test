set(ENV{XML_CATALOG_FILES} ${CATALOG})
execute_process(COMMAND ${XSLTPROC_EXECUTABLE} --output ${OUTPUT} --xinclude --nonet ${ARGS})
