#import "Common.h"
#import "MapsAppDelegate.h"
#import "MapViewController.h"
#import "MWMActivityViewController.h"
#import "MWMBottomMenuCollectionViewCell.h"
#import "MWMBottomMenuLayout.h"
#import "MWMBottomMenuView.h"
#import "MWMBottomMenuViewController.h"
#import "MWMMapViewControlsManager.h"
#import "MWMSearchManager.h"
#import "SettingsAndMoreVC.h"
#import "Statistics.h"
#import "UIColor+MapsMeColor.h"
#import "UIKitCategories.h"

#import "3party/Alohalytics/src/alohalytics_objc.h"

#include "Framework.h"

extern NSString * const kAlohalyticsTapEventKey;
extern NSString * const kSearchStateWillChangeNotification;
extern NSString * const kSearchStateKey;

static NSString * const kCollectionCellPortrait = @"MWMBottomMenuCollectionViewPortraitCell";
static NSString * const kCollectionCelllandscape = @"MWMBottomMenuCollectionViewLandscapeCell";

static CGFloat const kLayoutThreshold = 420.0;

typedef NS_ENUM(NSUInteger, MWMBottomMenuViewCell)
{
  MWMBottomMenuViewCellDownload,
  MWMBottomMenuViewCellSettings,
  MWMBottomMenuViewCellShare,
  MWMBottomMenuViewCellCount
};

@interface MWMBottomMenuViewController ()<UICollectionViewDataSource, UICollectionViewDelegate>

@property(weak, nonatomic) MapViewController * controller;
@property(weak, nonatomic) IBOutlet UICollectionView * buttonsCollectionView;

@property(weak, nonatomic) IBOutlet UIButton * locationButton;
@property(weak, nonatomic) IBOutlet UICollectionView * additionalButtons;
@property(weak, nonatomic) IBOutlet UILabel * streetLabel;

@property(weak, nonatomic) id<MWMBottomMenuControllerProtocol> delegate;

@property(nonatomic) BOOL searchIsActive;

@property(nonatomic) SolidTouchView * dimBackground;

@property(nonatomic) MWMBottomMenuState restoreState;

@property(nonatomic) int locationListenerSlot;

@property(nonatomic) location::State::Mode locationState;

@end

@implementation MWMBottomMenuViewController

- (instancetype)initWithParentController:(MapViewController *)controller
                                delegate:(id<MWMBottomMenuControllerProtocol>)delegate
{
  self = [super init];
  if (self)
  {
    _controller = controller;
    _delegate = delegate;
    [controller addChildViewController:self];
    MWMBottomMenuView * view = (MWMBottomMenuView *)self.view;
    [controller.view addSubview:view];
    view.maxY = controller.view.height;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(searchStateWillChange:)
                                                 name:kSearchStateWillChangeNotification
                                               object:nil];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  [self setupCollectionView];
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  [self configLocationListener];
  [self onLocationStateModeChanged:GetFramework().GetLocationState()->GetMode()];
}

- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];
  GetFramework().GetLocationState()->RemoveStateModeListener(self.locationListenerSlot);
}

- (void)onEnterForeground
{
  [self onLocationStateModeChanged:GetFramework().GetLocationState()->GetMode()];
}

#pragma mark - Layout

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                duration:(NSTimeInterval)duration
{
  [self.additionalButtons reloadData];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
  [self.additionalButtons reloadData];
}

#pragma mark - Routing state

- (void)setStreetName:(NSString *)streetName
{
  self.state = MWMBottomMenuStateText;
  self.streetLabel.text = streetName;
}

- (void)setInactive
{
  self.p2pButton.selected = NO;
  self.state = self.restoreState = MWMBottomMenuStateInactive;
}

- (void)setPlanning
{
  if (IPAD)
    return;
  self.state = MWMBottomMenuStatePlanning;
}

- (void)setGo
{
  if (IPAD)
    return;
  self.state = MWMBottomMenuStateGo;
}

#pragma mark - Location button

- (void)configLocationListener
{
  typedef void (*LocationStateModeFnT)(id, SEL, location::State::Mode);
  SEL locationStateModeSelector = @selector(onLocationStateModeChanged:);
  LocationStateModeFnT locationStateModeFn =
      (LocationStateModeFnT)[self methodForSelector:locationStateModeSelector];

  self.locationListenerSlot = GetFramework().GetLocationState()->AddStateModeListener(
      bind(locationStateModeFn, self, locationStateModeSelector, _1));
}

- (void)onLocationStateModeChanged:(location::State::Mode)state
{
  self.locationState = state;
  UIButton * locBtn = self.locationButton;
  [locBtn.imageView stopAnimating];
  [locBtn.imageView.layer removeAllAnimations];
  switch (state)
  {
    case location::State::Mode::UnknownPosition:
    case location::State::Mode::NotFollow:
    case location::State::Mode::Follow:
      break;
    case location::State::Mode::PendingPosition:
    {
      [locBtn setImage:[UIImage imageNamed:@"ic_menu_location_pending"]
              forState:UIControlStateNormal];
      CABasicAnimation * rotation;
      rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
      rotation.duration = kDefaultAnimationDuration;
      rotation.toValue = @(M_PI * 2.0 * rotation.duration);
      rotation.cumulative = YES;
      rotation.repeatCount = MAXFLOAT;
      [locBtn.imageView.layer addAnimation:rotation forKey:@"locationImage"];
      break;
    }
    case location::State::Mode::RotateAndFollow:
    {
      NSUInteger const morphImagesCount = 6;
      NSUInteger const endValue = morphImagesCount + 1;
      NSMutableArray * morphImages = [NSMutableArray arrayWithCapacity:morphImagesCount];
      for (NSUInteger i = 1, j = 0; i != endValue; i++, j++)
        morphImages[j] = [UIImage imageNamed:[@"ic_follow_mode_light_" stringByAppendingString:@(i).stringValue]];
      locBtn.imageView.animationImages = morphImages;
      locBtn.imageView.animationRepeatCount = 1;
      locBtn.imageView.image = morphImages.lastObject;
      [locBtn.imageView startAnimating];
      break;
    }
  }
  [self refreshLocationButtonState];
}

- (void)refreshLocationButtonState
{
  dispatch_async(dispatch_get_main_queue(), ^
  {
    if (self.locationButton.imageView.isAnimating)
    {
      [self refreshLocationButtonState];
    }
    else
    {
      UIButton * locBtn = self.locationButton;
      switch (self.locationState)
      {
        case location::State::Mode::PendingPosition:
          break;
        case location::State::Mode::UnknownPosition:
          [locBtn setImage:[UIImage imageNamed:@"ic_menu_location_off_mode_light"] forState:UIControlStateNormal];
          break;
        case location::State::Mode::NotFollow:
          [locBtn setImage:[UIImage imageNamed:@"ic_menu_location_get_position"] forState:UIControlStateNormal];
          break;
        case location::State::Mode::Follow:
          [locBtn setImage:[UIImage imageNamed:@"ic_menu_location_follow"] forState:UIControlStateNormal];
          break;
        case location::State::Mode::RotateAndFollow:
          [locBtn setImage:[UIImage imageNamed:@"ic_menu_location_follow_and_rotate"] forState:UIControlStateNormal];
          break;
      }
    }
  });
}

#pragma mark - Notifications

- (void)searchStateWillChange:(NSNotification *)notification
{
  MWMSearchManagerState state =
      MWMSearchManagerState([[notification userInfo][kSearchStateKey] unsignedIntegerValue]);
  self.searchIsActive = state != MWMSearchManagerStateHidden;
}

#pragma mark - Setup

- (void)setupCollectionView
{
  [self.buttonsCollectionView registerNib:[UINib nibWithNibName:kCollectionCellPortrait bundle:nil]
               forCellWithReuseIdentifier:kCollectionCellPortrait];
  [self.buttonsCollectionView registerNib:[UINib nibWithNibName:kCollectionCelllandscape bundle:nil]
               forCellWithReuseIdentifier:kCollectionCelllandscape];
  MWMBottomMenuLayout * cvLayout =
      (MWMBottomMenuLayout *)self.buttonsCollectionView.collectionViewLayout;
  cvLayout.buttonsCount = MWMBottomMenuViewCellCount;
  cvLayout.layoutThreshold = kLayoutThreshold;
  ((MWMBottomMenuView *)self.view).layoutThreshold = kLayoutThreshold;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(nonnull UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section
{
  return MWMBottomMenuViewCellCount;
}

- (nonnull UICollectionViewCell *)collectionView:(nonnull UICollectionView *)collectionView
                          cellForItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  BOOL const isWideMenu = self.view.width > kLayoutThreshold;
  MWMBottomMenuCollectionViewCell * cell =
      [collectionView dequeueReusableCellWithReuseIdentifier:isWideMenu ? kCollectionCelllandscape
                                                                        : kCollectionCellPortrait
                                                forIndexPath:indexPath];
  switch (indexPath.item)
  {
  case MWMBottomMenuViewCellDownload:
  {
    NSUInteger const badgeCount =
        GetFramework().GetCountryTree().GetActiveMapLayout().GetOutOfDateCount();
    [cell configureWithIconName:@"ic_menu_download"
                          label:L(@"download_maps")
                     badgeCount:badgeCount];
  }
  break;
  case MWMBottomMenuViewCellSettings:
    [cell configureWithIconName:@"ic_menu_settings" label:L(@"settings") badgeCount:0];
    break;
  case MWMBottomMenuViewCellShare:
    [cell configureWithIconName:@"ic_menu_share" label:L(@"share_my_location") badgeCount:0];
    break;
  case MWMBottomMenuViewCellCount:
    break;
  }
  return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(nonnull UICollectionView *)collectionView
    didSelectItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  switch (indexPath.item)
  {
  case MWMBottomMenuViewCellDownload:
    [self menuActionDownloadMaps];
    break;
  case MWMBottomMenuViewCellSettings:
    [self menuActionOpenSettings];
    break;
  case MWMBottomMenuViewCellShare:
    [self menuActionShareLocation];
    break;
  case MWMBottomMenuViewCellCount:
    break;
  }
}

- (void)collectionView:(nonnull UICollectionView *)collectionView
    didHighlightItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  MWMBottomMenuCollectionViewCell * cell =
      (MWMBottomMenuCollectionViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
  [cell highlighted:YES];
}

- (void)collectionView:(nonnull UICollectionView *)collectionView
    didUnhighlightItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  MWMBottomMenuCollectionViewCell * cell =
      (MWMBottomMenuCollectionViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
  [cell highlighted:NO];
}

#pragma mark - Buttons actions

- (void)menuActionDownloadMaps
{
  [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatDownloadMaps}];
  self.state = self.restoreState;
  [self.delegate actionDownloadMaps];
}

- (void)menuActionOpenSettings
{
  [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatSettings}];
  self.state = self.restoreState;
  [Alohalytics logEvent:kAlohalyticsTapEventKey withValue:@"settingsAndMore"];
  SettingsAndMoreVC * const vc = [[SettingsAndMoreVC alloc] initWithStyle:UITableViewStyleGrouped];
  [self.controller.navigationController pushViewController:vc animated:YES];
}

- (void)menuActionShareLocation
{
  [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatShare}];
  [Alohalytics logEvent:kAlohalyticsTapEventKey withValue:@"share@"];
  CLLocation * location = [MapsAppDelegate theApp].m_locationManager.lastLocation;
  if (!location)
  {
    [[[UIAlertView alloc] initWithTitle:L(@"unknown_current_position")
                                message:nil
                               delegate:nil
                      cancelButtonTitle:L(@"ok")
                      otherButtonTitles:nil] show];
    return;
  }
  CLLocationCoordinate2D const coord = location.coordinate;
  NSIndexPath * cellIndex = [NSIndexPath indexPathForItem:MWMBottomMenuViewCellShare inSection:0];
  MWMBottomMenuCollectionViewCell * cell =
      (MWMBottomMenuCollectionViewCell *)[self.additionalButtons cellForItemAtIndexPath:cellIndex];
  MWMActivityViewController * shareVC =
      [MWMActivityViewController shareControllerForLocationTitle:nil location:coord myPosition:YES];
  [shareVC presentInParentViewController:self.controller anchorView:cell.icon];
}

- (IBAction)locationButtonTouchUpInside:(UIButton *)sender
{
  [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatLocation}];
  GetFramework().GetLocationState()->SwitchToNextMode();
}

- (IBAction)point2PointButtonTouchUpInside:(UIButton *)sender
{
  [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatPointToPoint}];
  self.state = self.restoreState;
  BOOL const isSelected = !sender.isSelected;
  sender.selected = isSelected;
  MapsAppDelegate * theApp = [MapsAppDelegate theApp];
  if (isSelected)
  {
    theApp.routingPlaneMode = MWMRoutingPlaneModePlacePage;
    [self.controller.controlsManager routingPrepare];
  }
  else
  {
    if (theApp.routingPlaneMode == MWMRoutingPlaneModeSearchDestination || theApp.routingPlaneMode == MWMRoutingPlaneModeSearchSource)
      self.controller.controlsManager.searchHidden = YES;
    [self.controller.controlsManager routingHidden];
  }
}

- (IBAction)searchButtonTouchUpInside:(UIButton *)sender
{
  [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatSearch}];
  [Alohalytics logEvent:kAlohalyticsTapEventKey withValue:@"search"];
  self.state = self.restoreState;
  self.controller.controlsManager.searchHidden = self.searchIsActive;
}

- (IBAction)bookmarksButtonTouchUpInside:(UIButton *)sender
{
  [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatBookmarks}];
  [Alohalytics logEvent:kAlohalyticsTapEventKey withValue:@"bookmarks"];
  self.state = self.restoreState;
  [self.controller openBookmarks];
}

- (IBAction)menuButtonTouchUpInside:(UIButton *)sender
{
  switch (self.state)
  {
  case MWMBottomMenuStateHidden:
    NSAssert(false, @"Incorrect state");
    break;
  case MWMBottomMenuStateInactive:
  case MWMBottomMenuStatePlanning:
  case MWMBottomMenuStateGo:
  case MWMBottomMenuStateText:
    [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatExpand}];
    self.state = MWMBottomMenuStateActive;
    break;
  case MWMBottomMenuStateActive:
    [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatCollapse}];
    self.state = self.restoreState;
    break;
  case MWMBottomMenuStateCompact:
    [[Statistics instance] logEvent:kStatMenu withParameters:@{kStatButton : kStatRegular}];
    [self.delegate closeInfoScreens];
    break;
  }
}
- (IBAction)goButtonTouchUpInside:(UIButton *)sender
{
  [self.controller.controlsManager routingNavigation];
}

- (void)dimBackgroundTap
{
  // In case when there are 2 touch events (dimBackgroundTap & menuButtonTouchUpInside)
  // if dimBackgroundTap is processed first then menuButtonTouchUpInside behaves as if menu is
  // inactive this is wrong case, so we postpone dimBackgroundTap to make sure
  // menuButtonTouchUpInside processed first
  dispatch_async(dispatch_get_main_queue(), ^{ self.state = self.restoreState; });
}

- (void)toggleDimBackgroundVisible:(BOOL)visible
{
  if (visible)
    [self.controller.view insertSubview:self.dimBackground belowSubview:self.view];
  self.dimBackground.alpha = visible ? 0.0 : 0.8;
  [UIView animateWithDuration:kDefaultAnimationDuration animations:^
  {
    self.dimBackground.alpha = visible ? 0.8 : 0.0;
  }
  completion:^(BOOL finished)
  {
    if (!visible)
    {
      [self.dimBackground removeFromSuperview];
      self.dimBackground = nil;
    }
  }];
}

#pragma mark - Properties

- (SolidTouchView *)dimBackground
{
  if (!_dimBackground)
  {
    _dimBackground = [[SolidTouchView alloc] initWithFrame:self.controller.view.bounds];
    _dimBackground.backgroundColor = [UIColor fadeBackground];
    _dimBackground.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer * tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dimBackgroundTap)];
    [_dimBackground addGestureRecognizer:tap];
  }
  return _dimBackground;
}

- (void)setState:(MWMBottomMenuState)state
{
  [self toggleDimBackgroundVisible:state == MWMBottomMenuStateActive];
  MWMBottomMenuView * view = (MWMBottomMenuView *)self.view;
  if (view.state == MWMBottomMenuStateCompact &&
      (state == MWMBottomMenuStatePlanning || state == MWMBottomMenuStateGo ||
       state == MWMBottomMenuStateText))
    self.restoreState = state;
  else
    view.state = state;
}

- (MWMBottomMenuState)state
{
  return ((MWMBottomMenuView *)self.view).state;
}

- (void)setRestoreState:(MWMBottomMenuState)restoreState
{
  ((MWMBottomMenuView *)self.view).restoreState = restoreState;
}

- (MWMBottomMenuState)restoreState
{
  return ((MWMBottomMenuView *)self.view).restoreState;
}

- (void)setLeftBound:(CGFloat)leftBound
{
  ((MWMBottomMenuView *)self.view).leftBound = leftBound;
}

- (CGFloat)leftBound
{
  return ((MWMBottomMenuView *)self.view).leftBound;
}

- (void)setSearchIsActive:(BOOL)searchIsActive
{
  ((MWMBottomMenuView *)self.view).searchIsActive = searchIsActive;
}

- (BOOL)searchIsActive
{
  return ((MWMBottomMenuView *)self.view).searchIsActive;
}

@end
