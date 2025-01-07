include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(SmallProject_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(SmallProject_setup_options)
  option(SmallProject_ENABLE_HARDENING "Enable hardening" ON)
  option(SmallProject_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    SmallProject_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    SmallProject_ENABLE_HARDENING
    OFF)

  SmallProject_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR SmallProject_PACKAGING_MAINTAINER_MODE)
    option(SmallProject_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(SmallProject_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(SmallProject_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(SmallProject_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(SmallProject_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(SmallProject_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(SmallProject_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(SmallProject_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(SmallProject_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(SmallProject_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(SmallProject_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(SmallProject_ENABLE_PCH "Enable precompiled headers" OFF)
    option(SmallProject_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(SmallProject_ENABLE_IPO "Enable IPO/LTO" ON)
    option(SmallProject_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(SmallProject_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(SmallProject_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(SmallProject_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(SmallProject_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(SmallProject_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(SmallProject_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(SmallProject_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(SmallProject_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(SmallProject_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(SmallProject_ENABLE_PCH "Enable precompiled headers" OFF)
    option(SmallProject_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      SmallProject_ENABLE_IPO
      SmallProject_WARNINGS_AS_ERRORS
      SmallProject_ENABLE_USER_LINKER
      SmallProject_ENABLE_SANITIZER_ADDRESS
      SmallProject_ENABLE_SANITIZER_LEAK
      SmallProject_ENABLE_SANITIZER_UNDEFINED
      SmallProject_ENABLE_SANITIZER_THREAD
      SmallProject_ENABLE_SANITIZER_MEMORY
      SmallProject_ENABLE_UNITY_BUILD
      SmallProject_ENABLE_CLANG_TIDY
      SmallProject_ENABLE_CPPCHECK
      SmallProject_ENABLE_COVERAGE
      SmallProject_ENABLE_PCH
      SmallProject_ENABLE_CACHE)
  endif()

  SmallProject_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (SmallProject_ENABLE_SANITIZER_ADDRESS OR SmallProject_ENABLE_SANITIZER_THREAD OR SmallProject_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(SmallProject_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(SmallProject_global_options)
  if(SmallProject_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    SmallProject_enable_ipo()
  endif()

  SmallProject_supports_sanitizers()

  if(SmallProject_ENABLE_HARDENING AND SmallProject_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR SmallProject_ENABLE_SANITIZER_UNDEFINED
       OR SmallProject_ENABLE_SANITIZER_ADDRESS
       OR SmallProject_ENABLE_SANITIZER_THREAD
       OR SmallProject_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${SmallProject_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${SmallProject_ENABLE_SANITIZER_UNDEFINED}")
    SmallProject_enable_hardening(SmallProject_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(SmallProject_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(SmallProject_warnings INTERFACE)
  add_library(SmallProject_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  SmallProject_set_project_warnings(
    SmallProject_warnings
    ${SmallProject_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(SmallProject_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    SmallProject_configure_linker(SmallProject_options)
  endif()

  include(cmake/Sanitizers.cmake)
  SmallProject_enable_sanitizers(
    SmallProject_options
    ${SmallProject_ENABLE_SANITIZER_ADDRESS}
    ${SmallProject_ENABLE_SANITIZER_LEAK}
    ${SmallProject_ENABLE_SANITIZER_UNDEFINED}
    ${SmallProject_ENABLE_SANITIZER_THREAD}
    ${SmallProject_ENABLE_SANITIZER_MEMORY})

  set_target_properties(SmallProject_options PROPERTIES UNITY_BUILD ${SmallProject_ENABLE_UNITY_BUILD})

  if(SmallProject_ENABLE_PCH)
    target_precompile_headers(
      SmallProject_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(SmallProject_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    SmallProject_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(SmallProject_ENABLE_CLANG_TIDY)
    SmallProject_enable_clang_tidy(SmallProject_options ${SmallProject_WARNINGS_AS_ERRORS})
  endif()

  if(SmallProject_ENABLE_CPPCHECK)
    SmallProject_enable_cppcheck(${SmallProject_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(SmallProject_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    SmallProject_enable_coverage(SmallProject_options)
  endif()

  if(SmallProject_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(SmallProject_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(SmallProject_ENABLE_HARDENING AND NOT SmallProject_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR SmallProject_ENABLE_SANITIZER_UNDEFINED
       OR SmallProject_ENABLE_SANITIZER_ADDRESS
       OR SmallProject_ENABLE_SANITIZER_THREAD
       OR SmallProject_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    SmallProject_enable_hardening(SmallProject_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
