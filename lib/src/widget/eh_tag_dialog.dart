import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/routes/routes.dart';
import 'package:jhentai/src/utils/route_util.dart';
import 'package:jhentai/src/utils/toast_util.dart';
import 'package:jhentai/src/widget/eh_wheel_speed_controller.dart';
import 'package:like_button/like_button.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../config/global_config.dart';
import '../database/database.dart';
import '../network/eh_request.dart';
import '../setting/user_setting.dart';
import '../utils/log.dart';
import '../utils/snack_util.dart';
import 'loading_state_indicator.dart';

class EHTagDialog extends StatefulWidget {
  final TagData tagData;
  final int gid;
  final String token;
  final String apikey;

  const EHTagDialog({
    Key? key,
    required this.tagData,
    required this.gid,
    required this.token,
    required this.apikey,
  }) : super(key: key);

  @override
  _EHTagDialogState createState() => _EHTagDialogState();
}

class _EHTagDialogState extends State<EHTagDialog> {
  LoadingState voteUpState = LoadingState.idle;
  LoadingState voteDownState = LoadingState.idle;
  LoadingState addWatchedTagState = LoadingState.idle;
  LoadingState addHiddenTagState = LoadingState.idle;

  ScrollController scrollController = ScrollController();

  @override
  void dispose() {
    super.dispose();
    scrollController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text('${widget.tagData.namespace}:${widget.tagData.key}'),
      contentPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 12, top: 12),
      children: [
        if (widget.tagData.tagName != null) ...[
          _buildInfo(),
          const Divider(height: 1).marginOnly(top: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildVoteUpButton(),
            _buildVoteDownButton(),
            _buildWatchTagButton(),
            _buildHideTagButton(),
            _buildGoToTagSetsButton(),
          ],
        ).marginOnly(top: 12),
      ],
    );
  }

  Widget _buildInfo() {
    String content = widget.tagData.fullTagName! + widget.tagData.intro! + widget.tagData.links!;

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 50,
        maxHeight: 400,
        minWidth: 200,
        maxWidth: 200,
      ),
      child: EHWheelSpeedController(
        scrollController: scrollController,
        child: HtmlWidget(
          content,
          renderMode: ListViewMode(shrinkWrap: true, controller: scrollController),
          textStyle: const TextStyle(fontSize: 12),
          onErrorBuilder: (context, element, error) => Text('$element error: $error'),
          onLoadingBuilder: (context, element, loadingProgress) => const CircularProgressIndicator(),
          onTapUrl: launchUrlString,
          customWidgetBuilder: (element) {
            if (element.localName != 'img') {
              return null;
            }
            return Center(
              child: ExtendedImage.network(element.attributes['src']!).marginSymmetric(vertical: 20),
            );
          },
        ).paddingSymmetric(horizontal: 12),
      ),
    );
  }

  Widget _buildVoteUpButton() {
    return LikeButton(
      likeBuilder: (bool liked) => Icon(
        Icons.thumb_up,
        size: GlobalConfig.tagDialogButtonSize,
        color: liked ? Colors.green : GlobalConfig.tagDialogButtonColor,
      ),
      onTap: (bool liked) => liked ? Future.value(true) : vote(isVotingUp: true),
    );
  }

  Widget _buildVoteDownButton() {
    return LikeButton(
      likeBuilder: (bool liked) => Icon(
        Icons.thumb_down,
        size: GlobalConfig.tagDialogButtonSize,
        color: liked ? Colors.red : GlobalConfig.tagDialogButtonColor,
      ),
      onTap: (bool liked) => liked ? Future.value(true) : vote(isVotingUp: false),
    );
  }

  Widget _buildWatchTagButton() {
    return LikeButton(
      likeBuilder: (bool liked) => Icon(
        Icons.favorite,
        size: GlobalConfig.tagDialogButtonSize,
        color: liked ? Colors.red : GlobalConfig.tagDialogButtonColor,
      ),
      onTap: (bool liked) => liked ? Future.value(true) : addNewTagSet(true),
    );
  }

  Widget _buildHideTagButton() {
    return LikeButton(
      likeBuilder: (bool liked) => Icon(
        Icons.visibility_off,
        size: GlobalConfig.tagDialogButtonSize,
        color: liked ? Colors.red : GlobalConfig.tagDialogButtonColor,
      ),
      onTap: (bool liked) => liked ? Future.value(true) : addNewTagSet(false),
    );
  }

  Widget _buildGoToTagSetsButton() {
    return LikeButton(
      likeBuilder: (_) => Icon(
        Icons.settings,
        size: GlobalConfig.tagDialogButtonSize,
        color: GlobalConfig.tagDialogButtonColor,
      ),
      onTap: (_) async {
        toRoute(Routes.tagSets);
        return null;
      },
    );
  }

  Future<bool> vote({required bool isVotingUp}) async {
    if (!UserSetting.hasLoggedIn()) {
      snack('operationFailed'.tr, 'needLoginToOperate'.tr);
      return false;
    }

    if (voteUpState == LoadingState.loading || voteDownState == LoadingState.loading) {
      return true;
    }

    if (isVotingUp) {
      voteUpState = LoadingState.loading;
    } else {
      voteDownState = LoadingState.loading;
    }

    _doVote(isVotingUp: isVotingUp);

    return true;
  }

  Future<void> _doVote({required bool isVotingUp}) async {
    Log.info('Vote for tag:${widget.tagData.key}, isVotingUp: $isVotingUp');

    try {
      await EHRequest.voteTag(
        widget.gid,
        widget.token,
        UserSetting.ipbMemberId.value!,
        widget.apikey,
        widget.tagData.namespace,
        widget.tagData.key,
        isVotingUp,
      );
    } on DioError catch (e) {
      if (isVotingUp) {
        voteUpState = LoadingState.error;
      } else {
        voteDownState = LoadingState.error;
      }
      Log.error('voteTagFailed'.tr, e.message);
      snack('voteTagFailed'.tr, e.message);
      return;
    }

    if (isVotingUp) {
      voteUpState = LoadingState.success;
    } else {
      voteDownState = LoadingState.success;
    }

    toast('success'.tr);
  }

  Future<bool> addNewTagSet(bool watch) async {
    if (!UserSetting.hasLoggedIn()) {
      snack('operationFailed'.tr, 'needLoginToOperate'.tr);
      return false;
    }

    if (addWatchedTagState == LoadingState.loading || addHiddenTagState == LoadingState.loading) {
      return true;
    }

    if (watch) {
      addWatchedTagState = LoadingState.loading;
    } else {
      addHiddenTagState = LoadingState.loading;
    }

    _doAddNewTagSet(watch);

    return true;
  }

  Future<void> _doAddNewTagSet(bool watch) async {
    Log.info('Add new tag set: ${widget.tagData.namespace}:${widget.tagData.key}, watch:$watch');

    try {
      await EHRequest.requestAddTagSet(
        tag: '${widget.tagData.namespace}:${widget.tagData.key}',
        tagWeight: 10,
        watch: watch,
        hidden: !watch,
      );
    } on DioError catch (e) {
      Log.error('addNewTagSetFailed'.tr, e.message);
      snack('addNewTagSetFailed'.tr, e.message, longDuration: true, snackPosition: SnackPosition.BOTTOM);
      if (watch) {
        addWatchedTagState = LoadingState.error;
      } else {
        addHiddenTagState = LoadingState.error;
      }
      return;
    }

    if (watch) {
      addWatchedTagState = LoadingState.success;
    } else {
      addHiddenTagState = LoadingState.success;
    }

    snack(
      watch ? 'addNewWatchedTagSetSuccess'.tr : 'addNewHiddenTagSetSuccess'.tr,
      'addNewTagSetSuccessHint'.tr,
      longDuration: true,
      snackPosition: SnackPosition.TOP,
    );
  }
}