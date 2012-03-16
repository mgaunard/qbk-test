cmake_minimum_required(VERSION 2.6)

if(NOT BOOST_ROOT)
  set(BOOST_ROOT $ENV{BOOST_ROOT})
endif()

find_program(DOXYGEN_EXECUTABLE doxygen)
find_program(XSLTPROC_EXECUTABLE xsltproc)
find_program(QUICKBOOK_EXECUTABLE quickbook ${BOOST_ROOT}/dist/bin)
find_path(BOOSTBOOK_XSL_DIR docbook.xsl ${BOOST_ROOT}/tools/boostbook/xsl)
find_path(BOOSTBOOK_DTD_DIR boostbook.dtd ${BOOST_ROOT}/tools/boostbook/dtd)
find_path(DOCBOOK_XSL_DIR catalog.xml /usr/share/xml/docbook/stylesheet/docbook-xsl)
find_path(DOCBOOK_DTD_DIR docbookx.dtd /usr/share/xml/docbook/schema/dtd/4.2)

include(CMakeParseArguments OPTIONAL RESULT_VARIABLE CMakeParseArguments_FOUND)

macro(nt2_required)
  foreach(arg ${ARGN})
    if(NOT ${arg})
      message(FATAL_ERROR "${arg} required but not found")
    endif()
  endforeach()
endmacro()
nt2_required(DOXYGEN_EXECUTABLE XSLTPROC_EXECUTABLE QUICKBOOK_EXECUTABLE BOOSTBOOK_XSL_DIR BOOSTBOOK_DTD_DIR DOCBOOK_XSL_DIR DOCBOOK_DTD_DIR CMakeParseArguments_FOUND)
configure_file(${CMAKE_SOURCE_DIR}/catalog.xml.in ${CMAKE_BINARY_DIR}/catalog.xml)

macro(nt2_absolute var file)
  get_filename_component(input_path ${file} PATH)
  if(input_path)
    set(${var} ${file})
  elseif(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/${file})
    set(${var} ${CMAKE_CURRENT_SOURCE_DIR}/${file})
  elseif(EXISTS ${CMAKE_CURRENT_BINARY_DIR}/${file})
    set(${var} ${CMAKE_CURRENT_BINARY_DIR}/${file})
  else()
    set(${var} ${file})
  endif()
endmacro()

macro(nt2_xsltproc output)
  cmake_parse_arguments(ARG "" "COMMENT;WORKING_DIRECTORY" "DEPENDS" ${ARGN})

  add_custom_command(OUTPUT ${output}
                     COMMAND ${CMAKE_COMMAND} "-DXSLTPROC_EXECUTABLE=${XSLTPROC_EXECUTABLE}" "-DCATALOG=${CMAKE_BINARY_DIR}/catalog.xml"
                                              "-DOUTPUT=${output}" "-DARGS=\"${ARG_UNPARSED_ARGUMENTS}\""
                                              -P "${CMAKE_SOURCE_DIR}/nt2.xsltproc.cmake"
                     DEPENDS ${ARG_DEPENDS}
                     COMMENT ${ARG_COMMENT}
                    )
endmacro()

macro(nt2_doc_html target file)
  nt2_absolute(absolute ${file})

  nt2_xsltproc(${CMAKE_BINARY_DIR}/${target}/index.html
               ${BOOSTBOOK_XSL_DIR}/xhtml.xsl
               ${absolute}
               DEPENDS ${file}
               COMMENT "Converting Docbook file ${file} to XHTML..."
              )

  add_custom_target(${target}
                    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/${target} ${CMAKE_BINARY_DIR}/${target}
                    DEPENDS ${CMAKE_BINARY_DIR}/${target}/index.html
                   )
endmacro()

macro(nt2_doc_boostbook file)
  nt2_absolute(absolute ${file}.xml)

  nt2_xsltproc(${file}.docbook
               ${BOOSTBOOK_XSL_DIR}/docbook.xsl
               ${absolute}
               DEPENDS ${ARGN}
               COMMENT "Converting Boostbook file ${file}.xml to Docbook..."
              )
endmacro()

macro(nt2_doc_quickbook file)
  nt2_absolute(absolute ${file}.qbk)
  file(RELATIVE_PATH relative ${CMAKE_SOURCE_DIR} ${absolute})

  # We always build Quickbook files because we cannot reliably identify dependencies
  set(target_name target_${relative})
  string(REPLACE "/" "_" target_name ${target_name})
  add_custom_target(${target_name}
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${absolute} ${CMAKE_CURRENT_BINARY_DIR}
                    COMMAND ${QUICKBOOK_EXECUTABLE}
                            --input-file ${file}.qbk
                            --include-path ${CMAKE_CURRENT_SOURCE_DIR}
                            --include-path ${CMAKE_CURRENT_BINARY_DIR}
                            --output-file ${file}.xml
                    DEPENDS ${file}.qbk
                    COMMENT "Converting Quickbook file ${file}.qbk to Boostbook..."
                    SOURCES ${file}.qbk
                   )
  add_custom_command(OUTPUT ${file}.xml
                     DEPENDS ${target_name}
                    )
endmacro()

macro(nt2_doc_doxygen file)
  nt2_absolute(absolute ${file}.doxyfile)
  file(RELATIVE_PATH relative ${CMAKE_SOURCE_DIR} ${absolute})

  if(NOT IS_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${file}.doxygen)
    file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${file}.doxygen)
  endif()
  file(READ ${absolute} DOXYGEN_CONTENT)
  set(DOXYGEN_CONTENT ${DOXYGEN_CONTENT}
      "QUIET = YES\n"
      "WARN_IF_UNDOCUMENTED = NO\n"
      "GENERATE_LATEX = NO\n"
      "GENERATE_HTML = NO\n"
      "GENERATE_XML = YES\n"
      "XML_OUTPUT = ${CMAKE_CURRENT_BINARY_DIR}/${file}.doxygen\n"
     )
  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/${file}.doxygen/doxyfile ${DOXYGEN_CONTENT})

  # We always run Doxygen because we cannot reliably identify dependencies
  set(target_name target_${relative})
  string(REPLACE "/" "_" target_name ${target_name})
  add_custom_target(${target_name}
                    COMMAND ${DOXYGEN_EXECUTABLE} ${CMAKE_CURRENT_BINARY_DIR}/${file}.doxygen/doxyfile
                    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                    DEPENDS ${file}.doxyfile
                    COMMENT "Running doxygen with XML onput on ${file}.doxyfile..."
                    SOURCES ${file}.doxyfile
                   )
  add_custom_command(OUTPUT ${file}.doxygen/index.xml
                     DEPENDS ${target_name}
                    )

  nt2_xsltproc(${file}.doxygen/all.xml
               ${file}.doxygen/combine.xslt
               ${file}.doxygen/index.xml
               DEPENDS ${file}.doxygen/index.xml
               COMMENT "Combining Doxygen XML output..."
              )

  nt2_xsltproc(${file}.xml
               ${BOOSTBOOK_XSL_DIR}/doxygen/doxygen2boostbook.xsl
               ${file}.doxygen/all.xml
               DEPENDS ${file}.doxygen/all.xml
               COMMENT "Converting Doxygen XML to Boostbook (${file}.xml)..."
              )
endmacro()

macro(nt2_doc target)
  set(dependencies)
  set(main)
  foreach(e ${ARGN})
    get_filename_component(ext ${e} EXT)
    get_filename_component(path ${e} PATH)
    get_filename_component(name ${e} NAME_WE)
    set(file_base ${path}${name})
    if(NOT main)
      set(main ${file_base})
    endif()
    if(ext STREQUAL ".qbk")
      nt2_doc_quickbook(${file_base})
    elseif(ext STREQUAL ".doxyfile")
      nt2_doc_doxygen(${file_base})
    elseif(NOT ext STREQUAL ".xml")
      message(FATAL_ERROR "file ${e} is not a Quickbook, Doxygen or Boostbook file")
    endif()
    list(APPEND dependencies ${file_base}.xml)
  endforeach()
  nt2_doc_boostbook(${main} ${dependencies})
  nt2_doc_html(${target} ${main}.docbook)
endmacro()

nt2_doc(doc test.qbk ref.doxyfile)
