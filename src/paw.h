#ifndef PAW_H
#define PAW_H

#include <chrono>
#include <string>
#include <optional>

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
  double max_cost;
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

#endif /* end of include guard: PAW_H */
