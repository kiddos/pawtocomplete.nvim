#ifndef PAW_H
#define PAW_H

#include <chrono>
#include <functional>
#include <optional>
#include <string>
#include <vector>

enum CompletionItemKind {
  Text = 1,
  Method = 2,
  Function = 3,
  Constructor = 4,
  Field = 5,
  Variable = 6,
  Class = 7,
  Interface = 8,
  Module = 9,
  Property = 10,
  Unit = 11,
  Value = 12,
  Enum = 13,
  Keyword = 14,
  Snippet = 15,
  Color = 16,
  File = 17,
  Reference = 18,
  Folder = 19,
  EnumMember = 20,
  Constant = 21,
  Struct = 22,
  Event = 23,
  Operator = 24,
  TypeParameter = 25,
};

enum CompletionTriggerKind {
  Invoked = 1,
  TriggerCharacter = 2,
  TriggerForIncompleteCompletions = 3,
};

struct Position {
  int line;
  int character;
};

struct Range {
  Position start;
  Position end;
};

struct TextEdit {
  std::string new_text;
  std::optional<Range> range;
  std::optional<Range> insert;
  std::optional<Range> replace;
};

struct CompletionItem {
  std::string label;
  std::optional<CompletionItemKind> kind;
  std::optional<std::string> detail;
  std::optional<std::string> sort_text;
  std::optional<std::string> filter_text;
  std::optional<std::string> insert_text;
  std::optional<TextEdit> text_edit;
  double cost;
  bool match_once;
};

struct EditDistanceOption {
  std::string keyword;
  int insert_cost;
  int delete_cost;
  int substitude_cost;
  int alpha;
  double max_cost;
  double beta;
  double gamma;
};

struct CompletionParam {
  int line;
  int start;
  int cursor;
};

enum CatState {
  NORMAL,
  SMILE,
  HAPPY,
  KISSING,
  WRY,
  POUTING,
  CRYING,
};

struct Cat {
  CatState state;
  int counter;
  std::chrono::time_point<std::chrono::system_clock> last_interact;
};

struct Context {
  Cat cat;
};

struct CacheKey {
  int bufnr;
  int line;
  int col;
  std::string word;

  bool operator==(const CacheKey& key) const {
    return bufnr == key.bufnr && line == key.line && col == key.col &&
           word == key.word;
  }

  template <typename H>
  friend H AbslHashValue(H h, const CacheKey& key) {
    return H::combine(std::move(h), key.bufnr, key.line, key.col, key.word);
  }
};

struct HashCacheKey {
  size_t operator()(const CacheKey& key) const {
    return std::hash<int>()(key.bufnr) ^ std::hash<int>()(key.line) ^
           std::hash<int>()(key.col) ^ std::hash<std::string>()(key.word);
  }
};

struct DataItem {
  CacheKey key;
  std::vector<CompletionItem> items;
};

#endif /* end of include guard: PAW_H */
