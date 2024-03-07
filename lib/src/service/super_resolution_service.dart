import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/extension/dio_exception_extension.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/network/eh_request.dart';
import 'package:jhentai/src/setting/super_resolution_setting.dart';
import 'package:jhentai/src/utils/table.dart';
import 'package:path/path.dart';
import 'package:retry/retry.dart';

import '../model/gallery_image.dart';
import '../setting/path_setting.dart';
import '../utils/archive_util.dart';
import '../utils/eh_executor.dart';
import '../utils/log.dart';
import '../utils/toast_util.dart';
import '../widget/loading_state_indicator.dart';
import 'archive_download_service.dart';
import 'gallery_download_service.dart';

class SuperResolutionService extends GetxController {
  static const String downloadId = 'downloadId';
  static const String superResolutionId = 'superResolutionId';
  static const String superResolutionImageId = 'superResolutionImageId';

  LoadingState downloadState = LoadingState.idle;
  String downloadProgress = '0%';

  EHExecutor executor = EHExecutor(concurrency: 1);

  final GalleryDownloadService galleryDownloadService = Get.find();
  final ArchiveDownloadService archiveDownloadService = Get.find();

  Table<int, SuperResolutionType, SuperResolutionInfo> superResolutionInfoTable = Table();

  static const String imageDirName = 'super_resolution';

  static void init() {
    Get.put(SuperResolutionService(), permanent: true);
    Log.debug('init SuperResolutionService success', false);
  }

  @override
  void onInit() async {
    if (!await galleryDownloadService.completed) {
      return;
    }
    if (!await archiveDownloadService.completed) {
      return;
    }

    List<SuperResolutionInfoData> superResolutionInfoDatas = await _selectAllSuperResolutionInfo();
    for (SuperResolutionInfoData data in superResolutionInfoDatas) {
      superResolutionInfoTable.put(
        data.gid,
        SuperResolutionType.values[data.type],
        SuperResolutionInfo(
          SuperResolutionType.values[data.type],
          SuperResolutionStatus.values[data.status],
          data.imageStatuses
              .split(SuperResolutionInfo.imageStatusesSeparator)
              .map((e) => int.parse(e))
              .map((index) => SuperResolutionStatus.values[index])
              .toList(),
        ),
      );
    }

    _checkInfoSourceExists();

    Future.wait(superResolutionInfoTable
        .entries()
        .where((e) => e.value.status == SuperResolutionStatus.running)
        .map((e) => executor.scheduleTask(0, () => _doSuperResolve(e.key1, e.key2)))
        .toList());
    super.onInit();
  }

  SuperResolutionInfo? get(int gid, SuperResolutionType type) => superResolutionInfoTable.get(gid, type);

  Future<void> downloadModelFile(ModelType model) async {
    String downloadUrl;

    if (GetPlatform.isWindows) {
      downloadUrl = model.windowsDownloadUrl;
    } else if (GetPlatform.isMacOS) {
      downloadUrl = model.macDownloadUrl;
    } else if (GetPlatform.isLinux) {
      downloadUrl = model.linuxDownloadUrl;
    } else {
      toast('error'.tr);
      return;
    }

    downloadProgress = '0%';
    downloadState = LoadingState.loading;
    updateSafely([downloadId]);

    final String modelDownloadPath = join(PathSetting.getVisibleDir().path, '${model.type}.zip');
    final String extractPath = join(PathSetting.getVisibleDir().path, model.type);

    try {
      await retry(
        () => EHRequest.download(
          url: downloadUrl,
          path: modelDownloadPath,
          receiveTimeout: 10 * 60 * 1000,
          onReceiveProgress: (count, total) {
            downloadProgress = (count / total * 100).toStringAsFixed(2) + '%';
            updateSafely([downloadId]);
          },
        ),
        maxAttempts: 5,
        onRetry: (error) => Log.warning('Download super-resolution model failed, retry.'),
      );
    } on DioException catch (e) {
      Log.error('Download super-resolution model failed after 5 times', e.errorMsg);
      downloadState = LoadingState.error;
      updateSafely([downloadId]);
      return;
    }

    Log.info('Super-resolution model downloaded, model: ${model.subType}');

    bool success = await extractZipArchive(modelDownloadPath, extractPath);

    if (!success) {
      Log.error('Unpacking Super-resolution model error!');
      Log.uploadError(Exception('Unpacking Super-resolution model error!'));
      toast('internalError'.tr);
      downloadState = LoadingState.error;
      updateSafely([downloadId]);
      return;
    }

    File(modelDownloadPath).delete();

    String dirPath;
    if (GetPlatform.isWindows) {
      dirPath = join(extractPath, model.windowsModelExtractPath);
    } else if (GetPlatform.isMacOS) {
      dirPath = join(extractPath, model.macOSModelExtractPath);
    } else if (GetPlatform.isLinux) {
      dirPath = join(extractPath, model.linuxModelExtractPath);
    } else {
      toast('error'.tr);
      return;
    }

    SuperResolutionSetting.saveModelDirectoryPath(dirPath);

    downloadState = LoadingState.success;
    updateSafely([downloadId]);
  }

  Future<bool> superResolve(int gid, SuperResolutionType type) async {
    if (type == SuperResolutionType.gallery) {
      GalleryDownloadInfo? galleryDownloadInfo = galleryDownloadService.galleryDownloadInfos[gid];
      if (galleryDownloadInfo?.downloadProgress.downloadStatus != DownloadStatus.downloaded) {
        toast('requireDownloadComplete'.tr);
        return false;
      }
    } else {
      ArchiveDownloadInfo? archiveDownloadInfo = archiveDownloadService.archiveDownloadInfos[gid];
      if (archiveDownloadInfo?.archiveStatus != ArchiveStatus.completed) {
        toast('requireDownloadComplete'.tr);
        return true;
      }
    }

    SuperResolutionInfo? superResolutionInfo = get(gid, type);
    if (superResolutionInfo?.status == SuperResolutionStatus.success) {
      return true;
    }
    if (superResolutionInfo?.status == SuperResolutionStatus.running) {
      return true;
    }

    if (superResolutionInfo == null) {
      List<GalleryImage> rawImages;
      if (type == SuperResolutionType.gallery) {
        rawImages = galleryDownloadService.galleryDownloadInfos[gid]!.images.cast();
      } else {
        rawImages = archiveDownloadService.getUnpackedImages(gid);
      }

      superResolutionInfo = SuperResolutionInfo(
        type,
        SuperResolutionStatus.running,
        List.generate(rawImages.length, (_) => SuperResolutionStatus.running),
      );
      superResolutionInfoTable.put(gid, type, superResolutionInfo);
      await _insertSuperResolutionInfo(gid, superResolutionInfo);

      Directory(dirname(computeImageOutputAbsolutePath(rawImages[0].path!))).createSync(recursive: true);

      updateSafely(['$superResolutionId::$gid']);
    }

    toast('${'startProcess'.tr}: $gid');
    executor.scheduleTask(0, () => _doSuperResolve(gid, type));
    return true;
  }

  Future<void> pauseSuperResolve(int gid, SuperResolutionType type) async {
    SuperResolutionInfo? superResolutionInfo = get(gid, type);

    if (superResolutionInfo == null ||
        superResolutionInfo.status == SuperResolutionStatus.success ||
        superResolutionInfo.status == SuperResolutionStatus.paused) {
      return;
    }

    bool? success = superResolutionInfo.currentProcess?.kill();
    Log.info('pause super resolution: $gid $success');

    superResolutionInfo.status = SuperResolutionStatus.paused;
    for (SuperResolutionStatus status in superResolutionInfo.imageStatuses) {
      if (status == SuperResolutionStatus.running) {
        status = SuperResolutionStatus.paused;
      }
    }
    await _updateSuperResolutionInfoStatus(gid, superResolutionInfo);
    updateSafely(['$superResolutionId::$gid']);
  }

  Future<void> deleteSuperResolve(int gid, SuperResolutionType type) async {
    SuperResolutionInfo? superResolutionInfo = get(gid, type);
    if (superResolutionInfo == null) {
      return;
    }

    Log.info('delete super resolution: $gid');

    superResolutionInfo.currentProcess?.kill();
    superResolutionInfoTable.remove(gid, type);
    await appDb.deleteSuperResolutionInfo(gid);

    String dirPath;
    if (type == SuperResolutionType.gallery) {
      GalleryDownloadedData? gallery = galleryDownloadService.gallerys.firstWhereOrNull((g) => g.gid == gid);
      if (gallery == null) {
        return;
      }
      dirPath = join(galleryDownloadService.computeGalleryDownloadPath(gallery.title, gallery.gid), imageDirName);
    } else {
      ArchiveDownloadedData? archive = archiveDownloadService.archives.firstWhereOrNull((a) => a.gid == gid);
      if (archive == null) {
        return;
      }
      dirPath = join(archiveDownloadService.computeArchiveUnpackingPath(archive), imageDirName);
    }

    Directory directory = Directory(dirPath);
    if (directory.existsSync()) {
      Directory(dirPath).deleteSync(recursive: true);
    }

    updateSafely(['$superResolutionId::$gid']);
  }

  Future<void> _doSuperResolve(int gid, SuperResolutionType type) async {
    List<GalleryImage> rawImages;
    if (type == SuperResolutionType.gallery) {
      rawImages = galleryDownloadService.galleryDownloadInfos[gid]!.images.cast();
    } else {
      rawImages = archiveDownloadService.getUnpackedImages(gid);
    }

    SuperResolutionInfo superResolutionInfo = get(gid, type)!;
    if (superResolutionInfo.status != SuperResolutionStatus.running) {
      superResolutionInfo.status = SuperResolutionStatus.running;
      await _updateSuperResolutionInfoStatus(gid, superResolutionInfo);
      updateSafely(['$superResolutionId::$gid']);
    }

    for (int i = 0; i < rawImages.length; i++) {
      /// cancelled
      if (get(gid, type) == null) {
        return;
      }

      if (superResolutionInfo.status == SuperResolutionStatus.paused) {
        return;
      }

      if (superResolutionInfo.imageStatuses[i] == SuperResolutionStatus.success) {
        continue;
      }

      if (SuperResolutionSetting.modelDirectoryPath.value == null) {
        return;
      }

      superResolutionInfo.imageStatuses[i] = SuperResolutionStatus.running;
      await _updateSuperResolutionInfoStatus(gid, superResolutionInfo);
      updateSafely(['$superResolutionId::$gid']);

      bool success = await _handleImage(rawImages[i], superResolutionInfo);
      if (!success) {
        pauseSuperResolve(gid, type);
        return;
      }

      superResolutionInfo.imageStatuses[i] = SuperResolutionStatus.success;
      Log.download('super resolve image ${rawImages[i].path} success');

      /// we can't kill the process immediately on Windows
      if (get(gid, type) != null) {
        await _updateSuperResolutionInfoStatus(gid, superResolutionInfo);
      }
      updateSafely(['$superResolutionId::$gid', '$superResolutionImageId::$gid::$i']);
    }

    if (get(gid, type) != null && superResolutionInfo.imageStatuses.every((status) => status == SuperResolutionStatus.success)) {
      superResolutionInfo.status = SuperResolutionStatus.success;
      await _updateSuperResolutionInfoStatus(gid, superResolutionInfo);
      updateSafely(['$superResolutionId::$gid']);
      Log.info('super resolve success, gid:$gid');
    }
  }

  Future<bool> _handleImage(GalleryImage rawImage, SuperResolutionInfo superResolutionInfo) async {
    if (extension(rawImage.path!) == '.gif') {
      String inputAbsolutePath = GalleryDownloadService.computeImageDownloadAbsolutePathFromRelativePath(rawImage.path!);
      String outputAbsolutePath = computeImageOutputAbsolutePath(rawImage.path!);
      try {
        File(inputAbsolutePath).copySync(outputAbsolutePath);
      } catch (e, s) {
        Log.error('copy gif image failed', e, s);
        return false;
      }
      return true;
    }

    Process? process;
    try {
      process = await _callProcess(rawImage);
    } on Exception catch (e) {
      toast('internalError'.tr + e.toString(), isShort: false);
      Log.error(e);
      Log.uploadError(e, extraInfos: {'rawImage': rawImage});

      return false;
    } on Error catch (e) {
      toast('internalError'.tr + e.toString(), isShort: false);
      Log.error(e);
      Log.uploadError(e, extraInfos: {'rawImage': rawImage});

      return false;
    }

    superResolutionInfo.currentProcess = process;

    process.stderr.listen((event) {
      Log.verbose(String.fromCharCodes(event).trim());
    });

    int exitCode = await process.exitCode;

    /// pause and kill the process
    if (exitCode == -1 || exitCode == -15 || exitCode == 15) {
      return false;
    }

    if (exitCode != 0) {
      toast('${'internalError'.tr} exitCode:$exitCode', isShort: false);
      Log.error('${'internalError'.tr} exitCode:$exitCode');
      Log.uploadError(
        Exception('Process Error'),
        extraInfos: {'rawImage': rawImage, 'exitCode': exitCode},
      );

      return false;
    }

    return true;
  }

  Future<Process> _callProcess(GalleryImage rawImage) {
    Log.download('start to super resolve image ${rawImage.path}');

    String inputRelativePath = rawImage.path!;
    String outputRelativePath = computeImageOutputRelativePath(rawImage.path!);

    ModelType modelType = SuperResolutionSetting.model.value;

    Log.verbose(
      'Run: ${join(
        SuperResolutionSetting.modelDirectoryPath.value!,
        GetPlatform.isWindows
            ? modelType.windowsExecutableName
            : GetPlatform.isMacOS
                ? modelType.macOSExecutableName
                : modelType.linuxExecutableName,
      )} '
      '-i $inputRelativePath '
      '-o $outputRelativePath '
      '-n ${SuperResolutionSetting.model.value.subType} '
      '-f png '
      '-s 4 '
      '-g ${SuperResolutionSetting.gpuId.value} '
      '-m "${join(SuperResolutionSetting.modelDirectoryPath.value!, modelType.modelRelativePath)}"',
    );

    return Process.start(
      join(
        SuperResolutionSetting.modelDirectoryPath.value!,
        GetPlatform.isWindows
            ? modelType.windowsExecutableName
            : GetPlatform.isMacOS
                ? modelType.macOSExecutableName
                : modelType.linuxExecutableName,
      ),
      [
        '-i',
        inputRelativePath,
        '-o',
        outputRelativePath,
        '-n',
        SuperResolutionSetting.model.value.subType,
        '-f',
        'png',
        '-s',
        '4',
        '-g',
        SuperResolutionSetting.gpuId.value.toString(),
        '-m',
        join(SuperResolutionSetting.modelDirectoryPath.value!, modelType.modelRelativePath),
      ],
      workingDirectory: PathSetting.getVisibleDir().path,
      runInShell: true,
    );
  }

  void _checkInfoSourceExists() {
    List<TableEntry<int, SuperResolutionType, SuperResolutionInfo>> targetEntries = [];

    for (TableEntry<int, SuperResolutionType, SuperResolutionInfo> entry in superResolutionInfoTable.entries()) {
      if (entry.key2 == SuperResolutionType.gallery && galleryDownloadService.galleryDownloadInfos.containsKey(entry.key1)) {
        continue;
      }
      if (entry.key2 == SuperResolutionType.archive && archiveDownloadService.archiveDownloadInfos.containsKey(entry.key1)) {
        continue;
      }

      Log.error('Try to init super-resolution info but image source not exists: $entry');
      targetEntries.add(entry);
    }

    for (TableEntry<int, SuperResolutionType, SuperResolutionInfo> entry in targetEntries) {
      deleteSuperResolve(entry.key1, entry.key2);
    }
  }

  /// db
  Future<List<SuperResolutionInfoData>> _selectAllSuperResolutionInfo() async {
    return appDb.selectAllSuperResolutionInfo().get();
  }

  Future<bool> _insertSuperResolutionInfo(int gid, SuperResolutionInfo superResolutionInfo) async {
    return await appDb.insertSuperResolutionInfo(
          gid,
          superResolutionInfo.type.index,
          superResolutionInfo.status.index,
          superResolutionInfo.imageStatuses.map((status) => status.index).join(SuperResolutionInfo.imageStatusesSeparator),
        ) >
        0;
  }

  Future<bool> _updateSuperResolutionInfoStatus(int gid, SuperResolutionInfo superResolutionInfo) async {
    return await appDb.updateSuperResolutionInfoStatus(
          superResolutionInfo.status.index,
          superResolutionInfo.imageStatuses.map((status) => status.index).join(SuperResolutionInfo.imageStatusesSeparator),
          gid,
        ) >
        0;
  }

  // disk

  /// when we update a gallery, if this gallery is in super-resolution process, we need to copy current product
  Future<void> copyImageInfo(GalleryDownloadedData oldGallery, GalleryDownloadedData newGallery, int oldImageSerialNo, int newImageSerialNo) async {
    SuperResolutionInfo? oldGallerySuperResolutionInfo = get(oldGallery.gid, SuperResolutionType.gallery);
    if (oldGallerySuperResolutionInfo == null) {
      return;
    }

    if (oldGallerySuperResolutionInfo.imageStatuses[oldImageSerialNo] != SuperResolutionStatus.success) {
      return;
    }

    Log.debug('copy old super resolution image to new gallery, old: ${oldGallery.gid} $oldImageSerialNo, new: ${newGallery.gid} $newImageSerialNo');

    SuperResolutionInfo? newGallerySuperResolutionInfo = get(newGallery.gid, SuperResolutionType.gallery);
    String oldPath = computeImageOutputAbsolutePath(galleryDownloadService.galleryDownloadInfos[oldGallery.gid]!.images[oldImageSerialNo]!.path!);
    String newPath = computeImageOutputAbsolutePath(galleryDownloadService.galleryDownloadInfos[newGallery.gid]!.images[newImageSerialNo]!.path!);

    if (newGallerySuperResolutionInfo == null) {
      newGallerySuperResolutionInfo = SuperResolutionInfo(
        SuperResolutionType.gallery,
        SuperResolutionStatus.paused,
        List.generate(galleryDownloadService.galleryDownloadInfos[newGallery.gid]!.images.length, (_) => SuperResolutionStatus.running),
      );
      superResolutionInfoTable.put(newGallery.gid, SuperResolutionType.gallery, newGallerySuperResolutionInfo);
      await _insertSuperResolutionInfo(newGallery.gid, newGallerySuperResolutionInfo);
      File(newPath).parent.createSync(recursive: true);
      updateSafely(['$superResolutionId::${newGallery.gid}']);
    }

    try {
      File imageFile = File(oldPath);
      imageFile.copySync(newPath);
    } on Exception catch (e) {
      Log.error('copy super resolution image failed', e);
      Log.uploadError(e);
    }

    newGallerySuperResolutionInfo.imageStatuses[newImageSerialNo] = SuperResolutionStatus.success;
    await _updateSuperResolutionInfoStatus(newGallery.gid, newGallerySuperResolutionInfo);
    updateSafely(['$superResolutionId::${newGallery.gid}', '$superResolutionImageId::${newGallery.gid}::$newImageSerialNo']);
  }

  String computeImageOutputAbsolutePath(String rawImagePath) {
    return join(PathSetting.getVisibleDir().path, computeImageOutputRelativePath(rawImagePath));
  }

  String computeImageOutputRelativePath(String rawImagePath) {
    return join(computeImageOutputDirPath(rawImagePath), basenameWithoutExtension(rawImagePath) + (extension(rawImagePath) == '.gif' ? '.gif' : '.png'));
  }

  String computeImageOutputDirPath(String rawImagePath) {
    return join(dirname(rawImagePath), imageDirName);
  }
}

class SuperResolutionInfo {
  Process? currentProcess;

  SuperResolutionType type;

  SuperResolutionStatus status;

  List<SuperResolutionStatus> imageStatuses;

  static const imageStatusesSeparator = ',';

  SuperResolutionInfo(this.type, this.status, this.imageStatuses);
}

enum SuperResolutionType { gallery, archive }

enum SuperResolutionStatus { paused, running, success }
