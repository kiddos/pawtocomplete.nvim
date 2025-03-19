extern "C" {
#include <string.h>

#include "lauxlib.h"
#include "lua.h"
}

#include <algorithm>
#include <vector>

#include "paw.h"

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

int lua_trim(lua_State* L) {
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

bool is_word_char(char c) { return isalnum(c) || c == '_'; }

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
    lua_pushinteger(L, i);  // Push the index i
    lua_gettable(L, 2);     // Get id[i]

    lua_pushvalue(L, -2);  // Push the current table (res)
    lua_pushvalue(L, -2);  // Push id[i] again

    lua_gettable(L, -2);  // Get res[id[i]]

    if (lua_isnil(L, -1)) {
      lua_pushnil(L);
      return 1;
    }

    lua_replace(L, -3);  // Replace the old res with the new res[id[i]]
    lua_pop(L, 1);       // Pop id[i]
  }

  lua_replace(L, 1);  // replace the original table with the result.
  lua_settop(L, 1);   // Keep only the result on the stack.
  return 1;
}

CompletionItemKind get_completion_item_kind(lua_State* L, const char* key) {
  lua_getfield(L, -1, key);
  CompletionItemKind kind =
      static_cast<CompletionItemKind>(luaL_optinteger(L, -1, 1));
  lua_pop(L, 1);
  return kind;
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
  if (item.text_edit) {
    push_text_edit(L, *item.text_edit);
    lua_setfield(L, -2, "textEdit");
  }
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
  option.max_cost = luaL_optnumber(L, -1, 2.0);
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

  const size_t len1 = s1.size();
  const size_t len2 = s2.size();

  std::vector<std::vector<int>> dp(len1 + 1, std::vector<int>(len2 + 1, 0));

  for (size_t i = 0; i <= len1; ++i) {
    dp[i][0] = i * delete_cost;
  }
  for (size_t j = 0; j <= len2; ++j) {
    dp[0][j] = j * insert_cost;
  }

  bool match_once = false;
  for (size_t i = 1; i <= len1; ++i) {
    for (size_t j = 1; j <= len2; ++j) {
      if (s1[i - 1] == s2[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
        match_once = true;
      } else {
        dp[i][j] =
            std::min({dp[i - 1][j] + delete_cost,            // Deletion
                      dp[i][j - 1] + insert_cost,            // Insertion
                      dp[i - 1][j - 1] + substitude_cost});  // Substitution
      }
    }
  }
  return {dp[len1][len2], match_once};
}

struct CompareCompletionItem {
  bool operator()(const CompletionItem& a, const CompletionItem& b) {
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
};


std::string& get_text(CompletionItem& item) {
  return item.insert_text   ? *item.insert_text
                      : item.filter_text ? *item.filter_text
                                          : item.label;
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

int lua_filter_and_sort(lua_State* L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  luaL_checktype(L, 2, LUA_TTABLE);
  luaL_checktype(L, 3, LUA_TTABLE);

  lua_pushvalue(L, 1);
  std::vector<CompletionItem> items = parse_completion_items(L);
  lua_pop(L, 1);

  lua_pushvalue(L, 2);
  EditDistanceOption option = parse_edit_distance_option(L);
  lua_pop(L, 1);

  lua_pushvalue(L, 3);
  CompletionParam param = parse_completion_param(L);
  lua_pop(L, 1);

  for (auto& item : items) {
    std::string& text = get_text(item);
    auto [cost, match_once] = edit_distance(text, option);
    item.cost = option.keyword.length() == 0
                    ? std::numeric_limits<int>::max()
                    : (double)cost / option.keyword.length();
    item.match_once = match_once;
  }

  std::vector<CompletionItem> output;
  if (option.keyword.empty()) {
    for (auto& item : items) {
      if (item.kind != CompletionItemKind::Text && item.kind != CompletionItemKind::Snippet) {
        output.push_back(item);
      }
    }
  } else {
    for (auto& item : items) {
      if (item.match_once && item.cost <= option.max_cost) {
        output.push_back(item);
      }
    }
  }

  set_text_edit(output, param);
  std::sort(output.begin(), output.end(), CompareCompletionItem());

  push_completion_items(L, output);
  return 1;
}

std::string get_emoji(CatState state) {
  if (state == CatState::NORMAL) {
    return u8"🐱";
  } else if (state == CatState::SMILE) {
    return u8"😺";
  } else if (state == CatState::HAPPY) {
    return u8"😸";
  } else if (state == CatState::KISSING) {
    return u8"😽";
  } else if (state == CatState::WRY) {
    return u8"😼";
  } else if (state == CatState::POUTING) {
    return u8"😾";
  } else if (state == CatState::CRYING) {
    return u8"😿";
  }
  return "";
}

void interact(Cat& cat) {
  auto t = std::chrono::system_clock::now();
  auto d = t - cat.last_interact;
  if (d >= std::chrono::minutes(5)) {
    cat.state = CatState::CRYING;
    cat.counter = 0;
  } else {
    if (cat.state == CatState::NORMAL) {
      if (++cat.counter >= 3) {
        cat.state = CatState::SMILE;
        cat.counter = 0;
      }
    } else if (cat.state == CatState::SMILE) {
      if (++cat.counter >= 5) {
        cat.state = CatState::HAPPY;
        cat.counter = 0;
      }
    } else if (cat.state == CatState::HAPPY) {
      if (++cat.counter >= 10) {
        cat.state = CatState::KISSING;
        cat.counter = 0;
      }
    } else if (cat.state == CatState::KISSING) {
      if (++cat.counter >= 2) {
        cat.state = CatState::NORMAL;
        cat.counter = 0;
      }
    } else if (cat.state == CatState::WRY) {
      if (++cat.counter >= 3) {
        cat.state = CatState::NORMAL;
        cat.counter = 0;
      }
    } else if (cat.state == CatState::POUTING) {
      if (++cat.counter >= 3) {
        cat.state = CatState::WRY;
        cat.counter = 0;
      }
    } else if (cat.state == CatState::CRYING) {
      if (++cat.counter >= 3) {
        cat.state = CatState::POUTING;
        cat.counter = 0;
      }
    }
  }
  cat.last_interact = t;
}

Cat init_cat() {
  return Cat{
    .state = CatState::NORMAL,
    .counter = 0,
    .last_interact = std::chrono::system_clock::now(),
  };
}

static Cat cat = init_cat();
static Context context{cat};

int lua_interact(lua_State*) {
  interact(context.cat);
  return 0;
}

int lua_cat_emoji(lua_State* L) {
  std::string emoji = get_emoji(context.cat.state);
  lua_pushstring(L, emoji.c_str());
  return 1;
}

// paw module
extern "C" int luaopen_paw(lua_State* L) {
  lua_newtable(L);

  lua_pushcfunction(L, lua_trim);
  lua_setfield(L, -2, "trim_long_text");

  lua_pushcfunction(L, lua_is_whitespace);
  lua_setfield(L, -2, "is_whitespace");

  lua_pushcfunction(L, lua_find_last_word_index);
  lua_setfield(L, -2, "find_last_word_index");

  lua_pushcfunction(L, lua_find_last_trigger_index);
  lua_setfield(L, -2, "find_last_trigger_index");

  lua_pushcfunction(L, lua_table_get);
  lua_setfield(L, -2, "table_get");

  lua_pushcfunction(L, lua_filter_and_sort);
  lua_setfield(L, -2, "filter_and_sort");

  lua_pushcfunction(L, lua_interact);
  lua_setfield(L, -2, "interact");

  lua_pushcfunction(L, lua_cat_emoji);
  lua_setfield(L, -2, "cat_emoji");
  return 1;
}
