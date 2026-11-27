# Spectrum analysis from LukashonakV/cava 1.0.0. The shell supplies audio via PipeWire.
enable_language(C)
pkg_check_modules(FFTW REQUIRED IMPORTED_TARGET fftw3)
add_library(cavacore STATIC cavacore.c)
target_include_directories(cavacore PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(cavacore PRIVATE PkgConfig::FFTW m)
target_compile_options(cavacore PRIVATE -w)
set_target_properties(cavacore PROPERTIES POSITION_INDEPENDENT_CODE ON C_VISIBILITY_PRESET hidden)
