cmake_minimum_required(VERSION 3.16)
project(smart_objects)
set(CMAKE_CXX_STANDARD 17)
add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES IMPORTED_LOCATION
  "${CMAKE_CURRENT_SOURCE_DIR}/third_party/onnxruntime/${OHOS_ARCH}/lib/libonnxruntime.so")
add_library(detector SHARED detector.cpp)
target_include_directories(detector PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/third_party/onnxruntime/include")
target_link_libraries(detector PUBLIC "-Wl,--no-as-needed" onnxruntime "-Wl,--as-needed" libace_napi.z.so)
