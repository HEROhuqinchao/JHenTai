import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/model/search_history.dart';
import 'package:jhentai/src/service/storage_service.dart';
import 'package:jhentai/src/service/tag_translation_service.dart';

import '../database/database.dart';
import '../utils/log.dart';

class SearchHistoryService extends GetxService {
  StorageService storageService = Get.find();
  TagTranslationService tagTranslationService = Get.find();

  List<SearchHistory> histories = [];

  static const _maxLength = 50;

  static void init() {
    Get.put(SearchHistoryService(), permanent: true);
  }

  @override
  Future<void> onInit() async {
    super.onInit();

    List searchHistories = storageService.read(ConfigEnum.searchConfig.key) ?? <String>[];
    for (String searchHistory in searchHistories) {
      histories.add(
        SearchHistory(
          rawKeyword: searchHistory,
          translatedKeyword: tagTranslationService.isReady ? await translateSearchHistory(searchHistory) : null,
        ),
      );
    }

    Log.debug('init SearchHistoryService success');
  }

  Future<void> writeHistory(String searchHistory) async {
    histories.removeWhere((history) => history.rawKeyword == searchHistory);
    histories.insert(
      0,
      SearchHistory(
        rawKeyword: searchHistory,
        translatedKeyword: tagTranslationService.isReady ? await translateSearchHistory(searchHistory) : null,
      ),
    );

    if (histories.length > _maxLength) {
      histories = histories.sublist(0, _maxLength);
    }

    storageService.write(ConfigEnum.searchHistory.key, histories.map((history) => history.rawKeyword).toList());
  }

  Future<void> deleteHistory(SearchHistory searchHistory) async {
    if (histories.remove(searchHistory)) {
      storageService.write(ConfigEnum.searchHistory.key, histories.map((history) => history.rawKeyword).toList());
    }
  }

  Future<void> clearHistory() async {
    histories.clear();
    await storageService.remove(ConfigEnum.searchHistory.key);
  }

  /// find each pair and then translate, remains the parts which can't be translated
  Future<String> translateSearchHistory(String searchHistory) async {
    List<RegExpMatch> matches = RegExp(r'(\w+):"([^"]+)\$"').allMatches(searchHistory).toList();
    if (matches.isEmpty) {
      return searchHistory;
    }

    String result = '';
    int index = 0;
    int matchIndex = 0;
    while (index < searchHistory.length) {
      if (matchIndex >= matches.length) {
        result += searchHistory.substring(index);
        break;
      }

      if (index < matches[matchIndex].start) {
        result += searchHistory.substring(index, matches[matchIndex].start);
        index = matches[matchIndex].start;
        continue;
      }

      if (index == matches[matchIndex].start) {
        String namespace = matches[matchIndex].group(1)!;
        String key = matches[matchIndex].group(2)!;
        TagData? tagData = await tagTranslationService.getTagTranslation(namespace, key);

        if (tagData == null) {
          result += searchHistory.substring(matches[matchIndex].start, matches[matchIndex].end);
        } else {
          result += '｢${tagData.translatedNamespace}:${tagData.tagName}｣';
        }

        index = matches[matchIndex].end;
        matchIndex++;
        continue;
      }
    }

    return result;
  }
}
