cmake_minimum_required(VERSION 3.14)
project(pawtocomplete C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra")
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
)

# after watching https://www.youtube.com/watch?v=ncHmEUmJZf4
# switching to abseil flat_hash_map instead of using std::unordered_map
FetchContent_Declare(
  abseil
  GIT_REPOSITORY https://github.com/abseil/abseil-cpp.git
  GIT_TAG        20250512.1
)

FetchContent_MakeAvailable(lua abseil)

message("${lua_SOURCE_DIR}/src")
include_directories("${lua_SOURCE_DIR}")
file(GLOB_RECURSE LUA_SOURCES ${lua_SOURCE_DIR}/*.c)
add_library(paw src/paw.cc ${LUA_SOURCES})

target_link_libraries(paw PRIVATE absl::hash absl::flat_hash_map)
