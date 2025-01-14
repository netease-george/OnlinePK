//
//  NEPkLiveViewController.m
//  NLiteAVDemo
//
//  Created by vvj on 2021/8/12.
// Copyright (c) 2021 NetEase, Inc.  All rights reserved.
// Use of this source code is governed by a MIT license that can be found in the LICENSE file.

#import "NEPkLiveViewController.h"
#import "NTESActionSheetNavigationController.h"

#import "NETSPkStatusBar.h"
#import "NETSInviteeInfoView.h"
#import "TopmostView.h"
#import "NETSInvitingBar.h"


#import "NENavigator.h"
#import "NETSAnchorTopInfoView.h"
#import "NETSAudienceNum.h"
#import "NEPkService.h"
#import "NEPkPassthroughService.h"
#import "NECreateRoomResponseModel.h"
#import "NETSChoosePKSheet.h"
#import "NEPkService.h"
#import "NEPassthroughPkInviteModel.h"
#import "NEPkChatroomMsgHandle.h"
#import "NELiveRoomListModel.h"
#import "NETSPushStreamService.h"
#import "NEPkLiveAttachment.h"
#import "NETSChatroomService.h"
#import "Reachability.h"

@interface NEPkLiveViewController ()<NETSChoosePKSheetDelegate,NEPkPassthroughServiceDelegate,NEPkChatroomMsgHandleDelegate,NETSInvitingBarDelegate>
///// pk直播服务类
//@property (nonatomic, strong)   NETSPkService    *pkService;
/// pk邀请状态条
@property (nonatomic, strong)   NETSInvitingBar  *pkInvitingBar;
/// pk状态条
@property(nonatomic, strong)    NETSPkStatusBar  *pkStatusBar;
/// 主播信息视图
@property (nonatomic, strong)   NETSAnchorTopInfoView   *anchorInfo;
/// 直播中 观众数量视图
@property (nonatomic, strong)   NETSAudienceNum         *audienceInfo;
/// 被邀请者信息视图
@property (nonatomic, strong)   NETSInviteeInfoView     *inviteeInfo;
/// pk胜利图标
@property (nonatomic, strong)   UIImageView     *pkSuccessIco;
/// pk失败图标
@property (nonatomic, strong)   UIImageView     *pkFailedIco;
/// 是否接受pk邀请对话框
@property (nonatomic, strong)   UIAlertController   *pkAlert;
/// 己方加入视音频房间信号
@property (nonatomic, strong)   RACSubject      *joinedPkChannelSubject;
/// 服务端透传pk开始信号
@property (nonatomic, strong)   RACSubject      *serverStartPkSubject;
/// 邀请别人PK按钮
@property (nonatomic, strong)   UIButton                *pkBtn;

@property(nonatomic, strong) NEPkPassthroughService *pkPassthroughService;
//IM 聊天室消息处理类
@property(nonatomic, strong) NEPkChatroomMsgHandle *pkChatRoomMsgHandle;
//pk状态
@property(nonatomic, assign) NEPKStatus pkState;

@property(nonatomic, assign) NETSPkServiceRole pkRole;
//对方主播昵称
@property(nonatomic, strong) NSString *otherAnchorName;

@property(nonatomic, strong) Reachability *reachability;
//记录被邀请者的id
@property(nonatomic, strong) NSString *inviteeAccountId;
@end

@implementation NEPkLiveViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initConfig];
    [self bindAction];
}

- (void)initConfig {
    self.pkState = NEPKStatusInit;
    [[NIMSDK sharedSDK].passThroughManager addDelegate:self.pkPassthroughService];
    [[NIMSDK sharedSDK].chatManager addDelegate:self.pkChatRoomMsgHandle];
    [[NIMSDK sharedSDK].chatroomManager addDelegate:self.pkChatRoomMsgHandle];
    [[NIMSDK sharedSDK].systemNotificationManager addDelegate:self.pkChatRoomMsgHandle];
}

#pragma mark - overwriteMethod

- (void)layoutPkLive {
    [super layoutPkLive];
    [self.pkSuccessIco removeFromSuperview];
    [self.pkFailedIco removeFromSuperview];
    
    [self.view addSubview:self.pkStatusBar];
    [self.view addSubview:self.inviteeInfo];
    
    
    self.pkStatusBar.frame = CGRectMake(0, self.localRender.bottom, kScreenWidth, 58);
    self.inviteeInfo.frame = CGRectMake(self.remoteRender.right - 8 - 82, self.remoteRender.top + 8, 82, 24);
    [self.pkStatusBar refreshWithLeftRewardCoins:0 leftRewardAvatars:@[] rightRewardCoins:0 rightRewardAvatars:@[]];
}


- (void)layoutSingleLive {
    [super layoutSingleLive];
    [self.pkStatusBar removeFromSuperview];
    [self.pkSuccessIco removeFromSuperview];
    [self.pkFailedIco removeFromSuperview];
    [self.inviteeInfo removeFromSuperview];
    
}
#pragma mark - privateMethod
- (void)bindAction {
    @weakify(self);
    [RACObserve(self, pkState) subscribeNext:^(id  _Nullable x) {
        ntes_main_async_safe(^{
            @strongify(self);
            NSString *pkBtnIco = (self.pkState == NEPKStatusPking || self.pkState == NEPKStatusPkPunish) ? @"end_pk_ico" : @"pk_ico";
            [self.pkBtn setImage:[UIImage imageNamed:pkBtnIco] forState:UIControlStateNormal];
        });
    }];
    
    
    [RACObserve(self, createRoomModel) subscribeNext:^(NECreateRoomResponseModel*  _Nullable room) {
        @strongify(self);
        if (!room) { return; }
        self.pkChatRoomMsgHandle.chatroomId = room.live.chatRoomId;
    }];
}



-(void)createRoomRefreshUI {
    [super createRoomRefreshUI];
    [self.view addSubview:self.pkBtn];
    self.pkBtn.frame = CGRectMake(kScreenWidth - 60 - 8, kScreenHeight - (kIsFullScreen ? 34 : 0) - 64 - 60, 60, 60);
}

- (void)closeLiveRoom {
    [super closeLiveRoom];
    [self.pkStatusBar stopCountdown];
    if (self.pkState == NEPKStatusPking) {
        [[NERtcEngine sharedEngine] stopChannelMediaRelay];
    }
}

- (void)presenAlert:(UIAlertController *)alert {
    // 消除顶层视图
    UIView *topmostView = [TopmostView viewForApplicationWindow];
    for (UIView *subview in topmostView.subviews) {
        [subview removeFromSuperview];
    }
    topmostView.userInteractionEnabled = NO;
    
    // 弹出alert
    if (self.pkAlert) {
        [self.pkAlert dismissViewControllerAnimated:NO completion:nil];
        self.pkAlert = nil;
    }
    [[NENavigator shared].navigationController presentViewController:alert animated:YES completion:nil];
    self.pkAlert = alert;
}

//点击pk按钮
- (void)startPkAction:(UIButton *)sender {
    
    if (self.pkState == NEPKStatusInit || self.pkState == NEPKStatusPkEnd) {
        if ([self.pkInvitingBar superview]) {
            [NETSToast showToast:NSLocalizedString(@"您已经再邀请中,不可再邀请", nil)];
            return;
        }
        YXAlogInfo(@"打开pk列表面板,开始pk");
        self.pkState = NEPKStatusPkInviting;
        [NETSChoosePKSheet showWithTarget:self];
    }else if (self.pkState == NEPKStatusPking || self.pkState == NEPKStatusPkPunish) {
        YXAlogInfo(@"点击结束pk");
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"结束PK", nil) message:NSLocalizedString(@"PK尚未结束,强制结束会返回普通直播模式", nil) preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"取消", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            YXAlogInfo(@"取消强制结束pk");
        }];
        @weakify(self);
        UIAlertAction *confirm = [UIAlertAction actionWithTitle:NSLocalizedString(@"立即结束", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [NETSToast showLoading];
            @strongify(self);
            [self _manualEndPk];
        }];
        [alert addAction:cancel];
        [alert addAction:confirm];
        [self presenAlert:alert];
    }else if (self.pkState == NEPKStatusPkInviting) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self.pkInvitingBar superview]) {
                [NETSToast showToast:NSLocalizedString(@"您已经再邀请中,不可再邀请", nil)];
            }else {
                [NETSChoosePKSheet showWithTarget:self];
            }
        });
       
    }
}

/// 强制结束pk
- (void)_manualEndPk {

    [[NEPkService sharedPkService] closePkLiveSuccessBlock:^(NSDictionary * _Nonnull response) {
        [self layoutSingleLive];
    } failedBlock:^(NSError * _Nonnull error, NSDictionary * _Nullable response) {
      YXAlogError(@"closePkLive failed,error:%@",error);
    }];
    
}

//开始跨频道转发
- (void)startRtcChannelRelayWithChannelName:(NSString *)channelName token:(NSString *)checkSum rooomUid:(int64_t)uid {
    ///实例化config
    NERtcChannelMediaRelayConfiguration *config = [[NERtcChannelMediaRelayConfiguration alloc]init];
    //添加目标房间1信息
    NERtcChannelMediaRelayInfo *info = [[NERtcChannelMediaRelayInfo alloc]init];
    info.channelName = channelName;
    info.token = checkSum;
    info.uid = uid;
    [config setDestinationInfo:info forChannelName:info.channelName];

    //开始转发
    int ret = [[NERtcEngine sharedEngine] startChannelMediaRelay:config];
    if(ret == 0) {
        YXAlogError(@"startRtcChannelRelay success");
    }else {
        //失败处理
        YXAlogError(@"startRtcChannelRelay failed,error = %d",ret);
    }
}



//更新推流任务
- (void)_updateLiveStreamTask:(NSArray *)uids {
    
    NERtcLiveStreamTaskInfo* taskInfo = [NETSPushStreamService streamTaskWithUrl:self.createRoomModel.live.liveConfig.pushUrl uids:uids];
    
    [NETSPushStreamService updateLiveStreamTask:taskInfo successBlock:^{
        YXAlogInfo(@"updateLiveStreamTask success");
    } failedBlock:^(NSError * _Nonnull error) {
        YXAlogError(@"updateLiveStream failed,error = %@",error);
    }];
}


-(void)dealloc {
    [[NIMSDK sharedSDK].passThroughManager removeDelegate:self.pkPassthroughService];
    [[NIMSDK sharedSDK].chatManager removeDelegate:self.pkChatRoomMsgHandle];
    [[NIMSDK sharedSDK].chatroomManager removeDelegate:self.pkChatRoomMsgHandle];
    [[NIMSDK sharedSDK].systemNotificationManager removeDelegate:self.pkChatRoomMsgHandle];
}

#pragma mark - NETSChoosePKSheetDelegate 选择主播PK代理
- (void)choosePkOnSheet:(NETSChoosePKSheet *)sheet withRoom:(NELiveRoomListDetailModel *)room {
    [sheet dismiss];
    self.inviteeAccountId = room.anchor.accountId;
    @weakify(self);
    void (^successBlock)(NSString * _Nonnull) = ^(NSString *nickName) {
        @strongify(self);
        NSString *title = [NSString stringWithFormat:NSLocalizedString(@"邀请\"%@\"PK连线中...", nil),nickName];
        self.pkInvitingBar = [NETSInvitingBar showInvitingWithTarget:self title:title];
    };
    
    void (^failedBlock)(NSError * _Nullable) = ^(NSError * _Nullable error) {
        NSString *msg = error.userInfo[NSLocalizedDescriptionKey] ?: NSLocalizedString(@"邀请PK失败", nil);
        [NETSToast showToast:msg];
    };
    
    NSString *msg = [NSString stringWithFormat:NSLocalizedString(@"确定邀请\"%@\"进行PK?", nil), room.anchor.nickname];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"邀请PK", nil) message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"取消", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        YXAlogInfo(@"邀请者取消pk邀请...");
    }];
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:NSLocalizedString(@"确定", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        @strongify(self);
        [NETSToast showLoading];
    [[NEPkService sharedPkService] requestPkWithOperation:NEPkOperationInvite targetAccountId:room.anchor.accountId successBlock:^(NSDictionary * _Nonnull response) {
        successBlock(room.anchor.nickname);
    } failedBlock:^(NSError * _Nonnull error, NSDictionary * _Nullable response) {
        if (error) {
            YXAlogError(@"requestPk failed,error = %@",error);
            failedBlock(error);
        }
        [NETSToast hideLoading];
    }];
        
    }];
    [alert addAction:cancel];
    [alert addAction:confirm];
    [self presenAlert:alert];
}

#pragma mark - NETSInvitingBarDelegate
-(void)clickCancelInviting:(NETSInviteBarType)barType {
    
    self.pkState = NEPKStatusInit;
    [[NEPkService sharedPkService] cancelPkRequestWithOperation:NEPkOperationCancel targetAccountId:self.inviteeAccountId successBlock:^(NSDictionary * _Nonnull response) {
        [NETSToast hideLoading];
    } failedBlock:^(NSError * _Nonnull error, NSDictionary * _Nullable response) {
        if (error) {
            YXAlogError(@"cancelPkRequest failed,error:%@",error);
        }
    }];
}

#pragma mark - NEPkPassthroughServiceDelegate

- (void)receivePassThrourhPKInviteData:(NEPassthroughPkInviteModel *)data {
    
    YXAlogInfo(@"receive pKInvite passThrourhMessage  success!");
    
    if (self.presentedViewController && [self.presentedViewController isKindOfClass:[NTESActionSheetNavigationController class]]) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    }
    
    NSString *msg = [NSString stringWithFormat:NSLocalizedString(@"\"%@\"邀请你进行PK,是否接受?", nil), data.actionAnchor.nickname];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"邀请PK", nil) message:msg preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"拒绝", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [[NEPkService sharedPkService] rejectPkRequestWithOperation:NEPkOperationRefuse targetAccountId:data.actionAnchor.accountId successBlock:^(NSDictionary * _Nonnull response) {
                    
        } failedBlock:^(NSError * _Nonnull error, NSDictionary * _Nullable response) {
            if (error) {
                YXAlogError(@"rejectPk failed,error:%@",error);
            }
        }];
    }];
    
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:NSLocalizedString(@"接受", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        
        [[NEPkService sharedPkService] acceptPkWithOperation:NEPkOperationAgree targetAccountId:data.senderAccountId successBlock:^(NSDictionary * _Nonnull response) {
            YXAlogInfo(@"acceptPk success");
            [NETSToast showLoading];
            [self startRtcChannelRelayWithChannelName:data.actionAnchor.channelName token:data.targetAnchor.checkSum rooomUid:data.targetAnchor.roomUid.longLongValue];
        } failedBlock:^(NSError * _Nonnull error, NSDictionary * _Nullable response) {
            if (error) {
                YXAlogError(@"acceptPk failed,error:%@",error);
            }
        }];
    }];

    [alert addAction:cancel];
    [alert addAction:confirm];
    [self presenAlert:alert];
}

- (void)receivePassThrourhAgreePkData:(NEPassthroughPkInviteModel *)data {
    YXAlogInfo(@"receive agreePk passThrourhMessage  success!");

    [self startRtcChannelRelayWithChannelName:data.actionAnchor.channelName token:data.targetAnchor.checkSum rooomUid:data.targetAnchor.roomUid.longLongValue];;
}

- (void)receivePassThrourhRefusePKInviteData:(NEPassthroughPkInviteModel *)data {
    YXAlogInfo(@"refuse pk invite");
    self.pkState = NEPKStatusInit;
    [NETSToast hideLoading];
    if ([self.pkInvitingBar superview]) {
        [self.pkInvitingBar dismiss];
    }
    [NETSToast showToast:NSLocalizedString(@"对方已拒绝你的PK邀请", nil)];
}

- (void)receivePassThrourhCancelPKInviteData:(NEPassthroughPkInviteModel *)data {
    YXAlogInfo(@"receive cancelPKInvite passThrourhMessage  success!");

    [NETSToast showToast:NSLocalizedString(@"对方已取消PK邀请", nil)];
    if (self.pkAlert) {
        [self.pkAlert dismissViewControllerAnimated:YES completion:nil];
        self.pkAlert = nil;
    }
}


- (void)receivePassThrourhTimeOutData:(NEPassthroughPkInviteModel *)data {
    YXAlogInfo(@"receive timeOut passThrourhMessage  success!");
    self.pkState = NEPKStatusInit;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NETSToast hideLoading];//延时执行
    });
    
    [NETSToast showToast:NSLocalizedString(@"PK连接超时，已自动取消", nil)];

    if (self.pkAlert) {
        [self.pkAlert dismissViewControllerAnimated:YES completion:nil];
    }
    if ([self.pkInvitingBar superview]) {
        [self.pkInvitingBar dismiss];
    }
}


#pragma mark - NEPkChatroomMsgHandleDelegate
- (void)receivePkStartAttachment:(NEPkLiveStartAttachment *)liveStartData {
    
    YXAlogInfo(@"receive pkStart imMessage  success!");
    NERtcVideoCanvas *canvas = [self setupLocalCanvas];
    [NERtcEngine.sharedEngine setupLocalVideoCanvas:canvas];
    self.pkState = NEPKStatusPking;
    
    // pk布局
    ntes_main_async_safe(^{
        [NETSToast hideLoading];
        [self layoutPkLive];
        [NETSToast hideLoading];
        [self.pkInvitingBar dismiss];
    });
    
    // 开始pk倒计时
    int32_t start = kPkLiveTotalTime - (int32_t)((liveStartData.sendTime - liveStartData.pkStartTime) / 1000);
    [self.pkStatusBar countdownWithSeconds:start prefix:@"PK "];
    [self.pkStatusBar refreshWithLeftRewardCoins:0 leftRewardAvatars:@[] rightRewardCoins:0 rightRewardAvatars:@[]];
    
    
    if ([liveStartData.inviter.accountId isEqualToString:[NEAccount shared].userModel.accountId]) {//邀请者是自己
        self.pkRole = NETSPkServiceInviter;
        [self.inviteeInfo reloadAvatar:liveStartData.inviter.avatar nickname:liveStartData.inviter.nickname];
    }else {
        self.pkRole = NETSPkServiceInvitee;
        [self.inviteeInfo reloadAvatar:liveStartData.invitee.avatar nickname:liveStartData.invitee.nickname];
    }

    //更新推流任务
    NSArray *uids = @[@(liveStartData.inviter.roomUid),@(liveStartData.invitee.roomUid)];
    [self _updateLiveStreamTask:uids];
}

 
-(void)receivePunishStartAttachment:(NEStartPunishAttachment *)punishData {
    
    YXAlogInfo(@"receive punishStart imMessage  success!");
    self.pkState = NEPKStatusPkPunish;
    // 获取pk结果
    NETSPkResult res = NETSPkUnknownResult;
    if (punishData.inviteeRewards == punishData.inviterRewards) {
        res = NETSPkTieResult;
    }
    else if ((punishData.inviteeRewards > punishData.inviterRewards && self.pkRole == NETSPkServiceInvitee) ||
             (punishData.inviteeRewards < punishData.inviterRewards && self.pkRole == NETSPkServiceInviter)) {
        res = NETSPkCurrentAnchorWin;
    }
    else {
        res = NETSPkOtherAnchorWin;
    }
    
    if (res == NETSPkTieResult) {
        [self.pkStatusBar stopCountdown];
    } else {
//        int32_t seconds = kPkLivePunishTotalTime - (int32_t)((data.currentTime - data.pkPulishmentTime) / 1000);
        [self.pkStatusBar countdownWithSeconds:punishData.pkPenaltyCountDown prefix:@"惩罚 "];
    }
    
    //刷新惩罚UI
    CGRect leftIcoFrame = CGRectMake((self.localRender.width - 100) * 0.5, self.localRender.bottom - 100, 100, 100);
    CGRect rightIcoFrame = CGRectMake(self.remoteRender.left + (self.remoteRender.width - 100) * 0.5, self.remoteRender.bottom - 100, 100, 100);
    
    self.pkSuccessIco.image = [UIImage imageNamed:@"pk_succeed_ico"];
    self.pkFailedIco.image = [UIImage imageNamed:@"pk_failed_ico"];
    
    switch (res) {
        case NETSPkCurrentAnchorWin:
        {
            self.pkSuccessIco.frame = leftIcoFrame;
            self.pkFailedIco.frame = rightIcoFrame;
        }
            break;
        case NETSPkOtherAnchorWin:
        {
            self.pkSuccessIco.frame = rightIcoFrame;
            self.pkFailedIco.frame = leftIcoFrame;
        }
            break;
        case NETSPkTieResult:
        {
            self.pkSuccessIco.image = [UIImage imageNamed:@"pk_tie_ico"];
            self.pkFailedIco.image = [UIImage imageNamed:@"pk_tie_ico"];
            
            self.pkSuccessIco.frame = leftIcoFrame;
            self.pkFailedIco.frame = rightIcoFrame;
        }
            break;
            
        default:
            break;
    }
    
    [self.view addSubview:self.pkSuccessIco];
    [self.view addSubview:self.pkFailedIco];
 
}


-(void)receivePkEndAttachment:(NEPkEndAttachment *)pkEndData {
    
    YXAlogInfo(@"receive pkEnd imMessage  success!");

    NERtcVideoCanvas *canvas = [self setupSingleCanvas];
    [NERtcEngine.sharedEngine setupLocalVideoCanvas:canvas];
    self.pkState = NEPKStatusPkEnd;
    // 停止pk计时
    [self.pkStatusBar stopCountdown];
    
    //停止跨频道转发
    [[NERtcEngine sharedEngine] stopChannelMediaRelay];
    
    // 布局单人直播
    ntes_main_async_safe(^{
        [NETSToast hideLoading];
        [self layoutSingleLive];
    });
    
  
    if (self.pkAlert) {
        [self.pkAlert dismissViewControllerAnimated:YES completion:nil];
    }
    
    //更新推流任务
    NSArray *uids = @[@(self.createRoomModel.anchor.roomUid)];
    [self _updateLiveStreamTask:uids];
    
    // 若是当前用户取消,不提示
    NSString *nickname = [NEAccount shared].userModel.nickname;
    if (![pkEndData.nickname isEqualToString:nickname]) {
        NSString *msg = [NSString stringWithFormat:NSLocalizedString(@"%@结束PK", nil), pkEndData.nickname];
        [NETSToast showToast:msg];
    }
}



- (void)receivePkRewardAttachment:(NEPkRewardAttachment *)rewardData {
    YXAlogInfo(@"receive pkReward imMessage success!");
    BOOL isInviter = [rewardData.anchorReward.accountId isEqualToString:[NEAccount shared].userModel.accountId];
    if (self.pkState == NEPKStatusPking) {
        // pk状态,更新pk状态栏
        int64_t leftReward = isInviter ? rewardData.anchorReward.pkRewardTotal : rewardData.otherAnchorReward.pkRewardTotal;
        NSArray *leftAvatars = isInviter ? rewardData.anchorReward.rewardAvatars : rewardData.otherAnchorReward.rewardAvatars;
        int64_t rightReward = isInviter ? rewardData.otherAnchorReward.pkRewardTotal : rewardData.anchorReward.pkRewardTotal;
        NSArray *rightAvatars = isInviter ? rewardData.otherAnchorReward.rewardAvatars : rewardData.anchorReward.rewardAvatars;
        [self.pkStatusBar refreshWithLeftRewardCoins:leftReward leftRewardAvatars:leftAvatars rightRewardCoins:rightReward rightRewardAvatars:rightAvatars];
    }
    
    // 更新用户信息栏(云币值)
    int32_t coins = rewardData.anchorReward.rewardTotal;
    if (!isInviter) {
        coins = rewardData.otherAnchorReward.rewardTotal;
    }
    [self.anchorInfo updateCoins:coins];
    
    //如果打赏的是当前主播,向聊天室发送打赏消息
    if (isInviter) {
        NIMCustomObject *object = [[NIMCustomObject alloc] init];
        object.attachment = rewardData;
        NIMMessage *msg = [[NIMMessage alloc] init];
        msg.messageObject = object;
        [self.chatView addMessages:@[msg]];
    }
}

- (void)onRecvRoomTextMsg:(NSArray<NIMMessage *> *)messages {
    [self chatViewAddMessge:messages];
}

-(void)didChatroomMember:(NIMChatroomNotificationMember *)member enter:(BOOL)enter sessionId:(NSString *)sessionId {

    // 主播的聊天室id
    NSString *chatRoomCreatorId = self.createRoomModel.anchor.imAccid;
    if ([chatRoomCreatorId isEqualToString:member.userId]) {
        YXAlogInfo(@"聊天室创建者: \"%@\" %@房间", member.userId, (enter ? @"加入":@"离开"));
    } else {
        // 提示非聊天室创建者 加入/离开 消息
        NIMMessage *message = [[NIMMessage alloc] init];
        message.text = enter ? [NSString stringWithFormat:NSLocalizedString(@"\"%@\" 加入房间", nil), member.nick] : [NSString stringWithFormat:NSLocalizedString(@"\"%@\" 离开房间", nil), member.nick];
        message.remoteExt = @{@"type":@(1)};
        [self.chatView addMessages:@[message]];
    }
    
    // 聊天室信息成员变更
    NSString *roomId = self.createRoomModel.live.chatRoomId;
    [NETSChatroomService fetchMembersRoomId:roomId limit:10 successBlock:^(NSArray<NIMChatroomMember *> * _Nullable members) {
        YXAlogInfo(@"members: %@", members);
        [self.audienceInfo reloadWithDatas:members];
    } failedBlock:^(NSError * _Nonnull error) {
        YXAlogInfo(@"主播端获取IM聊天室成员失败, error: %@", error);
    }];
    
}

- (void)didChatroomClosedWithRoomId:(NSString *)roomId {
    
}

#pragma mark - lazyMethod
- (UIButton *)pkBtn {
    if (!_pkBtn) {
        _pkBtn = [[UIButton alloc] init];
        [_pkBtn setImage:[UIImage imageNamed:@"pk_ico"] forState:UIControlStateNormal];
        [_pkBtn addTarget:self action:@selector(startPkAction:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _pkBtn;
}

- (NETSAnchorTopInfoView *)anchorInfo {
    if (!_anchorInfo) {
        _anchorInfo = [[NETSAnchorTopInfoView alloc] init];
    }
    return _anchorInfo;
}

- (NETSAudienceNum *)audienceInfo {
    if (!_audienceInfo) {
        _audienceInfo = [[NETSAudienceNum alloc] initWithFrame:CGRectZero];
    }
    return _audienceInfo;
}

- (NETSPkStatusBar *)pkStatusBar {
    if (!_pkStatusBar) {
        _pkStatusBar = [[NETSPkStatusBar alloc] init];
    }
    return _pkStatusBar;
}

- (UIImageView *)pkSuccessIco {
    if (!_pkSuccessIco) {
        _pkSuccessIco = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
    }
    return _pkSuccessIco;
}

- (UIImageView *)pkFailedIco {
    if (!_pkFailedIco) {
        _pkFailedIco = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
    }
    return _pkFailedIco;
}

- (NETSInviteeInfoView *)inviteeInfo {
    if (!_inviteeInfo) {
        _inviteeInfo = [[NETSInviteeInfoView alloc] init];
    }
    return _inviteeInfo;
}

- (NEPkPassthroughService *)pkPassthroughService {
    if (!_pkPassthroughService) {
        _pkPassthroughService = [[NEPkPassthroughService alloc]init];
        _pkPassthroughService.delegate = self;
    }
    return _pkPassthroughService;
}

-(NEPkChatroomMsgHandle *)pkChatRoomMsgHandle {
    if (!_pkChatRoomMsgHandle) {
        _pkChatRoomMsgHandle = [[NEPkChatroomMsgHandle alloc]init];
        _pkChatRoomMsgHandle.delegate = self;
    }
    return _pkChatRoomMsgHandle;
}

@end
