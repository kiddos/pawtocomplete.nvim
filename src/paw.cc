extern "C" {
#include <string.h>

#include "lauxlib.h"
#include "lua.h"
}

#include <absl/strings/str_format.h>

#include <algorithm>
#include <vector>

#include "paw.h"

#define MAX_STARS 5

std::string trim(const std::string& str) {
  size_t first = str.find_first_not_of(" \t\n\r");
  if (first == std::string::npos) {
    return "";
  }
  size_t last = str.find_last_not_of(" \t\n\r");
  return str.substr(first, (last - first + 1));
}

std::string trim_long_text(const std::string& s, size_t max_len) {
  if (s.length() > max_len) {
    return s.substr(0, max_len) + "...";
  }
  return s;
}

/**
 * param1: text
 */
int lua_trim_long_text(lua_State* L) {
  const char* input = luaL_checkstring(L, 1);
  int max_len = luaL_checkint(L, 2);
  std::string t = trim(input);
  std::string trimmed = trim_long_text(t, max_len);
  lua_pushstring(L, trimmed.c_str());
  return 1;
}

bool has_none_space(const char* s) {
  size_t len = strlen(s);
  if (len > 0) {
    for (size_t i = 0; i < len; ++i) {
      if (!isspace(s[i])) {
        return true;
      }
    }
  }
  return false;
}

/**
 * param1: table|string
 */
int lua_is_whitespace(lua_State* L) {
  if (lua_istable(L, 1)) {
    lua_pushnil(L);

    bool is_whitespace = true;
    while (lua_next(L, 1) != 0) {
      // Key is at index -2, value at -1
      if (!lua_isnumber(L, -2)) {
        lua_pop(L, 1);
        is_whitespace = false;
        break;
      }

      if (lua_isstring(L, -1)) {
        const char* value = lua_tostring(L, -1);
        if (has_none_space(value)) {
          lua_pop(L, 1);
          is_whitespace = false;
          break;
        }
      } else {
        lua_pop(L, 1);
        is_whitespace = false;
        break;
      }
      lua_pop(L, 1);
    }
    lua_pushboolean(L, is_whitespace);
  } else if (lua_isstring(L, 1)) {
    const char* input = luaL_checkstring(L, 1);
    size_t len = strlen(input);
    bool is_whitespace = true;
    for (size_t i = 0; i < len; ++i) {
      if (!isspace(input[i])) {
        is_whitespace = false;
      }
    }
    lua_pushboolean(L, is_whitespace);
  }
  return 1;
}

bool is_word_char(char c) { return isalnum(c) || c == '_' || c == '-'; }

int lua_find_last_word_index(lua_State* L) {
  const char* input = luaL_checkstring(L, 1);
  size_t len = strlen(input);
  int last_word_index = -1;
  for (int i = len - 1; i >= 0; --i) {
    if (is_word_char(input[i])) {
      last_word_index = i;
    } else {
      break;
    }
  }
  if (last_word_index >= 0) {
    lua_pushnumber(L, last_word_index);
  } else {
    lua_pushnil(L);
  }
  return 1;
}

int lua_find_last_trigger_index(lua_State* L) {
  const char* input = luaL_checkstring(L, 1);
  const char* trigger_str = luaL_checkstring(L, 2);
  char trigger_char = trigger_str[0];
  size_t len = strlen(input);
  int index = -1;
  for (int i = len - 1; i >= 0; --i) {
    if (!is_word_char(input[i])) {
      if (input[i] == trigger_char) {
        index = i;
      }
      break;
    }
  }

  if (index >= 0) {
    lua_pushnumber(L, index);
  } else {
    lua_pushnil(L);
  }
  return 1;
}

// given a table and a list
// retrieve the value from table[list[1]][list[1]][...]
int lua_table_get(lua_State* L) {
  if (!lua_istable(L, 1) || !lua_istable(L, 2)) {
    lua_pushnil(L);
    return 1;
  }

  int list_len = lua_objlen(L, 2);
  if (lua_isnumber(L, -1)) {
    list_len = (int)lua_tonumber(L, -1);
  }

  lua_pushvalue(L, 1);

  for (int i = 1; i <= list_len; ++i) {
    lua_pushinteger(L, i);
    lua_gettable(L, 2);

    lua_pushvalue(L, -2);
    lua_pushvalue(L, -2);

    lua_gettable(L, -2);

    if (lua_isnil(L, -1)) {
      lua_pushnil(L);
      return 1;
    }

    lua_replace(L, -3);
    lua_pop(L, 1);
  }

  lua_replace(L, 1);
  lua_settop(L, 1);
  return 1;
}

CompletionItemKind get_completion_item_kind(lua_State* L, const char* key) {
  lua_getfield(L, -1, key);
  CompletionItemKind kind =
      static_cast<CompletionItemKind>(luaL_optinteger(L, -1, 1));
  lua_pop(L, 1);
  return kind;
}

std::optional<int> get_optional_int(lua_State* L, const char* key) {
  lua_getfield(L, -1, key);
  if (lua_isnil(L, -1)) {
    lua_pop(L, 1);
    return std::nullopt;
  }
  auto val = luaL_optinteger(L, -1, 1);
  lua_pop(L, 1);
  return std::optional<int>(val);
}

std::optional<std::string> get_optional_string(lua_State* L, const char* key) {
  lua_getfield(L, -1, key);
  std::optional<std::string> result;
  if (lua_isstring(L, -1)) {
    result = std::optional<std::string>(lua_tostring(L, -1));
  }
  lua_pop(L, 1);
  return result;
}

std::optional<Range> get_optional_range(lua_State* L, const char* key) {
  lua_getfield(L, -1, key);
  std::optional<Range> range;
  if (lua_istable(L, -1)) {
    range.emplace(Range{});

    lua_getfield(L, -1, "start");
    if (lua_istable(L, -1)) {
      lua_getfield(L, -1, "line");
      range->start.line = luaL_checkinteger(L, -1);
      lua_pop(L, 1);
      lua_getfield(L, -1, "character");
      range->start.character = luaL_checkinteger(L, -1);
      lua_pop(L, 1);
    }
    lua_pop(L, 1);
    lua_getfield(L, -1, "end");
    if (lua_istable(L, -1)) {
      lua_getfield(L, -1, "line");
      range->end.line = luaL_checkinteger(L, -1);
      lua_pop(L, 1);
      lua_getfield(L, -1, "character");
      range->end.character = luaL_checkinteger(L, -1);
      lua_pop(L, 1);
    }
    lua_pop(L, 1);
  }
  lua_pop(L, 1);
  return range;
}

std::optional<TextEdit> get_optional_text_edit(lua_State* L, const char* key) {
  lua_getfield(L, -1, key);
  std::optional<TextEdit> edit;
  if (lua_istable(L, -1)) {
    auto new_text = get_optional_string(L, "newText");
    edit.emplace(TextEdit{
        .new_text = new_text ? *new_text : "",
        .range = get_optional_range(L, "range"),
        .insert = get_optional_range(L, "insert"),
        .replace = get_optional_range(L, "replace"),
    });
  }
  lua_pop(L, 1);
  return edit;
}

CompletionItem parse_completion_item(lua_State* L) {
  CompletionItem item;
  auto label = get_optional_string(L, "label");
  item.label = label ? trim(*label) : "";
  item.kind = get_completion_item_kind(L, "kind");
  item.detail = get_optional_string(L, "detail");
  item.sort_text = get_optional_string(L, "sortText");
  item.filter_text = get_optional_string(L, "filterText");
  item.insert_text = get_optional_string(L, "insertText");
  item.insert_text_format = get_optional_int(L, "insertTextFormat");
  item.text_edit = get_optional_text_edit(L, "textEdit");
  return item;
}

std::vector<CompletionItem> parse_completion_items(lua_State* L) {
  std::vector<CompletionItem> items;

  lua_pushnil(L);
  while (lua_next(L, -2) != 0) {
    if (lua_istable(L, -1)) {
      items.push_back(parse_completion_item(L));
    }
    lua_pop(L, 1);
  }
  return items;
}

void push_position(lua_State* L, const Position& p) {
  lua_newtable(L);
  lua_pushinteger(L, p.line);
  lua_setfield(L, -2, "line");
  lua_pushinteger(L, p.character);
  lua_setfield(L, -2, "character");
}

void push_range(lua_State* L, const Range& r) {
  lua_newtable(L);
  push_position(L, r.start);
  lua_setfield(L, -2, "start");
  push_position(L, r.end);
  lua_setfield(L, -2, "end");
}

void push_text_edit(lua_State* L, const TextEdit& edit) {
  lua_newtable(L);
  lua_pushstring(L, edit.new_text.c_str());
  lua_setfield(L, -2, "newText");

  if (edit.range) {
    push_range(L, *edit.range);
    lua_setfield(L, -2, "range");
  }

  if (edit.insert) {
    push_range(L, *edit.insert);
    lua_setfield(L, -2, "insert");
  }

  if (edit.replace) {
    push_range(L, *edit.replace);
    lua_setfield(L, -2, "replace");
  }
}

void push_completion_item(lua_State* L, const CompletionItem& item) {
  lua_newtable(L);
  lua_pushstring(L, item.label.c_str());
  lua_setfield(L, -2, "label");
  if (item.kind) {
    lua_pushinteger(L, *item.kind);
    lua_setfield(L, -2, "kind");
  }
  if (item.detail) {
    lua_pushstring(L, item.detail->c_str());
    lua_setfield(L, -2, "detail");
  }
  if (item.sort_text) {
    lua_pushstring(L, item.sort_text->c_str());
    lua_setfield(L, -2, "sortText");
  }
  if (item.filter_text) {
    lua_pushstring(L, item.filter_text->c_str());
    lua_setfield(L, -2, "filterText");
  }
  if (item.insert_text) {
    lua_pushstring(L, item.insert_text->c_str());
    lua_setfield(L, -2, "insertText");
  }
  if (item.insert_text_format) {
    lua_pushinteger(L, *item.insert_text_format);
    lua_setfield(L, -2, "insertTextFormat");
  }
  if (item.text_edit) {
    push_text_edit(L, *item.text_edit);
    lua_setfield(L, -2, "textEdit");
  }
  lua_pushnumber(L, item.client_id);
  lua_setfield(L, -2, "clientId");

  lua_pushnumber(L, item.cost);
  lua_setfield(L, -2, "cost");
}

void push_completion_items(lua_State* L,
                           const std::vector<CompletionItem>& items) {
  lua_newtable(L);
  int index = 1;
  for (const auto& item : items) {
    push_completion_item(L, item);
    lua_rawseti(L, -2, index++);
  }
}

EditDistanceOption parse_edit_distance_option(lua_State* L) {
  EditDistanceOption option;
  option.keyword = get_optional_string(L, "keyword")
                       ? *get_optional_string(L, "keyword")
                       : "";

  lua_getfield(L, -1, "insert_cost");
  option.insert_cost = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);

  lua_getfield(L, -1, "delete_cost");
  option.delete_cost = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);

  lua_getfield(L, -1, "substitude_cost");
  option.substitude_cost = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);

  lua_getfield(L, -1, "max_cost");
  option.max_cost = luaL_optnumber(L, -1, 1.0);
  lua_pop(L, 1);

  // largest alpha bias toward prefix
  lua_getfield(L, -1, "alpha");
  option.alpha = luaL_optinteger(L, -1, 2);
  lua_pop(L, 1);

  // prefer longer prefix matched
  lua_getfield(L, -1, "beta");
  option.beta = luaL_optnumber(L, -1, 2.0);
  lua_pop(L, 1);

  // penalize for long completion
  lua_getfield(L, -1, "gamma");
  option.gamma = luaL_optnumber(L, -1, 0.1);
  lua_pop(L, 1);

  return option;
}

CompletionParam parse_completion_param(lua_State* L) {
  CompletionParam param;

  lua_getfield(L, -1, "line");
  param.line = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);

  lua_getfield(L, -1, "start");
  param.start = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);

  lua_getfield(L, -1, "cursor");
  param.cursor = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);

  return param;
}

std::pair<int, bool> edit_distance(const std::string& s1,
                                   const EditDistanceOption& option) {
  const std::string& s2 = option.keyword;
  const int insert_cost = option.insert_cost;
  const int delete_cost = option.delete_cost;
  const int substitude_cost = option.substitude_cost;

  const size_t len1 = s1.length();
  const size_t len2 = s2.length();

  std::vector<int> dp(len2 + 1);
  std::vector<int> next_dp(len2 + 1);
  for (size_t j = 0; j <= len2; ++j) {
    dp[j] = j * insert_cost;
  }

  for (size_t i = 1; i <= len1; ++i) {
    next_dp[0] = i * delete_cost;
    for (size_t j = 1; j <= len2; ++j) {
      int weight = option.alpha * (1 - std::min(i, j) / std::max(len1, len2));
      if (tolower(s1[i - 1]) == tolower(s2[j - 1])) {
        next_dp[j] = dp[j - 1];
      } else {
        next_dp[j] =
            std::min({dp[j] + delete_cost + weight,            // Deletion
                      next_dp[j - 1] + insert_cost + weight,   // Insertion
                      dp[j - 1] + substitude_cost + weight});  // Substitution
      }
    }
    dp = next_dp;
  }
  bool is_subseq = false;
  if (len2 > 0) {
    for (size_t i = 0, j = 0; i < len1; ++i) {
      if (tolower(s1[i]) == tolower(s2[j])) {
        j++;
      }
      if (j == len2) {
        is_subseq = true;
        break;
      }
    }
  } else {
    is_subseq = true;
  }
  return {dp[len2], is_subseq};
}

struct CompareCompletionItem {
  bool operator()(const CompletionItem& a, const CompletionItem& b) {
    int format_a = a.insert_text_format ? *a.insert_text_format : 1;
    int format_b = b.insert_text_format ? *b.insert_text_format : 1;
    if (format_a == format_b) {
      double cost_a = a.cost;
      double cost_b = b.cost;

      if (cost_a != cost_b) {
        return cost_a < cost_b;
      }

      if (a.sort_text && b.sort_text) {
        return *a.sort_text < *b.sort_text;
      }
      return a.label < b.label;
    }
    return format_a > format_b;
  }
};

std::string& get_text(CompletionItem& item) {
  if (item.filter_text) {
    return *item.filter_text;
  }
  if (item.insert_text) {
    return *item.insert_text;
  }
  return item.label;
}

void set_text_edit(std::vector<CompletionItem>& items, CompletionParam& param) {
  for (auto& item : items) {
    if (!item.text_edit.has_value()) {
      TextEdit te;
      te.new_text = get_text(item);
      Position start = {param.line, param.start};
      Position end = {param.line, param.cursor};
      te.range = Range{start, end};
      item.text_edit = std::optional(te);
    } else {
      if (item.text_edit->range) {
        item.text_edit->range->end.character = param.cursor;
      }
      if (item.text_edit->insert) {
        item.text_edit->insert->end.character = param.cursor;
      }
      if (item.text_edit->replace) {
        item.text_edit->replace->end.character = param.cursor;
      }
    }
  }
}

int longest_common_prefix(const std::string& s1, const std::string& s2) {
  int n = std::min(s1.length(), s2.length());
  for (int i = 0; i < n; ++i) {
    if (s1[i] != s2[i]) {
      return i;
    }
  }
  return n;
}

double compute_cost(const std::string& text, int dist,
                    EditDistanceOption& option) {
  if (option.keyword.length() == 0 && text.length() == 0) {
    return std::numeric_limits<int>::max();
  }
  int C = std::max(
      {option.substitude_cost, option.insert_cost, option.delete_cost});
  double P = longest_common_prefix(text, option.keyword);
  double W = std::max(option.keyword.length(), text.length());
  int L = option.keyword.length();
  double cost = (double)dist / (W * C) - (L == 0 ? 0 : option.beta * (P / L)) +
                (option.gamma * text.length() / W);
  return cost;
}

int lua_find_trigger_context(lua_State* L) {
  if (lua_istable(L, 1)) {
    std::string line = luaL_checkstring(L, 2);
    int start = luaL_checkint(L, 3);
    const char c = start >= 0 ? line[start] : '\0';

    lua_pushnil(L);

    std::string trigger_char;
    while (lua_next(L, 1) != 0) {
      // Key is at index -2, value at -1
      if (lua_isstring(L, -1)) {
        const char* value = lua_tostring(L, -1);
        if (value && c == value[0]) {
          if (trigger_char.empty()) {
            trigger_char.push_back(c);
          }
        }
      }
      lua_pop(L, 1);
    }

    if (!trigger_char.empty()) {
      lua_newtable(L);
      lua_pushstring(L, trigger_char.c_str());
      lua_setfield(L, -2, "triggerCharacter");
      lua_pushinteger(L, TriggerCharacter);
      lua_setfield(L, -2, "triggerKind");
    } else {
      lua_pushnil(L);
    }
  } else {
    lua_pushnil(L);
  }
  return 1;
}

Cat::Cat() : state_(CatState::NORMAL), counter_(0), last_interact_(std::chrono::system_clock::now()) {
}

void Cat::Interact() {
  auto t = std::chrono::system_clock::now();
  auto d = t - last_interact_;
  if (d >= std::chrono::minutes(5)) {
    state_ = CatState::CRYING;
    counter_ = 0;
  } else {
    if (state_ == CatState::NORMAL) {
      if (++counter_ >= 3) {
        state_ = CatState::SMILE;
        counter_ = 0;
      }
    } else if (state_ == CatState::SMILE) {
      if (++counter_ >= 5) {
        state_ = CatState::HAPPY;
        counter_ = 0;
      }
    } else if (state_ == CatState::HAPPY) {
      if (++counter_ >= 10) {
        state_ = CatState::KISSING;
        counter_ = 0;
      }
    } else if (state_ == CatState::KISSING) {
      if (++counter_ >= 2) {
        state_ = CatState::NORMAL;
        counter_ = 0;
      }
    } else if (state_ == CatState::WRY) {
      if (++counter_ >= 3) {
        state_ = CatState::NORMAL;
        counter_ = 0;
      }
    } else if (state_ == CatState::POUTING) {
      if (++counter_ >= 3) {
        state_ = CatState::WRY;
        counter_ = 0;
      }
    } else if (state_ == CatState::CRYING) {
      if (++counter_ >= 3) {
        state_ = CatState::POUTING;
        counter_ = 0;
      }
    }
  }
  last_interact_ = t;
}

std::string Cat::get_emoji() const {
  if (state_ == CatState::NORMAL) {
    return u8"🐱";
  } else if (state_ == CatState::SMILE) {
    return u8"😺";
  } else if (state_ == CatState::HAPPY) {
    return u8"😸";
  } else if (state_ == CatState::KISSING) {
    return u8"😽";
  } else if (state_ == CatState::WRY) {
    return u8"😼";
  } else if (state_ == CatState::POUTING) {
    return u8"😾";
  } else if (state_ == CatState::CRYING) {
    return u8"😿";
  }
  return "";
}

static Context context;

int lua_clear_items(lua_State*) {
  context.completion_items.clear();
  return 0;
}

/**
 * param1: list of items
 * param2: client_id
 * param3: bufnr
 * param4: line (1-indexed)
 * param5: col (1-indexed)
 */
int lua_insert_items(lua_State* L) {
  std::lock_guard<std::mutex> lock(context.mutex);

  luaL_checktype(L, 1, LUA_TTABLE);
  lua_pushvalue(L, 1);
  std::vector<CompletionItem> items = parse_completion_items(L);
  lua_pop(L, 1);

  int client_id = luaL_checkint(L, 2);
  int bufnr = luaL_checkint(L, 3);
  int line = luaL_checkint(L, 4);
  int col = luaL_checkint(L, 5);
  CacheKey key{bufnr, line, col};

  std::vector<CompletionItem>& completion_items = context.completion_items.get(key);
  for (auto& item : items) {
    item.client_id = client_id;
    completion_items.push_back(std::move(item));
  }
  return 0;
}

int lua_interact(lua_State*) {
  std::lock_guard<std::mutex> lock(context.mutex);
  context.cat.Interact();
  return 0;
}

int lua_cat_emoji(lua_State* L) {
  std::string emoji = context.cat.get_emoji();
  lua_pushstring(L, emoji.c_str());
  return 1;
}

/**
 * param1: bufnr
 * param2: line (1-indexed)
 * param3: col (1-indexed)
 * param4: start (1-indexed)
 * param5: edit distance option
 */
int lua_get_completion_items(lua_State* L) {
  int bufnr = luaL_checkinteger(L, 1);
  int line = luaL_checkinteger(L, 2);
  int col = luaL_checkinteger(L, 3);
  int start = luaL_checkinteger(L, 4);
  luaL_checktype(L, 5, LUA_TTABLE);

  CacheKey key{bufnr, line, col};

  lua_pushvalue(L, 5);
  EditDistanceOption option = parse_edit_distance_option(L);
  lua_pop(L, 1);

  std::vector<CompletionItem>& items = context.completion_items.get(key);

  for (auto& item : items) {
    std::string& text = get_text(item);
    auto [dist, is_subseq] = edit_distance(text, option);
    item.cost = compute_cost(text, dist, option);
    item.is_subseq = is_subseq;
  }

  if (!items.empty()) {
    double max_cost = items[0].cost;
    double min_cost = items[0].cost;
    for (size_t i = 1; i < items.size(); ++i) {
      max_cost = fmax(max_cost, items[i].cost);
      min_cost = fmin(min_cost, items[i].cost);
    }
    double range = max_cost - min_cost;
    for (size_t i = 0; i < items.size(); ++i) {
      items[i].cost = (items[i].cost - min_cost) / range * MAX_STARS;
    }
  }

  std::vector<CompletionItem> output;
  for (auto& item : items) {
    if (item.is_subseq) {
      output.push_back(item);
    }
  }

  for (auto& item : output) {
    if (!item.text_edit.has_value()) {
      TextEdit te;
      te.new_text = get_text(item);
      Position s = {line-1, start-1};
      Position e = {line-1, col};
      te.range = Range{s, e};
      item.text_edit = std::optional(te);
    } else {
      if (item.text_edit->range) {
        item.text_edit->range->end.character = col;
      }
      if (item.text_edit->insert) {
        item.text_edit->insert->end.character = col;
      }
      if (item.text_edit->replace) {
        item.text_edit->replace->end.character = col;
      }
    }
  }

  std::sort(output.begin(), output.end(), CompareCompletionItem());

  push_completion_items(L, output);
  return 1;
}

/**
 * param1: bufnr
 * param2: line (1-indexed)
 * param3: col (1-indexed)
 */
int lua_has_cache(lua_State* L) {
  int bufnr = luaL_checkinteger(L, 1);
  int line = luaL_checkinteger(L, 2);
  int col = luaL_checkinteger(L, 3);

  CacheKey key{bufnr, line, col};

  bool has_value = context.completion_items.has_value(key);
  lua_pushboolean(L, has_value);
  return 1;
}

int lua_clear_completion_items(lua_State*) {
  context.completion_items.clear();
  return 0;
}

int lua_get_stars(lua_State* L) {
  double cost = luaL_checknumber(L, 1);
  double p = (1.0 - cost) * 5;
  std::string star = "⭐";
  std::string stars;
  int i = 0;
  while (i <= p) {
    stars += star;
    i++;
  }

  lua_pushstring(L, stars.c_str());
  return 1;
}

std::string abbreviate(const std::string& str, size_t length) {
  std::string s = trim(str);
  if (length < 3) {
    return s.substr(0, std::min(s.length(), length));
  }

  if (s.length() <= length) {
    return s;
  }

  size_t content_length = length - 3;
  return s.substr(0, content_length) + "...";
}

std::string format_completion_item(const std::string& symbol,
                                   const std::string& label,
                                   const std::string& detail,
                                   size_t symbol_width, size_t label_width,
                                   size_t detail_width) {
  return absl::StrFormat(" %*s  %-*s %*s",
                         symbol_width, symbol,
                         label_width, abbreviate(label, label_width-3),
                         detail_width, abbreviate(detail, detail_width));
}

int lua_format_completion_item(lua_State* L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  lua_pushvalue(L, 1);

  lua_getfield(L, -1, "symbol");
  std::string symbol = lua_tostring(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, -1, "label");
  std::string label = lua_tostring(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, -1, "detail");
  std::string detail = lua_tostring(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, -1, "symbol_width");
  size_t symbol_width = lua_tointeger(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, -1, "label_width");
  size_t label_width = lua_tointeger(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, -1, "detail_width");
  size_t detail_width = lua_tointeger(L, -1);
  lua_pop(L, 1);

  std::string output = format_completion_item(
      symbol, label, detail, symbol_width, label_width, detail_width);

  lua_pop(L, 1);

  lua_pushstring(L, output.c_str());
  return 1;
}

// paw module
extern "C" int luaopen_paw(lua_State* L) {
  lua_newtable(L);

  lua_pushcfunction(L, lua_trim_long_text);
  lua_setfield(L, -2, "trim_long_text");

  lua_pushcfunction(L, lua_is_whitespace);
  lua_setfield(L, -2, "is_whitespace");

  lua_pushcfunction(L, lua_find_last_word_index);
  lua_setfield(L, -2, "find_last_word_index");

  lua_pushcfunction(L, lua_find_last_trigger_index);
  lua_setfield(L, -2, "find_last_trigger_index");

  lua_pushcfunction(L, lua_table_get);
  lua_setfield(L, -2, "table_get");

  lua_pushcfunction(L, lua_find_trigger_context);
  lua_setfield(L, -2, "find_trigger_context");

  lua_pushcfunction(L, lua_interact);
  lua_setfield(L, -2, "interact");

  lua_pushcfunction(L, lua_cat_emoji);
  lua_setfield(L, -2, "cat_emoji");

  lua_pushcfunction(L, lua_insert_items);
  lua_setfield(L, -2, "insert_items");

  lua_pushcfunction(L, lua_get_completion_items);
  lua_setfield(L, -2, "get_completion_items");

  lua_pushcfunction(L, lua_has_cache);
  lua_setfield(L, -2, "has_cache");

  lua_pushcfunction(L, lua_clear_completion_items);
  lua_setfield(L, -2, "clear_completion_items");

  lua_pushcfunction(L, lua_get_stars);
  lua_setfield(L, -2, "get_stars");

  lua_pushcfunction(L, lua_format_completion_item);
  lua_setfield(L, -2, "format_completion_item");
  return 1;
}
