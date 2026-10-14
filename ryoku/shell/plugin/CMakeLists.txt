# Ryoku.Blobs: the SDF metaball plugin behind the screen frame (see
# docs/frame.md). A standard Qt6 QML module: qt_add_qml_module + AUTOMOC +
# qmltyperegistrar register the QML_ELEMENT types, qt_add_shaders bakes the
# metaball shaders into the module as :/shaders/*.qsb.
#
# It produces a dynamically loadable module under <build>/qml/Ryoku/Blobs that
# Quickshell picks up from QML2_IMPORT_PATH. build.sh wraps the configure/build
# and copies that module onto a QML import path; it ships prebuilt (the target
# has no build toolchain).
cmake_minimum_required(VERSION 3.28)

project(ryoku-blobs LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick ShaderTools Multimedia)
find_package(Threads REQUIRED)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_qml_module(ryoku-blobs
    URI Ryoku.Blobs
    VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/Ryoku/Blobs"
    SOURCES
        blobgroup.cpp blobgroup.hpp
        blobshape.cpp blobshape.hpp
        blobrect.cpp blobrect.hpp
        blobwave.cpp blobwave.hpp
        blobinvertedrect.cpp blobinvertedrect.hpp
        blobmaterial.cpp blobmaterial.hpp
        borderbeam.cpp borderbeam.hpp
        bordermaterial.cpp bordermaterial.hpp
        camerafeed.cpp camerafeed.hpp
        systemmonitor.cpp systemmonitor.hpp
        systemgraph.cpp systemgraph.hpp
        thinkingorb.cpp thinkingorb.hpp
)

# QQuickItems use scene-graph materials, CameraFeed uses Multimedia, and
# SystemMonitor keeps blocking kernel/driver reads on a worker thread.
target_link_libraries(ryoku-blobs PRIVATE Qt6::Quick Qt6::Multimedia Threads::Threads)

# Ship both the dynamic plugin and its backing library in the module directory,
# and give the plugin an $ORIGIN rpath so it resolves the backing from its own
# folder. The module is then relocatable: copy the directory onto any QML import
# path and it loads, with no shared lib to find elsewhere.
set_target_properties(ryoku-blobs ryoku-blobsplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/Ryoku/Blobs")
set_target_properties(ryoku-blobsplugin PROPERTIES
    INSTALL_RPATH "$ORIGIN"
    BUILD_WITH_INSTALL_RPATH ON)

qt_add_shaders(ryoku-blobs "blob_shaders"
    BATCHABLE
    GLSL "300es,330"
    PREFIX "/"
    FILES
        shaders/blob.vert
        shaders/blob.frag
        shaders/beam.vert
        shaders/beam.frag
)
