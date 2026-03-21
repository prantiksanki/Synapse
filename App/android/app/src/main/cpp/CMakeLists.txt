# CMakeLists.txt for the SYNAPSE llama_bridge native library.
#
# This builds a shared library (.so) that acts as a JNI bridge between
# the Kotlin LlamaService and the llama.cpp inference engine.
#
# To integrate real llama.cpp:
#   1. Clone https://github.com/ggerganov/llama.cpp into this cpp/ directory.
#   2. Add the llama.cpp sources to the add_library() call or use add_subdirectory().
#   3. Replace the stub implementations in llama_bridge.cpp with real llama.cpp API calls.

cmake_minimum_required(VERSION 3.22.1)

project("llama_bridge" LANGUAGES CXX)

# ---- Build the JNI bridge shared library ---------------------------------- #
add_library(
    llama_bridge       # Library name → produces libllama_bridge.so
    SHARED             # Shared library loaded at runtime via System.loadLibrary()
    llama_bridge.cpp   # JNI bridge source (stubs or real llama.cpp calls)
)

# ---- Find Android system libraries ---------------------------------------- #
find_library(log-lib  log)      # Android logging (Log.d etc.)
find_library(android-lib android) # Android asset / window manager

# ---- Link dependencies ----------------------------------------------------- #
target_link_libraries(
    llama_bridge
    ${log-lib}
    ${android-lib}
)

# ---- Compiler flags -------------------------------------------------------- #
target_compile_options(llama_bridge PRIVATE
    -std=c++17
    -O3                 # Optimise for inference speed
    -ffast-math         # Faster FP math (acceptable for LLM arithmetic)
    -Wall
    -Wextra
)

# ---- Include directories --------------------------------------------------- #
target_include_directories(llama_bridge PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)
