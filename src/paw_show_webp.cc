#include <fstream>
#include <iostream>
#include <vector>

#include <webp/demux.h>
#include <CLI/CLI.hpp>

#include <glad/gl.h>
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

void setup_gl(GLuint& VAO, GLuint& VBO, GLuint& shader_program) {
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

int main(int argc, char* argv[]) {
  CLI::App app{"show webp"};
  argv = app.ensure_utf8(argv);

  std::string webp = "";
  app.add_option("--webp", webp, "webp image");
  CLI11_PARSE(app, argc, argv);

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
  constexpr int window_size = 192;
  constexpr int margin = 20;
  int xpos = mode->width - window_size - margin;
  int ypos = mode->height - window_size - margin;

  GLFWwindow* window =
      glfwCreateWindow(window_size, window_size, "sparky", NULL, NULL);
  glfwSetWindowPos(window, xpos, ypos);
  glfwShowWindow(window);

  Display* dpy = XOpenDisplay(nullptr);
  if (dpy) {
    Window xwin = glfwGetX11Window(window);
    XSetInputFocus(dpy, PointerRoot, RevertToParent, CurrentTime);
    XFlush(dpy);
  }

  glfwMakeContextCurrent(window);
  int version = gladLoadGL(glfwGetProcAddress);
  if (version == 0) {
    std::cout << "Failed to initialize OpenGL context" << std::endl;
    return -1;
  }
  glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);

  std::vector<uint8_t> file_data = read_file_content(webp);

  WebPData webp_data = {file_data.data(), file_data.size()};
  WebPAnimDecoderOptions options;
  WebPAnimDecoderOptionsInit(&options);
  options.color_mode = MODE_RGBA;
  WebPAnimDecoder* decoder = WebPAnimDecoderNew(&webp_data, &options);
  WebPAnimInfo anim_info;
  WebPAnimDecoderGetInfo(decoder, &anim_info);

  GLuint texture;
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

  GLuint VAO, VBO, shader_program;
  setup_gl(VAO, VBO, shader_program);

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  bool is_fading = false;
  float opacity = 1.0f;
  int opacity_location = glGetUniformLocation(shader_program, "opacity");

  double startTime = glfwGetTime();
  while (!glfwWindowShouldClose(window)) {
    if ((glfwGetTime() - startTime) >= 0.06) {
      uint8_t* buf;
      int timestamp;
      if (WebPAnimDecoderHasMoreFrames(decoder)) {
        WebPAnimDecoderGetNext(decoder, &buf, &timestamp);

        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, anim_info.canvas_width,
                     anim_info.canvas_height, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                     buf);
      } else {
        is_fading = true;
      }
      startTime = glfwGetTime();
    }

    if (is_fading) {
      opacity -= 0.03f;
      if (opacity <= 0.0f) {
        glfwSetWindowShouldClose(window, true);
      }
    }

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

    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
      glfwSetWindowShouldClose(window, true);
  }

  glfwTerminate();
  return 0;
}
