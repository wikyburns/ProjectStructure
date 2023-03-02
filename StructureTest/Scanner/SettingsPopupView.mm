/*
 This file is part of the Structure SDK.
 Copyright © 2019 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "SettingsPopupView.h"
#import "ViewUtilities.h"

@interface DropDownView : UITableView <UITableViewDelegate, UITableViewDataSource>
- (instancetype)initWithOpt:(NSArray<NSString*>*)options activeIndex:(NSUInteger)index;
- (void)setOnChangedTarget:(void (^)(NSUInteger selectedIndex))action;

@property(nonatomic) NSUInteger selectedIndex;

@end

typedef void (^_Action)(NSUInteger);
@implementation DropDownView
{
    NSArray<NSString*>* _options;
    NSString* _cellReuseIdentifier;
    NSLayoutConstraint* _heightConstraint;
    BOOL _isShown;
    NSUInteger _activeIndex;

    _Action _action;
}

- (instancetype)initWithOpt:(NSArray<NSString*>*)options activeIndex:(NSUInteger)index
{
    // init
    self = [super init];
    _options = options;
    _cellReuseIdentifier = @"cell";
    _isShown = NO;
    _activeIndex = index;

    [self registerClass:UITableViewCell.self forCellReuseIdentifier:_cellReuseIdentifier];

    _heightConstraint = [self.heightAnchor constraintEqualToConstant:0];
    _heightConstraint.active = YES;

    self.dataSource = self;
    self.delegate = self;

    [self layoutIfNeeded];
    [self reloadData];
    _heightConstraint.constant = self.contentSize.height;

    return self;
}

- (nonnull UITableViewCell*)tableView:(nonnull UITableView*)tableView
                cellForRowAtIndexPath:(nonnull NSIndexPath*)indexPath
{
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:_cellReuseIdentifier forIndexPath:indexPath];

    const NSUInteger iRow = [indexPath indexAtPosition:1];
    if (iRow == 0) // header
    {
        cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
        cell.textLabel.textColor = colorFromHexString(@"3A3A3C");
        cell.backgroundColor = colorFromHexString(@"#DEDEDE");
        cell.textLabel.text = _options[_activeIndex];
    }
    else if (iRow - 1 == _activeIndex) // selected cell
    {
        cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.backgroundColor = colorFromHexString(@"#00C3FF");
        cell.textLabel.text = _options[iRow - 1];
    }
    else
    {
        cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
        cell.textLabel.textColor = colorFromHexString(@"505053");
        cell.backgroundColor = colorFromHexString(@"#DEDEDE");
        cell.textLabel.text = _options[iRow - 1];
    }
    return cell;
}

- (NSInteger)tableView:(nonnull UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return _isShown ? 1 + [_options count] : 1;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    if (_isShown)
    {
        _isShown = NO;
        const NSUInteger iRow = [indexPath indexAtPosition:1];
        if (iRow > 0 && _activeIndex != (iRow - 1))
        {
            _activeIndex = iRow - 1;
            if (_action)
                _action(_activeIndex);
        }
    }
    else
        _isShown = YES;

    [self reloadData];
    _heightConstraint.constant = self.contentSize.height;
    [self layoutIfNeeded];
}

- (void)setOnChangedTarget:(void (^)(NSUInteger selectedIndex))action
{
    _action = action;
}

- (NSUInteger)selectedIndex
{
    return _activeIndex;
}

- (void)setSelectedIndex:(NSUInteger)index
{
    _activeIndex = index;
    [self reloadData];
}

@end

@interface SettingsListModal : UIScrollView

@end

@implementation SettingsListModal
{
    id<SettingsPopupViewDelegate> _delegate;

    CGFloat marginSize;
    UIView* _contentView;

    // Objects that correspond to dynamic option settings
    UISegmentedControl* depthResolutionControl;
    UISwitch* highResolutionColorSwitch;
    UISwitch* irAutoExposureSwitch;
    UISlider* irManualExposureSlider;
    UISegmentedControl* irGainSegmentedControl;
    DropDownView* _streamPresetDropControl;
    UISegmentedControl* trackerTypeSegmentedControl;
    UISegmentedControl* slamOptionSegmentedControl;
    UISwitch* highResolutionMeshSwitch;
    UISwitch* improvedMapperSwitch;
}

- (instancetype)initWithSettingsPopupViewDelegate:(id<SettingsPopupViewDelegate>)delegate
{
    self = [super init];

    if (self)
    {
        _delegate = delegate;
        marginSize = 18.0;
        [self setupUIComponentsAndLayout];

        // Default option states
        depthResolutionControl.selectedSegmentIndex = 1; // VGA
        highResolutionColorSwitch.on = YES;
        irAutoExposureSwitch.on = YES;
        irManualExposureSlider.value = 14;
        irManualExposureSlider.enabled = !irAutoExposureSwitch.on;

        irGainSegmentedControl.selectedSegmentIndex = 2; // 4x
        _streamPresetDropControl.selectedIndex = 0;
        trackerTypeSegmentedControl.selectedSegmentIndex = 0;
        slamOptionSegmentedControl.selectedSegmentIndex = 0;
        highResolutionMeshSwitch.on = YES;
        improvedMapperSwitch.on = YES;

        [self addTouchResponders];

        // NOTE: sreamingSettingsDidChange should call streamingPropertiesDidChange
        [self streamingOptionsDidChange:_streamPresetDropControl];
        [self slamOptionDidChange:self];
        [self trackerSettingsDidChange:self];
        [self mapperSettingsDidChange:self];
    }
    return self;
}

+ (void)setConstraintsFor:(UIView*)view below:(UIView*)anchor margin:(CGFloat)margin
{
    NSLayoutYAxisAnchor* topAnchor = anchor ? anchor.bottomAnchor : view.superview.layoutMarginsGuide.topAnchor;
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:topAnchor constant:anchor ? margin : 0.0],
        [view.leadingAnchor constraintEqualToAnchor:view.superview.layoutMarginsGuide.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:view.superview.layoutMarginsGuide.trailingAnchor],
    ]];
}

+ (void)pinToViewBottom:(UIView*)view
{
    [view.bottomAnchor constraintEqualToAnchor:view.superview.layoutMarginsGuide.bottomAnchor].active = YES;
}

- (UIView*)addHorizontalRuleTo:(UIView*)parent below:(UIView*)anchor margin:(CGFloat)margin width:(CGFloat)width
{
    UIView* hr = createHorizontalRule(1.0);
    hr.backgroundColor = colorFromHexString(@"#979797");
    [parent addSubview:hr];

    [NSLayoutConstraint activateConstraints:@[
        [hr.topAnchor constraintEqualToAnchor:anchor.bottomAnchor constant:margin],
        [hr.centerXAnchor constraintEqualToAnchor:hr.superview.centerXAnchor],
        [hr.widthAnchor constraintEqualToAnchor:hr.superview.widthAnchor multiplier:width],
    ]];

    return hr;
}

- (UIView*)addOptionGroupViewTo:(UIView*)parent below:(UIView*)anchor margin:(CGFloat)margin label:(NSString*)text
{
    UIView* topLine = nil;
    if (anchor)
        topLine = [self addHorizontalRuleTo:parent below:anchor margin:0.0 width:1.0];

    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    label.textColor = colorFromHexString(@"505053");
    label.text = text;
    [parent addSubview:label];
    [SettingsListModal setConstraintsFor:label below:topLine margin:margin];

    UIView* bottomLine = [self addHorizontalRuleTo:parent below:label margin:9.0 width:1.0];

    UIView* subView = [[UIView alloc] init];
    subView.translatesAutoresizingMaskIntoConstraints = NO;
    subView.backgroundColor = colorFromHexString(@"#F1F1F1");
    subView.layoutMargins = UIEdgeInsetsMake(margin, margin, margin, margin);
    [parent addSubview:subView];

    [NSLayoutConstraint activateConstraints:@[
        [subView.topAnchor constraintEqualToAnchor:bottomLine.bottomAnchor],
        [subView.leadingAnchor constraintEqualToAnchor:subView.superview.leadingAnchor],
        [subView.widthAnchor constraintEqualToAnchor:subView.superview.widthAnchor],
    ]];

    return subView;
}

- (UISwitch*)addSwitchOptionTo:(UIView*)parent below:(UIView*)anchor margin:(CGFloat)margin label:(NSString*)text
{
    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
    label.textColor = colorFromHexString(@"3A3A3C");
    label.text = text;
    [parent addSubview:label];
    [SettingsListModal setConstraintsFor:label below:anchor margin:margin];

    UISwitch* switchView = [[UISwitch alloc] init];
    switchView.translatesAutoresizingMaskIntoConstraints = NO;
    switchView.userInteractionEnabled = YES;
    switchView.onTintColor = colorFromHexString(@"#00C3FF");
    [parent addSubview:switchView];

    [NSLayoutConstraint activateConstraints:@[
        [switchView.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
        [switchView.trailingAnchor constraintEqualToAnchor:switchView.superview.layoutMarginsGuide.trailingAnchor],
    ]];

    return switchView;
}

- (UISegmentedControl*)addSegmentedOptionTo:(UIView*)parent
                                      below:(UIView*)anchor
                                      label:(NSString*)text
                                    options:(NSArray<NSString*>*)options
{
    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
    label.textColor = colorFromHexString(@"3A3A3C");
    label.text = text;
    [parent addSubview:label];
    [SettingsListModal setConstraintsFor:label below:anchor margin:marginSize];

    UISegmentedControl* segmentView = [[UISegmentedControl alloc] initWithItems:options];
    segmentView.translatesAutoresizingMaskIntoConstraints = NO;
    segmentView.clipsToBounds = YES;
    segmentView.userInteractionEnabled = YES;
    segmentView.backgroundColor = colorFromHexString(@"#D2D2D2");
    segmentView.tintColor = colorFromHexString(@"#00C3FF");

    [segmentView setTitleTextAttributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: colorFromHexString(@"#505053")
    }
                               forState:UIControlStateNormal];
    [segmentView setTitleTextAttributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: [UIColor whiteColor]
    }
                               forState:UIControlStateSelected];
    [segmentView setBackgroundImage:imageWithColor(colorFromHexString(@"#DEDEDE"), CGRectMake(0.0, 0.0, 1.0, 30.0), 0.0)
                           forState:UIControlStateNormal
                         barMetrics:UIBarMetricsDefault];
    [segmentView setBackgroundImage:imageWithColor(colorFromHexString(@"#00C3FF"), CGRectMake(0.0, 0.0, 1.0, 30.0), 0.0)
                           forState:UIControlStateSelected
                         barMetrics:UIBarMetricsDefault];

    [segmentView setDividerImage:imageWithColor([UIColor clearColor], CGRectMake(0.0, 0.0, 1.0, 30.0), 0.0)
             forLeftSegmentState:UIControlStateNormal
               rightSegmentState:UIControlStateNormal
                      barMetrics:UIBarMetricsDefault];
    [segmentView setDividerImage:imageWithColor([UIColor clearColor], CGRectMake(0.0, 0.0, 1.0, 30.0), 0.0)
             forLeftSegmentState:UIControlStateNormal
               rightSegmentState:UIControlStateSelected
                      barMetrics:UIBarMetricsDefault];
    segmentView.layer.cornerRadius = 8.0f;

    [parent addSubview:segmentView];
    [SettingsListModal setConstraintsFor:segmentView below:label margin:marginSize];
    return segmentView;
}

- (UISlider*)addSliderOptionTo:(UIView*)parent
                         below:(UIView*)anchor
                         label:(NSString*)text
                       textMin:(NSString*)textMin
                       textMax:(NSString*)textMax
                           min:(float)min
                           max:(float)max
{
    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
    label.textColor = colorFromHexString(@"#3A3A3C");
    label.text = text;
    [parent addSubview:label];
    [SettingsListModal setConstraintsFor:label below:anchor margin:marginSize];

    UISlider* slider = [[UISlider alloc] init];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.tintColor = colorFromHexString(@"#00C3FF");
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.userInteractionEnabled = YES;
    [parent addSubview:slider];

    UILabel* minLabel = [[UILabel alloc] init];
    minLabel.translatesAutoresizingMaskIntoConstraints = NO;
    minLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    minLabel.textColor = colorFromHexString(@"979797");
    minLabel.text = textMin;
    [parent addSubview:minLabel];

    UILabel* maxLabel = [[UILabel alloc] init];
    maxLabel.translatesAutoresizingMaskIntoConstraints = NO;
    maxLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    maxLabel.textColor = colorFromHexString(@"979797");
    maxLabel.text = textMax;
    [parent addSubview:maxLabel];

    [NSLayoutConstraint activateConstraints:@[
        [slider.centerYAnchor constraintEqualToAnchor:label.bottomAnchor constant:marginSize],
        [minLabel.centerYAnchor constraintEqualToAnchor:slider.centerYAnchor],
        [minLabel.leftAnchor constraintEqualToAnchor:minLabel.superview.layoutMarginsGuide.leftAnchor],
        [minLabel.rightAnchor constraintEqualToAnchor:slider.leftAnchor],
        [maxLabel.centerYAnchor constraintEqualToAnchor:slider.centerYAnchor],
        [maxLabel.leftAnchor constraintEqualToAnchor:slider.rightAnchor],
        [maxLabel.rightAnchor constraintEqualToAnchor:maxLabel.superview.layoutMarginsGuide.rightAnchor],
    ]];

    return slider;
}

- (DropDownView*)addDropDownOptionTo:(UIView*)parent
                               below:(UIView*)anchor
                               label:(NSString*)text
                             options:(NSArray<NSString*>*)options
                              active:(NSInteger)index
{
    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
    label.textColor = colorFromHexString(@"3A3A3C");
    label.text = text;
    [parent addSubview:label];
    [SettingsListModal setConstraintsFor:label below:anchor margin:marginSize];

    DropDownView* dropDown = [[DropDownView alloc] initWithOpt:options activeIndex:index];
    dropDown.layer.cornerRadius = 8.0f;
    dropDown.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:dropDown];
    [SettingsListModal setConstraintsFor:dropDown below:label margin:marginSize];
    return dropDown;
}

- (void)setupUIComponentsAndLayout
{
    // Attributes that apply to the whole content view
    self.backgroundColor = [UIColor whiteColor];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = 8.0f;

    _contentView = [[UIView alloc] init];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    _contentView.clipsToBounds = YES;
    _contentView.layoutMargins = UIEdgeInsetsMake(marginSize, marginSize, marginSize, marginSize);
    [self addSubview:_contentView];

    [NSLayoutConstraint activateConstraints:@[
        [_contentView.topAnchor constraintEqualToAnchor:_contentView.superview.topAnchor],
        [_contentView.bottomAnchor constraintEqualToAnchor:_contentView.superview.bottomAnchor],
        [_contentView.leftAnchor constraintEqualToAnchor:_contentView.superview.leftAnchor],
        [_contentView.rightAnchor constraintEqualToAnchor:_contentView.superview.rightAnchor],
        [_contentView.widthAnchor constraintEqualToAnchor:_contentView.superview.widthAnchor],
    ]];

    // Streaming settings
    UIView* streamingView = [self addOptionGroupViewTo:_contentView below:nil margin:marginSize
                                                 label:@"STREAMING SETTINGS"];
    {
        depthResolutionControl = [self addSegmentedOptionTo:streamingView below:nil label:@"Depth Resolution"
                                                    options:@[@"QVGA", @"VGA", @"Full"]];

        UIView* streamingHR0 = [self addHorizontalRuleTo:streamingView below:depthResolutionControl margin:marginSize
                                                   width:0.9];

        highResolutionColorSwitch = [self addSwitchOptionTo:streamingView below:streamingHR0 margin:marginSize
                                                      label:@"High Resolution Color"];

        UIView* streamingHR1 = [self addHorizontalRuleTo:streamingView below:highResolutionColorSwitch margin:marginSize
                                                   width:0.9];
        irAutoExposureSwitch = [self addSwitchOptionTo:streamingView below:streamingHR1 margin:marginSize
                                                 label:@"IR Auto Exposure (Mark II/Pro)"];

        UIView* streamingHR2 = [self addHorizontalRuleTo:streamingView below:irAutoExposureSwitch margin:marginSize
                                                   width:0.9];
        irManualExposureSlider = [self addSliderOptionTo:streamingView below:streamingHR2
                                                   label:@"IR Manual Exposure (Mark II/Pro)"
                                                 textMin:@"1 ms"
                                                 textMax:@"16 ms"
                                                     min:1.0
                                                     max:16.0];

        UIView* streamingHR3 = [self addHorizontalRuleTo:streamingView below:irManualExposureSlider margin:marginSize
                                                   width:0.9];
        irGainSegmentedControl = [self addSegmentedOptionTo:streamingView below:streamingHR3
                                                      label:@"IR Analog Gain (Mark II/Pro)"
                                                    options:@[@"1x", @"2x", @"4x", @"8x"]];

        UIView* streamingHR4 = [self addHorizontalRuleTo:streamingView below:irGainSegmentedControl margin:marginSize
                                                   width:0.9];

        _streamPresetDropControl =
            [self addDropDownOptionTo:streamingView below:streamingHR4 label:@"Depth Stream Preset (Mark II/Pro)"
                              options:@[@"Default", @"Body", @"Medium", @"Outdoors", @"Hybrid", @"Dark Object"]
                               active:0];
        [SettingsListModal pinToViewBottom:_streamPresetDropControl];
    }

    // SLAM Settings
    UIView* slamView = [self addOptionGroupViewTo:_contentView below:streamingView margin:marginSize
                                            label:@"SLAM SETTINGS"];
    {
        slamOptionSegmentedControl = [self addSegmentedOptionTo:slamView below:nil label:@"SLAM Option"
                                                        options:@[@"Default", @"STSLAMManager"]];
        [SettingsListModal pinToViewBottom:slamOptionSegmentedControl];
    }

    // Tracker Settings
    UIView* trackerView = [self addOptionGroupViewTo:_contentView below:slamView margin:marginSize
                                               label:@"TRACKER SETTINGS"];
    {
        trackerTypeSegmentedControl = [self addSegmentedOptionTo:trackerView below:nil label:@"Tracker Type"
                                                         options:@[@"Color + Depth", @"Depth Only"]];
        [SettingsListModal pinToViewBottom:trackerTypeSegmentedControl];
    }

    // Mapper Settings
    UIView* mapperView = [self addOptionGroupViewTo:_contentView below:trackerView margin:marginSize
                                              label:@"MAPPER SETTINGS"];
    {
        highResolutionMeshSwitch = [self addSwitchOptionTo:mapperView below:nil margin:marginSize
                                                     label:@"High Resolution Mesh"];
        UIView* mapperHR1 = [self addHorizontalRuleTo:mapperView below:highResolutionMeshSwitch margin:marginSize
                                                width:0.9];

        improvedMapperSwitch = [self addSwitchOptionTo:mapperView below:mapperHR1 margin:marginSize
                                                 label:@"Improved Mapper"];
        [SettingsListModal pinToViewBottom:improvedMapperSwitch];
    }

    UIView* hr6 = [self addHorizontalRuleTo:_contentView below:mapperView margin:0.0 width:1.0];
    [SettingsListModal pinToViewBottom:hr6];
}

- (void)addTouchResponders
{
    [depthResolutionControl addTarget:self action:@selector(streamingOptionsDidChange:)
                     forControlEvents:UIControlEventValueChanged];

    [highResolutionColorSwitch addTarget:self action:@selector(streamingOptionsDidChange:)
                        forControlEvents:UIControlEventValueChanged];

    [irAutoExposureSwitch addTarget:self action:@selector(streamingPropertiesDidChange:)
                   forControlEvents:UIControlEventValueChanged];

    [irManualExposureSlider addTarget:self action:@selector(streamingPropertiesDidChange:)
                     forControlEvents:UIControlEventTouchUpInside];

    [irGainSegmentedControl addTarget:self action:@selector(streamingPropertiesDidChange:)
                     forControlEvents:UIControlEventValueChanged];

    [slamOptionSegmentedControl addTarget:self action:@selector(slamOptionDidChange:)
                         forControlEvents:UIControlEventValueChanged];

    [trackerTypeSegmentedControl addTarget:self action:@selector(trackerSettingsDidChange:)
                          forControlEvents:UIControlEventValueChanged];

    [highResolutionMeshSwitch addTarget:self action:@selector(mapperSettingsDidChange:)
                       forControlEvents:UIControlEventValueChanged];

    [improvedMapperSwitch addTarget:self action:@selector(mapperSettingsDidChange:)
                   forControlEvents:UIControlEventValueChanged];

    __weak SettingsListModal* weakSelf = self;
    __weak DropDownView* weakControl = _streamPresetDropControl;
    [_streamPresetDropControl
        setOnChangedTarget:^(NSUInteger index) { [weakSelf streamingOptionsDidChange:weakControl]; }];
}

- (void)streamingOptionsDidChange:(id)sender
{
    NSInteger index = _streamPresetDropControl.selectedIndex;
    STCaptureSessionPreset presetMode = STCaptureSessionPresetDefault;
    switch (index)
    {
        case 0: presetMode = STCaptureSessionPresetDefault; break;
        case 1: presetMode = STCaptureSessionPresetBodyScanning; break;
        case 2: presetMode = STCaptureSessionPresetMediumRange; break;
        case 3: presetMode = STCaptureSessionPresetOutdoor; break;
        case 4: presetMode = STCaptureSessionPresetHybridMode; break;
        case 5: presetMode = STCaptureSessionPresetDarkObjectScanning; break;
        default:
            @throw [NSException exceptionWithName:@"SettingsPopupView" reason:@"Unknown index found on preset setting."
                                         userInfo:nil];
            break;
    }

    if (!_delegate)
        return;
    auto depthRes = static_cast<DepthResolution>(depthResolutionControl.selectedSegmentIndex);
    [_delegate streamingSettingsDidChange:highResolutionColorSwitch.on depthResolution:depthRes
                    depthStreamPresetMode:presetMode];

    // NOTE: Everytime we restart streaming we should re-apply the properties.
    // The exposure / gain settings that are default to a preset will get reset
    // if the STCaptureSession stream config is reset as well, so we want to re-apply
    // these every time we restart streaming for consistency's sake.
    [self streamingPropertiesDidChange:nil];
}

- (void)streamingPropertiesDidChange:(id)sender
{
    // Disable manual exposure if the IR AutoExposureSwitch is on
    irManualExposureSlider.enabled = !irAutoExposureSwitch.on;
    irManualExposureSlider.tintColor =
        (irManualExposureSlider.enabled ? colorFromHexString(@"#00C3FF") : colorFromHexString(@"#979797"));

    STCaptureSessionSensorAnalogGainMode gainMode = STCaptureSessionSensorAnalogGainMode8_0;
    switch (irGainSegmentedControl.selectedSegmentIndex)
    {
        case 0: gainMode = STCaptureSessionSensorAnalogGainMode1_0; break;
        case 1: gainMode = STCaptureSessionSensorAnalogGainMode2_0; break;
        case 2: gainMode = STCaptureSessionSensorAnalogGainMode4_0; break;
        case 3: gainMode = STCaptureSessionSensorAnalogGainMode8_0; break;
        default:
            @throw [NSException exceptionWithName:@"SettingsPopupView" reason:@"Unknown index found on gain setting."
                                         userInfo:nil];
            break;
    }

    if (!_delegate)
        return;
    [_delegate streamingPropertiesDidChange:irAutoExposureSwitch.on
                      irManualExposureValue:irManualExposureSlider.value / 1000 // send value in seconds
                          irAnalogGainValue:gainMode];
}

- (void)slamOptionDidChange:(id)sender
{
    if (!_delegate)
        return;
    // selectedSegmentIndex == 1 is STSlamManager
    [_delegate slamOptionDidChange:(slamOptionSegmentedControl.selectedSegmentIndex == 1)];
}

- (void)trackerSettingsDidChange:(id)sender
{
    if (!_delegate)
        return;
    [_delegate trackerSettingsDidChange:(trackerTypeSegmentedControl.selectedSegmentIndex == 0)];
}

- (void)mapperSettingsDidChange:(id)sender
{
    if (!_delegate)
        return;
    [_delegate mapperSettingsDidChange:highResolutionMeshSwitch.on improvedMapperEnabled:improvedMapperSwitch.on];
}

- (void)disableNonDynamicSettingsDuringScanning
{
    highResolutionColorSwitch.enabled = NO;
    trackerTypeSegmentedControl.enabled = NO;
    highResolutionMeshSwitch.enabled = NO;
    improvedMapperSwitch.enabled = NO;
    slamOptionSegmentedControl.enabled = NO;
}

- (void)enableAllSettingsDuringCubePlacement
{
    highResolutionColorSwitch.enabled = YES;
    irAutoExposureSwitch.enabled = YES;
    irManualExposureSlider.enabled = YES;
    irGainSegmentedControl.enabled = YES;
    slamOptionSegmentedControl.enabled = YES;
    trackerTypeSegmentedControl.enabled = YES;
    highResolutionMeshSwitch.enabled = YES;
    improvedMapperSwitch.enabled = YES;
}

@end

@implementation SettingsPopupView
{
    UIButton* _settingsIcon;
    SettingsListModal* _settingsListModal;

    BOOL _isSettingsListModalHidden;

    NSLayoutConstraint* widthConstraintWhenListModalIsShown;
    NSLayoutConstraint* heightConstraintWhenListModalIsShown;
    NSLayoutConstraint* widthConstraintWhenListModalIsHidden;
    NSLayoutConstraint* heightConstraintWhenListModalIsHidden;
}

- (instancetype)initWithSettingsPopupViewDelegate:(id<SettingsPopupViewDelegate>)delegate
{
    self = [super init];

    if (self)
    {
        [self setupComponentsWithDelegate:delegate];
    }
    return self;
}

- (void)setupComponentsWithDelegate:(id<SettingsPopupViewDelegate>)delegate
{
    // Attributes that apply to the whole content view
    self.backgroundColor = [UIColor clearColor];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.clipsToBounds = NO;

    // Settings Icon
    _settingsIcon = [[UIButton alloc] init];
    [_settingsIcon setImage:[UIImage imageNamed:@"settings-icon.png"] forState:UIControlStateNormal];
    [_settingsIcon setImage:[UIImage imageNamed:@"settings-icon.png"] forState:UIControlStateHighlighted];
    _settingsIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _settingsIcon.contentMode = UIViewContentModeScaleAspectFit;
    [_settingsIcon addTarget:self action:@selector(settingsIconPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_settingsIcon];

    [NSLayoutConstraint activateConstraints:@[
        [_settingsIcon.topAnchor constraintEqualToAnchor:_settingsIcon.superview.topAnchor],
        [_settingsIcon.leftAnchor constraintEqualToAnchor:_settingsIcon.superview.leftAnchor],
        [_settingsIcon.widthAnchor constraintEqualToConstant:45.0],
        [_settingsIcon.heightAnchor constraintEqualToConstant:45.0],
    ]];

    // Full Settings List Modal
    _settingsListModal = [[SettingsListModal alloc] initWithSettingsPopupViewDelegate:delegate];

    const CGRect screenBounds = [[UIScreen mainScreen] bounds];
    widthConstraintWhenListModalIsShown = [self.widthAnchor constraintEqualToConstant:420.0];
    heightConstraintWhenListModalIsShown = [self.heightAnchor constraintEqualToConstant:screenBounds.size.height - 40];
    widthConstraintWhenListModalIsHidden = [self.widthAnchor constraintEqualToAnchor:_settingsIcon.widthAnchor];
    heightConstraintWhenListModalIsHidden = [self.heightAnchor constraintEqualToAnchor:_settingsIcon.heightAnchor];
    [NSLayoutConstraint
        activateConstraints:@[widthConstraintWhenListModalIsHidden, heightConstraintWhenListModalIsHidden]];

    _isSettingsListModalHidden = YES;
}

- (void)showSettingsListModal
{
    [self addSubview:_settingsListModal];

    [NSLayoutConstraint activateConstraints:@[
        [_settingsListModal.topAnchor constraintEqualToAnchor:_settingsIcon.topAnchor],
        [_settingsListModal.leftAnchor constraintEqualToAnchor:_settingsIcon.rightAnchor constant:20.0],
        [_settingsListModal.widthAnchor constraintEqualToConstant:350.0],
        [_settingsListModal.heightAnchor constraintEqualToAnchor:_settingsListModal.superview.heightAnchor],
    ]];

    [self bringSubviewToFront:_settingsListModal];
}

- (void)hideSettingsListModal
{
    [_settingsListModal removeFromSuperview];
}

- (void)settingsIconPressed:(UIButton*)sender
{
    if (_isSettingsListModalHidden)
    {
        _isSettingsListModalHidden = NO;
        [NSLayoutConstraint
            deactivateConstraints:@[widthConstraintWhenListModalIsHidden, heightConstraintWhenListModalIsHidden]];
        [NSLayoutConstraint
            activateConstraints:@[widthConstraintWhenListModalIsShown, heightConstraintWhenListModalIsShown]];
        [self showSettingsListModal];
        return;
    }

    _isSettingsListModalHidden = YES;
    [NSLayoutConstraint
        deactivateConstraints:@[widthConstraintWhenListModalIsShown, heightConstraintWhenListModalIsShown]];
    [NSLayoutConstraint
        activateConstraints:@[widthConstraintWhenListModalIsHidden, heightConstraintWhenListModalIsHidden]];
    [self hideSettingsListModal];
}

- (void)disableNonDynamicSettingsDuringScanning
{
    [_settingsListModal disableNonDynamicSettingsDuringScanning];
}

- (void)enableAllSettingsDuringCubePlacement
{
    [_settingsListModal enableAllSettingsDuringCubePlacement];
}

@end
