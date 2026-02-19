#include <glad/gl.h>
#include <json/json.h>
#include <sys/stat.h>
#include <unistd.h>
#include <webp/demux.h>

#include <CLI/CLI.hpp>
#include <atomic>
#include <fstream>
#include <iostream>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>
// break clang-format sorting
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <X11/Xlib.h>

static void framebuffer_size_callback(GLFWwindow*, int width, int height) {
  glViewport(0, 0, width, height);
}

const char* vertex_shader_source = R"(
    #version 330 core
    layout (location = 0) in vec3 aPos;
    layout (location = 1) in vec2 aTexCoord;
    out vec2 TexCoord;
    void main() {
        gl_Position = vec4(aPos, 1.0);
        TexCoord = aTexCoord;
    }
)";

const char* fragment_shader_source = R"(
    #version 330 core
    out vec4 FragColor;
    in vec2 TexCoord;
    uniform sampler2D ourTexture;
    uniform float opacity;
    void main() {
        vec4 texColor = texture(ourTexture, TexCoord);
        FragColor = vec4(texColor.rgb, texColor.a * opacity);
    }
)";

void setup_shader_program(GLuint& VAO, GLuint& VBO, GLuint& shader_program) {
  float vertices[] = {
      1.0f,  1.0f,  0.0f, 1.0f, 0.0f,  // top right
      1.0f,  -1.0f, 0.0f, 1.0f, 1.0f,  // bottom right
      -1.0f, -1.0f, 0.0f, 0.0f, 1.0f,  // bottom left
      -1.0f, 1.0f,  0.0f, 0.0f, 0.0f   // top left
  };
  unsigned int indices[] = {0, 1, 3, 1, 2, 3};

  GLuint EBO;
  glGenVertexArrays(1, &VAO);
  glGenBuffers(1, &VBO);
  glGenBuffers(1, &EBO);

  glBindVertexArray(VAO);
  glBindBuffer(GL_ARRAY_BUFFER, VBO);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, EBO);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices,
               GL_STATIC_DRAW);

  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)0);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float),
                        (void*)(3 * sizeof(float)));
  glEnableVertexAttribArray(1);

  GLuint vertex_shader = glCreateShader(GL_VERTEX_SHADER);
  glShaderSource(vertex_shader, 1, &vertex_shader_source, NULL);
  glCompileShader(vertex_shader);

  GLuint fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
  glShaderSource(fragment_shader, 1, &fragment_shader_source, NULL);
  glCompileShader(fragment_shader);

  shader_program = glCreateProgram();
  glAttachShader(shader_program, vertex_shader);
  glAttachShader(shader_program, fragment_shader);
  glLinkProgram(shader_program);
}

std::vector<uint8_t> read_file_content(const std::string& filename) {
  std::ifstream ifs(filename, std::ios::binary | std::ios::ate);
  if (ifs.is_open()) {
    std::streamsize size = ifs.tellg();
    ifs.seekg(0, std::ios::beg);
    std::vector<uint8_t> buffer(size);
    if (size > 0) {
      if (!ifs.read(reinterpret_cast<char*>(buffer.data()), size)) {
        throw std::runtime_error("Error reading file");
      }
    }
    return buffer;
  }
  std::cerr << "fail not found" << std::endl;
  return std::vector<uint8_t>();
}

void unfocus_x11(GLFWwindow* window) {
  Display* x11_display = glfwGetX11Display();
  Window x11_window = glfwGetX11Window(window);

  Atom skip_taskbar =
      XInternAtom(x11_display, "_NET_WM_STATE_SKIP_TASKBAR", False);
  Atom wm_state = XInternAtom(x11_display, "_NET_WM_STATE", False);

  XEvent xev;
  memset(&xev, 0, sizeof(xev));
  xev.type = ClientMessage;
  xev.xclient.window = x11_window;
  xev.xclient.message_type = wm_state;
  xev.xclient.format = 32;
  xev.xclient.data.l[0] = 1;  // _NET_WM_STATE_ADD
  xev.xclient.data.l[1] = skip_taskbar;

  XSendEvent(x11_display, DefaultRootWindow(x11_display), False,
             SubstructureNotifyMask | SubstructureRedirectMask, &xev);

  XSetInputFocus(x11_display, PointerRoot, RevertToParent, CurrentTime);
  XFlush(x11_display);
}

struct SpriteFrame {
  std::vector<uint8_t> pixels;
  int duration_ms;
};

struct Sprite {
  double t;
  int width, height;
  int index;
  int loop_start;
  int loop_end;
  int target_frame;
  std::vector<SpriteFrame> frames;

  Sprite(std::vector<SpriteFrame>& frames) : t(0), index(0), frames(frames) {
    loop_start = 0;
    loop_end = frames.size() - 1;
    target_frame = loop_end;
  }

  void reset() { target_frame = 0; }

  bool update() {
    if (t == 0) {
      t = glfwGetTime();
      update_texture();
    } else {
      double t2 = glfwGetTime();
      int diff_millis = (t2 - t) * 1000;
      // std::cout << diff_millis << "-" << frames[index].duration_ms <<
      // std::endl;;

      if (index >= 0 && index < (int)frames.size() &&
          diff_millis >= frames[index].duration_ms) {
        int delta = index < target_frame ? 1 : -1;
        int next_index = index + delta;
        if (next_index == target_frame) {
          target_frame = target_frame == loop_end ? loop_start : loop_end;
        }
        // std::cout << next_index  << " " << target_frame << std::endl;
        index = next_index;
        update_texture();
        t = t2;
      }
    }
    return index == 0;
  }

  void update_texture() {
    auto buf = &frames[index].pixels[0];
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, buf);
  }
};

Sprite read_sprite(const std::string& webp_file, bool loop_back,
                   double fraction) {
  std::vector<uint8_t> file_data = read_file_content(webp_file);

  WebPData webp_data = {file_data.data(), file_data.size()};
  WebPAnimDecoderOptions options;
  WebPAnimDecoderOptionsInit(&options);
  options.color_mode = MODE_RGBA;
  WebPAnimDecoder* decoder = WebPAnimDecoderNew(&webp_data, &options);
  WebPAnimInfo anim_info;
  WebPAnimDecoderGetInfo(decoder, &anim_info);

  int width = anim_info.canvas_width;
  int height = anim_info.canvas_height;

  uint8_t* buf = nullptr;
  int timestamp = 0;
  int previous_timestamp = 0;
  std::vector<SpriteFrame> frames;
  while (WebPAnimDecoderHasMoreFrames(decoder)) {
    WebPAnimDecoderGetNext(decoder, &buf, &timestamp);

    SpriteFrame frame;
    frame.duration_ms = timestamp - previous_timestamp;
    frame.duration_ms *= fraction;
    size_t size = width * height * 4;
    frame.pixels = std::vector<uint8_t>(size);
    memcpy(&frame.pixels[0], buf, size);

    frames.push_back(frame);
    previous_timestamp = timestamp;
  }

  Sprite sprite(frames);
  sprite.width = width;
  sprite.height = height;
  return sprite;
}

enum Emotion {
  IDLE1,
  IDLE2,
  IDLE3,
  HAPPY1,
  SLEEPY1,
  TIRED1,
};

std::vector<std::string> files = {"idle1.webp",  "idle2.webp",   "idle3.webp",
                                  "happy1.webp", "sleepy1.webp", "tired1.webp"};

std::queue<std::string> rpc_queue;
std::mutex queue_mutex;
std::atomic<bool> rpc_running(true);
constexpr int IDLE_TIME = 60;

class Sparky {
 public:
  Sparky(const std::string& folder)
      : e_(IDLE1), next_e_(IDLE1), folder_(folder) {
    for (std::string& f : files) {
      std::string file_path = folder + "/" + f;
      auto sprite = read_sprite(file_path, true, 1.0);
      sprites_.push_back(sprite);
    }
    sprites_[SLEEPY1].loop_start = 24;
    last_rpc_ = glfwGetTime();
  }

  void reset() {
    int idx = e_;
    sprites_[idx].reset();
  }

  void idle1() {
    reset();
    next_e_ = IDLE1;
  }

  void idle2() {
    reset();
    next_e_ = IDLE2;
  }

  void idle3() {
    reset();
    next_e_ = IDLE3;
  }

  void happy1() {
    reset();
    next_e_ = HAPPY1;
  }

  void sleepy() {
    reset();
    next_e_ = SLEEPY1;
  }

  void tired() {
    reset();
    next_e_ = TIRED1;
  }

  void update() {
    int idx = e_;
    bool reset = sprites_[idx].update();
    if (reset) {
      e_ = next_e_;
    }
  }

  Emotion current_emotion() { return e_; }

 private:
  Emotion e_;
  Emotion next_e_;
  double last_rpc_;
  std::string folder_;
  std::vector<Sprite> sprites_;
};

const char* pipe_path = "/tmp/sparky_rpc";

void create_pipe() {
  if (mkfifo(pipe_path, 0666) == -1) {
    perror("mkfifo");
  }
}

void pipe_listener() {
  std::cout << "rpc listener running..." << std::endl;
  while (rpc_running) {
    std::ifstream pipe(pipe_path);
    std::string line;
    while (rpc_running && std::getline(pipe, line)) {
      if (!line.empty()) {
        std::cout << "got rpc: " << line << std::endl;
        std::lock_guard<std::mutex> lock(queue_mutex);
        rpc_queue.push(line);
      }
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  std::cout << "rpc listener closing..." << std::endl;
}

bool pipe_exists() {
  struct stat buffer;
  if (stat(pipe_path, &buffer) == 0) {
    return S_ISFIFO(buffer.st_mode);
  }
  return false;
}

double last_rpc = 0;

void process_rpc(Sparky& sparky, GLFWwindow* window) {
  if (rpc_queue.empty() && glfwGetTime() - last_rpc >= IDLE_TIME) {
    if (sparky.current_emotion() != SLEEPY1) {
      sparky.sleepy();
    }
    return;
  }

  Json::CharReaderBuilder reader_builder;
  const std::unique_ptr<Json::CharReader> reader(
      reader_builder.newCharReader());

  std::lock_guard<std::mutex> lock(queue_mutex);
  JSONCPP_STRING err;
  Json::Value value;
  while (!rpc_queue.empty()) {
    std::string json = rpc_queue.front();
    rpc_queue.pop();
    if (json.empty()) {
      continue;
    }
    std::cout << "process rpc: " << json << std::endl;
    last_rpc = glfwGetTime();
    if (reader->parse(json.c_str(), json.c_str() + json.length(), &value,
                      &err)) {
      std::string method = value["method"].as<std::string>();
      if (method == "emotion") {
        std::string emotion = value["params"].as<std::string>();
        std::cout << "next emotion: " << emotion << std::endl;
        if (emotion == "idle1") {
          sparky.idle1();
        } else if (emotion == "idle2") {
          sparky.idle2();
        } else if (emotion == "idle3") {
          sparky.idle3();
        } else if (emotion == "happy1") {
          sparky.happy1();
        } else if (emotion == "sleepy") {
          sparky.sleepy();
        } else if (emotion == "tired") {
          sparky.tired();
        }
      } else if (method == "close") {
        glfwSetWindowShouldClose(window, true);
      }
    } else {
      std::cerr << err << std::endl;
    }
  }
}

int main(int argc, char* argv[]) {
  CLI::App app{"show webp"};
  argv = app.ensure_utf8(argv);

  std::string sprites_folder;
  app.add_option("--sprite-folder", sprites_folder, "");
  CLI11_PARSE(app, argc, argv);

  if (pipe_exists()) {
    std::cout << "sparky already started" << std::endl;
    return 0;
  }

  create_pipe();

  if (!glfwInit()) {
    return -1;
  }

  GLFWmonitor* primary = glfwGetPrimaryMonitor();
  const GLFWvidmode* mode = glfwGetVideoMode(primary);

  glfwWindowHint(GLFW_FOCUS_ON_SHOW, GLFW_FALSE);
  glfwWindowHint(GLFW_FOCUSED, GLFW_FALSE);
  glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
  glfwWindowHint(GLFW_MOUSE_PASSTHROUGH, GLFW_TRUE);
  glfwWindowHint(GLFW_FLOATING, GLFW_TRUE);
  glfwWindowHint(GLFW_DECORATED, GLFW_FALSE);
  glfwWindowHint(GLFW_TRANSPARENT_FRAMEBUFFER, GLFW_TRUE);
  constexpr int window_size = 128;
  constexpr int margin = 20;
  int xpos = mode->width - window_size - margin;
  int ypos = mode->height - window_size - margin;

  GLFWwindow* window =
      glfwCreateWindow(window_size, window_size, "sparky", NULL, NULL);
  glfwSetWindowPos(window, xpos, ypos);
  glfwShowWindow(window);

  if (glfwGetPlatform() == GLFW_PLATFORM_X11) {
    unfocus_x11(window);
  }

  glfwMakeContextCurrent(window);
  int version = gladLoadGL(glfwGetProcAddress);
  if (version == 0) {
    std::cout << "Failed to initialize OpenGL context" << std::endl;
    return -1;
  }
  glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);

  Sparky sparky(sprites_folder);

  GLuint texture;
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

  GLuint VAO, VBO, shader_program;
  setup_shader_program(VAO, VBO, shader_program);

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  bool is_fading = false;
  float opacity = 1.0f;
  int opacity_location = glGetUniformLocation(shader_program, "opacity");

  std::thread listenerThread(pipe_listener);

  double startTime = glfwGetTime();
  while (!glfwWindowShouldClose(window)) {
    sparky.update();
    process_rpc(sparky, window);

    glClear(GL_COLOR_BUFFER_BIT);
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glEnable(GL_TEXTURE_2D);
    glUseProgram(shader_program);
    glUniform1f(opacity_location, opacity);
    glBindTexture(GL_TEXTURE_2D, texture);
    glBindVertexArray(VAO);
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0);

    glfwSwapBuffers(window);
    glfwPollEvents();

    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS) {
      glfwSetWindowShouldClose(window, true);
    }
  }

  rpc_running = false;
  if (listenerThread.joinable()) {
    listenerThread.detach();
  }

  unlink(pipe_path);
  glfwTerminate();
  return 0;
}
