import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/mixin/update_global_gallery_status_logic_mixin.dart';
import '../../../../database/database.dart';
import '../../../../mixin/scroll_to_top_logic_mixin.dart';
import '../../../../mixin/scroll_to_top_state_mixin.dart';
import '../../../../setting/performance_setting.dart';
import '../../mixin/archive/archive_download_page_logic_mixin.dart';
import '../../mixin/archive/archive_download_page_state_mixin.dart';
import '../../mixin/basic/multi_select/multi_select_download_page_logic_mixin.dart';
import 'archive_list_download_page_state.dart';

class ArchiveListDownloadPageLogic extends GetxController
    with Scroll2TopLogicMixin, MultiSelectDownloadPageLogicMixin<ArchiveDownloadedData>, ArchiveDownloadPageLogicMixin, UpdateGlobalGalleryStatusLogicMixin {
  ArchiveListDownloadPageState state = ArchiveListDownloadPageState();

  @override
  Scroll2TopStateMixin get scroll2TopState => state;

  @override
  ArchiveDownloadPageStateMixin get archiveDownloadPageState => state;

  late Worker maxGalleryNum4AnimationListener;

  @override
  void onInit() {
    super.onInit();

    state.displayGroups = Set.from(storageService.read(ConfigEnum.displayArchiveGroups.key) ?? ['default'.tr]);

    maxGalleryNum4AnimationListener = ever(PerformanceSetting.maxGalleryNum4Animation, (_) => updateSafely([bodyId]));
  }

  @override
  void onClose() {
    super.onClose();

    maxGalleryNum4AnimationListener.dispose();
  }

  void toggleDisplayGroups(String groupName) {
    if (state.displayGroups.contains(groupName)) {
      state.displayGroups.remove(groupName);
    } else {
      state.displayGroups.add(groupName);
    }

    storageService.write(ConfigEnum.displayArchiveGroups.name, state.displayGroups.toList());
    state.groupedListController.toggleGroup(groupName);
  }

  @override
  Future<void> doRenameGroup(String oldGroup, String newGroup) async {
    state.displayGroups.remove(oldGroup);
    return super.doRenameGroup(oldGroup, newGroup);
  }

  @override
  void handleRemoveItem(ArchiveDownloadedData archive) {
    state.groupedListController.removeElement(archive).then((_) {
      state.selectedGids.remove(archive.gid);
      archiveDownloadService.deleteArchive(archive.gid);
      updateGlobalGalleryStatus();
    });
  }

  @override
  void handleResumeAllTasks() {
    archiveDownloadService.resumeAllDownloadArchive();
  }

  @override
  void selectAllItem() {
    List<ArchiveDownloadedData> archives = [];
    for (String group in state.displayGroups) {
      archives.addAll(archiveDownloadService.archivesWithGroup(group));
    }

    multiSelectDownloadPageState.selectedGids.addAll(archives.map((archive) => archive.gid));
    updateSafely(multiSelectDownloadPageState.selectedGids.map((gid) => '$itemCardId::$gid').toList());
  }
}
