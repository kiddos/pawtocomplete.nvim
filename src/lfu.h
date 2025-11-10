#ifndef LFU_H
#define LFU_H

#include <absl/container/flat_hash_map.h>

#include <list>

template <typename T, typename U, typename F, int SIZE>
class LFU {
 public:
  LFU() : min_freq_(0), cache_(SIZE) {}

  void put(const T& key, U&& value) {
    if (cache_.count(key)) {
      cache_[key].second->second = std::move(value);
      increase_use_count(key);
    } else {
      if ((int)cache_.size() == SIZE) {
        auto it = data_[min_freq_].begin();
        auto key_to_evict = it->first;
        cache_.erase(key_to_evict);
        data_[min_freq_].erase(it);
      }

      data_[1].push_back({key, std::move(value)});
      auto it = prev(data_[1].end());
      cache_[key] = {1, it};
      min_freq_ = 1;
    }
  }

  bool has_value(const T& key) { return cache_.count(key); }

  U& get(const T& key) {
    if (!cache_.count(key)) {
      put(key, U{});
    }
    increase_use_count(key);
    return cache_[key].second->second;
  }

  void remove(const T& key) {
    if (!cache_.count(key)) {
      return;
    }

    int freq = cache_[key].first;
    auto it = cache_[key].second;
    data_[freq].erase(it);
    cache_.erase(key);

    if (freq == min_freq_ && data_[freq].empty()) {
      min_freq_++;
    }
  }

  void clear() {
    min_freq_ = 0;
    data_.clear();
    cache_.clear();
  }

 private:
  int min_freq_;
  absl::flat_hash_map<int, std::list<std::pair<T, U>>> data_;
  absl::flat_hash_map<
      T, std::pair<int, typename std::list<std::pair<T, U>>::iterator>, F>
      cache_;

  void increase_use_count(const T& key) {
    int freq = cache_[key].first;
    auto it = cache_[key].second;
    std::pair<T, U> new_p = *it;
    data_[freq].erase(it);
    data_[freq + 1].push_back(new_p);
    cache_[key] = {freq + 1, prev(data_[freq + 1].end())};
    if (freq == min_freq_ && data_[freq].empty()) {
      min_freq_++;
    }
  }
};

#endif /* end of include guard: LFU_H */
