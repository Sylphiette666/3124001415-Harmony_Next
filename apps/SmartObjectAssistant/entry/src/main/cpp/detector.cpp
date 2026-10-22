#include "napi/native_api.h"
#define ORT_API_MANUAL_INIT
#include "onnxruntime_cxx_api.h"
#include <chrono>
#include <cstring>
#include <dlfcn.h>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {
using Clock = std::chrono::steady_clock;
double Millis(Clock::time_point start) {
  return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}
std::unique_ptr<Ort::Env> ortEnv;
const OrtApiBase *apiBase = nullptr;
void *ortLibrary = nullptr;
std::mutex gate;
std::unique_ptr<Ort::Session> session;
std::string loadedPath;
std::string inputName;
std::string outputName;

std::string ReadString(napi_env env, napi_value value) {
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || length > 4096)
    throw std::runtime_error("Invalid model path");
  std::vector<char> chars(length + 1);
  napi_get_value_string_utf8(env, value, chars.data(), chars.size(), &length);
  return std::string(chars.data(), length);
}
void Set(napi_env env, napi_value object, const char *key, napi_value value) {
  napi_set_named_property(env, object, key, value);
}
napi_value Number(napi_env env, double value) {
  napi_value result; napi_create_double(env, value, &result); return result;
}
napi_value String(napi_env env, const std::string &value) {
  napi_value result; napi_create_string_utf8(env, value.c_str(), value.size(), &result); return result;
}
napi_value Dims(napi_env env, const std::vector<int64_t> &dims) {
  napi_value array; napi_create_array_with_length(env, dims.size(), &array);
  for (size_t i = 0; i < dims.size(); ++i) napi_set_element(env, array, i, Number(env, dims[i]));
  return array;
}
double Load(const std::string &path) {
  if (session && loadedPath == path) return 0;
  const auto start = Clock::now();
  if (!ortEnv) {
    // Resolve the public C entry point without an ELF versioned relocation.
    // Keep the upstream binary intact and retain its handle for session lifetime.
    ortLibrary = dlopen("libonnxruntime.so", RTLD_NOW | RTLD_LOCAL);
    if (!ortLibrary) throw std::runtime_error(std::string("ORT dlopen: ") + dlerror());
    using GetBase = const OrtApiBase *(ORT_API_CALL *)(void);
    auto getBase = reinterpret_cast<GetBase>(dlsym(ortLibrary, "OrtGetApiBase"));
    if (!getBase) getBase = reinterpret_cast<GetBase>(dlvsym(ortLibrary, "OrtGetApiBase", "VERS_1.16.3"));
    if (!getBase) throw std::runtime_error(std::string("ORT entry point: ") + dlerror());
    apiBase = getBase();
    const OrtApi *api = apiBase->GetApi(ORT_API_VERSION);
    if (!api) throw std::runtime_error("ONNX Runtime C API version mismatch");
    Ort::InitApi(api); ortEnv = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_ERROR, "SmartObjects");
  }
  Ort::SessionOptions options;
  options.SetIntraOpNumThreads(2);
  options.SetInterOpNumThreads(1);
  options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
  auto candidate = std::make_unique<Ort::Session>(*ortEnv, path.c_str(), options);
  if (candidate->GetInputCount() != 1 || candidate->GetOutputCount() != 1)
    throw std::runtime_error("Expected one YOLO input and one output");
  auto inputType = candidate->GetInputTypeInfo(0);
  auto inputTensor = inputType.GetTensorTypeAndShapeInfo();
  auto shape = inputTensor.GetShape();
  if (shape != std::vector<int64_t>({1, 3, 640, 640}))
    throw std::runtime_error("Expected YOLO input [1,3,640,640]");
  auto outputType = candidate->GetOutputTypeInfo(0);
  auto outputTensor = outputType.GetTensorTypeAndShapeInfo();
  auto output = outputTensor.GetShape();
  if (inputTensor.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
      outputTensor.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)
    throw std::runtime_error("Expected float32 input and output tensors");
  if (output != std::vector<int64_t>({1, 84, 8400}) && output != std::vector<int64_t>({1, 8400, 84}))
    throw std::runtime_error("Expected COCO YOLO output [1,84,8400] or [1,8400,84]");
  Ort::AllocatorWithDefaultOptions allocator;
  auto in = candidate->GetInputNameAllocated(0, allocator);
  auto out = candidate->GetOutputNameAllocated(0, allocator);
  inputName = in.get(); outputName = out.get();
  session = std::move(candidate); loadedPath = path;
  return Millis(start);
}
napi_value Inspect(napi_env env, napi_callback_info info) {
  try {
    size_t count = 1; napi_value args[1]; napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    if (count != 1) throw std::runtime_error("Model path is required");
    std::lock_guard<std::mutex> lock(gate);
    Load(ReadString(env, args[0]));
    napi_value result; napi_create_object(env, &result);
    Set(env, result, "input", String(env, inputName)); Set(env, result, "output", String(env, outputName));
    Set(env, result, "dims", Dims(env, session->GetOutputTypeInfo(0).GetTensorTypeAndShapeInfo().GetShape()));
    Set(env, result, "runtime", String(env, apiBase->GetVersionString()));
    return result;
  } catch (const std::exception &error) { napi_throw_error(env, nullptr, error.what()); return nullptr; }
}
napi_value Infer(napi_env env, napi_callback_info info) {
  try {
    size_t count = 2; napi_value args[2]; napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    if (count != 2) throw std::runtime_error("Model path and NCHW tensor are required");
    size_t bytes = 0; void *data = nullptr;
    if (napi_get_arraybuffer_info(env, args[1], &data, &bytes) != napi_ok || bytes != 3 * 640 * 640 * sizeof(float))
      throw std::runtime_error("Expected a contiguous float32 NCHW ArrayBuffer with 4915200 bytes");
    const size_t length = bytes / sizeof(float);
    std::lock_guard<std::mutex> lock(gate);
    const double loadMs = Load(ReadString(env, args[0]));
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    const int64_t shape[] = {1, 3, 640, 640};
    auto tensor = Ort::Value::CreateTensor<float>(memory, static_cast<float *>(data), length, shape, 4);
    const char *inputs[] = {inputName.c_str()}; const char *outputs[] = {outputName.c_str()};
    const auto start = Clock::now();
    auto values = session->Run(Ort::RunOptions{nullptr}, inputs, &tensor, 1, outputs, 1);
    const double inferenceMs = Millis(start);
    auto metadata = values[0].GetTensorTypeAndShapeInfo();
    if (metadata.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)
      throw std::runtime_error("Expected float32 YOLO output");
    const size_t elements = metadata.GetElementCount();
    napi_value outputBuffer, result; void *destination = nullptr;
    napi_create_arraybuffer(env, elements * sizeof(float), &destination, &outputBuffer);
    std::memcpy(destination, values[0].GetTensorData<float>(), elements * sizeof(float));
    napi_create_object(env, &result); Set(env, result, "data", outputBuffer);
    Set(env, result, "dims", Dims(env, metadata.GetShape()));
    Set(env, result, "loadMs", Number(env, loadMs)); Set(env, result, "inferenceMs", Number(env, inferenceMs));
    return result;
  } catch (const std::exception &error) { napi_throw_error(env, nullptr, error.what()); return nullptr; }
}
napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor methods[] = {
    {"infer", nullptr, Infer, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"inspect", nullptr, Inspect, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, 2, methods); return exports;
}
napi_module module = {1, 0, nullptr, Init, "detector", nullptr, {0}};
}
extern "C" __attribute__((constructor)) void RegisterDetector() { napi_module_register(&module); }
