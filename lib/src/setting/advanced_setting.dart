import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/utils/log.dart';

import '../service/storage_service.dart';

class AdvancedSetting {
  static RxBool enableLogging = true.obs;
  static RxBool enableVerboseLogging = kDebugMode.obs;
  static RxBool enableCheckUpdate = true.obs;
  static RxBool enableCheckClipboard = true.obs;
  static RxBool inNoImageMode = false.obs;

  static Future<void> init() async {
    Map<String, dynamic>? map = Get.find<StorageService>().read<Map<String, dynamic>>(ConfigEnum.advancedSetting.key);
    if (map != null) {
      _initFromMap(map);
      Log.debug('init AdvancedSetting success', false);
    } else {
      Log.debug('init AdvancedSetting success: default', false);
    }
  }

  static saveEnableLogging(bool enableLogging) {
    Log.debug('saveEnableLogging:$enableLogging');
    AdvancedSetting.enableLogging.value = enableLogging;
    _save();
  }

  static saveEnableVerboseLogging(bool enableVerboseLogging) {
    Log.debug('saveEnableVerboseLogging:$enableVerboseLogging');
    AdvancedSetting.enableVerboseLogging.value = enableVerboseLogging;
    _save();
  }

  static saveEnableCheckUpdate(bool enableCheckUpdate) {
    Log.debug('saveEnableCheckUpdate:$enableCheckUpdate');
    AdvancedSetting.enableCheckUpdate.value = enableCheckUpdate;
    _save();
  }

  static saveEnableCheckClipboard(bool enableCheckClipboard) {
    Log.debug('saveEnableCheckClipboard:$enableCheckClipboard');
    AdvancedSetting.enableCheckClipboard.value = enableCheckClipboard;
    _save();
  }

  static saveInNoImageMode(bool inNoImageMode) {
    Log.debug('saveInNoImageMode:$inNoImageMode');
    AdvancedSetting.inNoImageMode.value = inNoImageMode;
    _save();
  }

  static Future<void> _save() async {
    await Get.find<StorageService>().write(ConfigEnum.advancedSetting.key, _toMap());
  }

  static Map<String, dynamic> _toMap() {
    return {
      'enableLogging': enableLogging.value,
      'enableVerboseLogging': enableVerboseLogging.value,
      'enableCheckUpdate': enableCheckUpdate.value,
      'enableCheckClipboard': enableCheckClipboard.value,
      'inNoImageMode': inNoImageMode.value,
    };
  }

  static _initFromMap(Map<String, dynamic> map) {
    enableLogging.value = map['enableLogging'];
    enableVerboseLogging.value = map['enableVerboseLogging'] ?? enableVerboseLogging.value;
    enableCheckUpdate.value = map['enableCheckUpdate'] ?? enableCheckUpdate.value;
    enableCheckClipboard.value = map['enableCheckClipboard'] ?? enableCheckClipboard.value;
    inNoImageMode.value = map['inNoImageMode'] ?? inNoImageMode.value;
  }
}
