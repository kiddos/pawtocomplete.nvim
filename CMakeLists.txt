cmake_minimum_required(VERSION 3.14)
project(pawtocomplete C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS_DEBUG "-O0 -g")
set(CMAKE_CXX_FLAGS_RELEASE "-O3")
set(BUILD_SHARED_LIBS ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(FETCHCONTENT_QUIET FALSE)

include(FetchContent)
FetchContent_Declare(
  lua
  GIT_REPOSITORY https://github.com/lua/lua
  GIT_TAG        v5.1
  GIT_SHALLOW    TRUE
  GIT_PROGRESS   TRUE
)

# after watching https://www.youtube.com/watch?v=ncHmEUmJZf4
# switching to abseil flat_hash_map instead of using std::unordered_map
FetchContent_Declare(
  abseil
  GIT_REPOSITORY https://github.com/abseil/abseil-cpp.git
  GIT_TAG        20250512.1
  GIT_PROGRESS   TRUE
)

FetchContent_MakeAvailable(lua abseil)

file(GLOB_RECURSE LUA_SOURCES ${lua_SOURCE_DIR}/*.c)
add_library(paw src/paw.cc ${LUA_SOURCES})
target_include_directories(paw PRIVATE "${lua_SOURCE_DIR}")
target_link_options(paw INTERFACE -Wall -Wextra)
target_link_libraries(paw PRIVATE
  absl::hash
  absl::flat_hash_map
  absl::strings
)

FetchContent_Declare(
  libwebp
  GIT_REPOSITORY https://chromium.googlesource.com/webm/libwebp
  GIT_TAG        v1.6.0
  GIT_SHALLOW    TRUE
  GIT_PROGRESS   TRUE
)

set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "Disable glfw examples" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "Disable glfw tests" FORCE)
set(GLFW_BUILD_DOCS OFF CACHE BOOL "Disable glfw docs" FORCE)
set(GLFW_INSTALL OFF CACHE BOOL "Disable glfw examples" FORCE)
FetchContent_Declare(
  glfw
  GIT_REPOSITORY https://github.com/glfw/glfw.git
  GIT_TAG        3.4
  GIT_SHALLOW    TRUE
  GIT_PROGRESS   TRUE
)

FetchContent_Declare(
  glad
  GIT_REPOSITORY https://github.com/Dav1dde/glad.git
  GIT_TAG v2.0.8
  GIT_SHALLOW
  GIT_PROGRESS   TRUE
  SOURCE_SUBDIR  cmake
)
FetchContent_MakeAvailable(libwebp glfw glad)

FetchContent_Declare(
  CLI11
  GIT_REPOSITORY https://github.com/CLIUtils/CLI11
  GIT_TAG        v2.4.2
  GIT_SHALLOW    TRUE
  GIT_PROGRESS   TRUE
)
FetchContent_MakeAvailable(CLI11)

set(JSONCPP_WITH_TESTS OFF CACHE BOOL "Disable jsoncpp test" FORCE)
set(JSONCPP_WITH_POST_BUILD_UNITTEST OFF CACHE BOOL "Disable jsoncpp unittest" FORCE)
set(JSONCPP_WITH_PKGCONFIG_SUPPORT OFF CACHE BOOL "Disable jsoncpp pkgconfig" FORCE)
set(JSONCPP_WITH_EXAMPLE OFF CACHE BOOL "Disable jsoncpp example" FORCE)
set(BUILD_OBJECT_LIBS OFF CACHE BOOL "Disable jsoncpp object libs" FORCE)
FetchContent_Declare(
  jsoncpp
  GIT_REPOSITORY https://github.com/open-source-parsers/jsoncpp.git
  GIT_TAG        1.9.6
  GIT_SHALLOW    TRUE
  GIT_PROGRESS   TRUE
)

FetchContent_MakeAvailable(jsoncpp)

glad_add_library(glad_gl_core_33 STATIC REPRODUCIBLE LOADER API gl:core=3.3)

find_package(OpenGL REQUIRED)
find_package(X11 REQUIRED)

add_executable(sparky src/sparky.cc)
target_include_directories(sparky PRIVATE ${CLI11_SOURCE_DIR}/include)
target_compile_definitions(sparky
  PRIVATE GLFW_EXPOSE_NATIVE_X11
)
target_link_libraries(sparky
  PRIVATE
  glfw
  glad_gl_core_33
  OpenGL::GL
  webp
  webpdemux
  jsoncpp_lib
  X11
)
