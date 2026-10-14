cmake_minimum_required(VERSION 3.20)

project(rashin-app VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(WEBKIT REQUIRED IMPORTED_TARGET webkit2gtk-4.1)

add_executable(rashin-app main.cpp)
target_compile_definitions(
    rashin-app PRIVATE RASHIN_APP_VERSION="${PROJECT_VERSION}")
target_link_libraries(
    rashin-app PRIVATE PkgConfig::GTK3 PkgConfig::WEBKIT)

install(TARGETS rashin-app DESTINATION bin)
