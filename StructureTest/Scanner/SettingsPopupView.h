/*
 This file is part of the Structure SDK.
 Copyright © 2019 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#pragma once

#import <Foundation/Foundation.h>
#import <Structure/STCaptureSession+Types.h>
#import <UIKit/UIKit.h>

enum DepthResolution
{
    DepthResolution_Qvga,
    DepthResolution_Vga,
    DepthResolution_Full
};

@protocol SettingsPopupViewDelegate

- (void)streamingSettingsDidChange:(BOOL)highResolutionColorEnabled
                   depthResolution:(DepthResolution)depthResolution
             depthStreamPresetMode:(STCaptureSessionPreset)depthStreamPresetMode;

- (void)streamingPropertiesDidChange:(BOOL)irAutoExposureEnabled
               irManualExposureValue:(float)irManualExposureValue
                   irAnalogGainValue:(STCaptureSessionSensorAnalogGainMode)irAnalogGainValue;

- (void)slamOptionDidChange:(BOOL)stSlamManagerSelected;

- (void)trackerSettingsDidChange:(BOOL)rgbdTrackingEnabled;

- (void)mapperSettingsDidChange:(BOOL)highResolutionMeshEnabled improvedMapperEnabled:(BOOL)improvedMapperEnabled;

@end

@interface SettingsPopupView : UIView

- (instancetype)initWithSettingsPopupViewDelegate:(id<SettingsPopupViewDelegate>)delegate;
- (void)enableAllSettingsDuringCubePlacement;
- (void)disableNonDynamicSettingsDuringScanning;

@end
