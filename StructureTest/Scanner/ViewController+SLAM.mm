/*
  This file is part of the Structure SDK.
  Copyright © 2019 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"
#import "ViewController+CaptureSession.h"
#import "ViewController+OpenGL.h"

#import <Structure/Structure.h>

#pragma mark - Utilities

static float deltaRotationAngleBetweenPosesInDegrees(const GLKMatrix4& previousPose, const GLKMatrix4& newPose)
{
    GLKMatrix4 deltaPose = GLKMatrix4Multiply(
        newPose,
        // Transpose is equivalent to inverse since we will only use the rotation part.
        GLKMatrix4Transpose(previousPose));

    // Get the rotation component of the delta pose
    GLKQuaternion deltaRotationAsQuaternion = GLKQuaternionMakeWithMatrix4(deltaPose);

    // Get the angle of the rotation
    const float angleInDegree = GLKQuaternionAngle(deltaRotationAsQuaternion) / M_PI * 180;

    return angleInDegree;
}

static NSString* computeTrackerMessage(STTrackerHints hints)
{
    if (hints.trackerIsLost)
        return @"Tracking Lost! Please Realign or Press Reset.";

    if (hints.modelOutOfView)
        return @"Please put the model back in view.";

    if (hints.sceneIsTooClose)
        return @"Too close to the scene! Please step back.";

    return nil;
}

@implementation ViewController (SLAM)

#pragma mark - SLAM

// Set up SLAM related objects.
- (void)setupSLAM
{
    if (_slamState.initialized)
        return;

    if (_dynamicOptions.stSlamManagerIsSelected)
    {
        _slamState.slamOption = SlamOption::STSlamManager;
    }
    else
    {
        _slamState.slamOption = SlamOption::Default;
    }
    // Initialize the scene.
    _slamState.scene = [[STScene alloc] initWithContext:_display.context];

    if (_slamState.slamOption == SlamOption::STSlamManager)
    {
        // do nothing
    }
    else
    {
        NSLog(@"ObjectScanning Tracker is selected");
        // Initialize the camera pose tracker.
        NSDictionary* trackerOptions = @{
            kSTTrackerTypeKey: _dynamicOptions.depthAndColorTrackerIsOn ? @(STTrackerDepthAndColorBased)
                                                                        : @(STTrackerDepthBased),
            kSTTrackerTrackAgainstModelKey:
                @TRUE, // tracking against the model is much better for close range scanning.
            kSTTrackerQualityKey: @(STTrackerQualityAccurate),
            kSTTrackerBackgroundProcessingEnabledKey: @YES,
            kSTTrackerSceneTypeKey: @(STTrackerSceneTypeObject),
            kSTTrackerLegacyKey: @(YES)
        };
        // Initialize the camera pose tracker.
        _slamState.tracker = [[STTracker alloc] initWithScene:_slamState.scene options:trackerOptions];
    }


    // Default volume size set in options struct
    if (isnan(_slamState.volumeSizeInMeters.x))
        _slamState.volumeSizeInMeters = _options.initVolumeSizeInMeters;

    // The mapper will be initialized when we start scanning.
    if (!_fixedCubePosition)
    {
        // Setup the cube placement initializer.
        _slamState.cameraPoseInitializer =
            [[STCameraPoseInitializer alloc] initWithVolumeSizeInMeters:_slamState.volumeSizeInMeters options:@{
                kSTCameraPoseInitializerStrategyKey: @(STCameraPoseInitializerStrategyTableTopCube)
            }];
    }
    else
    {

        // Setup the cube placement initializer.
        _slamState.cameraPoseInitializer =
            [[STCameraPoseInitializer alloc] initWithVolumeSizeInMeters:_slamState.volumeSizeInMeters options:@{
                kSTCameraPoseInitializerStrategyKey: @(STCameraPoseInitializerStrategyGravityAlignedAtVolumeCenter)
            }];
    }

    // Set up the cube renderer with the current volume size.
    _display.cubeRenderer = [[STCubeRenderer alloc] initWithContext:_display.context];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    if ([defaults integerForKey:@"depthRenderingColoring"] == 1)
    {
        GLKVector3 rainbow[] = {
            {0.0f, 0.0f, 1.0f}, // Blue
            {0.0f, 1.0f, 1.0f}, // Aqua
            {0.0f, 1.0f, 0.0f}, // Green
            {1.0f, 1.0f, 0.0f}, // Yellow
            {1.0f, 0.0f, 0.0f}, // Red
        };
        [_display.cubeRenderer setDepthRenderingColors:rainbow numColors:sizeof(rainbow) / sizeof(GLKVector3)];
    }

    // Set up the initial volume size.
    [self adjustVolumeSize:_slamState.volumeSizeInMeters];

    // Restart CaptureSession and enter cube placement state
    //[self restartCaptureSession];
    [self enterCubePlacementState];

    NSDictionary* keyframeManagerOptions = @{
        kSTKeyFrameManagerMaxSizeKey: @(_options.maxNumKeyFrames),
        kSTKeyFrameManagerMaxDeltaTranslationKey: @(_options.maxKeyFrameTranslation),
        kSTKeyFrameManagerMaxDeltaRotationKey: @(_options.maxKeyFrameRotation), // 20 degrees.
    };

    _slamState.keyFrameManager = [[STKeyFrameManager alloc] initWithOptions:keyframeManagerOptions];

    _depthAsRgbaVisualizer =
        [[STDepthToRgba alloc] initWithOptions:@{kSTDepthToRgbaStrategyKey: @(STDepthToRgbaStrategyGray)}];

    _slamState.initialized = true;
}

- (void)resetSLAM
{
    _slamState.prevFrameTimeStamp = -1.0;
    [_slamState.mapper reset];
    [_slamState.lssTracker reset];
    [_slamState.tracker reset];
    [_slamState.scene clear];
    [_slamState.keyFrameManager clear];

    [self enterCubePlacementState];
}

- (void)clearSLAM
{
    _slamState.initialized = false;
    _slamState.scene = nil;
    _slamState.lssTracker = nil;
    _slamState.tracker = nil;
    if (_slamState.mapper)
        [_slamState.mapper reset];
    _slamState.mapper = nil;
    _slamState.keyFrameManager = nil;
}

- (void)setupMapper
{
    if (_slamState.slamOption == SlamOption::STSlamManager)
    {
        if (_slamState.lssTracker)
            _slamState.lssTracker = nil;

        NSDictionary* trackerOptions = @{
            kSTMapperVolumeResolutionKey: @(0.003),
            kSTMapperVolumeBoundsKey: @[
                @(_slamState.volumeSizeInMeters.x),
                @(_slamState.volumeSizeInMeters.y),
                @(_slamState.volumeSizeInMeters.z)
            ],
        };
        _slamState.lssTracker = [[STSLAMManager alloc] initWithScene:_slamState.scene options:trackerOptions];
    }
    else
    {
        if (_slamState.mapper)
        {
            [_slamState.mapper reset];
            _slamState.mapper = nil; // make sure we first remove a previous mapper.
        }

        // Here, we set a larger volume bounds size when mapping in high resolution.
        const float lowResolutionVolumeBounds = 125;
        const float highResolutionVolumeBounds = 200;

        float voxelSizeInMeters = _slamState.volumeSizeInMeters.x /
            (_dynamicOptions.highResMapping ? highResolutionVolumeBounds : lowResolutionVolumeBounds);

        // Avoid voxels that are too small - these become too noisy.
        voxelSizeInMeters = keepInRange(voxelSizeInMeters, 0.003, 0.2);

        // Compute the volume bounds in voxels, as a multiple of the volume resolution.
        GLKVector3 volumeBounds;
        volumeBounds.x = roundf(_slamState.volumeSizeInMeters.x / voxelSizeInMeters);
        volumeBounds.y = roundf(_slamState.volumeSizeInMeters.y / voxelSizeInMeters);
        volumeBounds.z = roundf(_slamState.volumeSizeInMeters.z / voxelSizeInMeters);

        NSLog(
            @"[Mapper] volumeSize (m): %f %f %f volumeBounds: %.0f %.0f %.0f (resolution=%f m)",
            _slamState.volumeSizeInMeters.x,
            _slamState.volumeSizeInMeters.y,
            _slamState.volumeSizeInMeters.z,
            volumeBounds.x,
            volumeBounds.y,
            volumeBounds.z,
            voxelSizeInMeters);

        NSDictionary* mapperOptions = @{
            kSTMapperLegacyKey: @(!_dynamicOptions.improvedMapperIsOn),
            kSTMapperVolumeResolutionKey: @(voxelSizeInMeters),
            kSTMapperVolumeBoundsKey: @[@(volumeBounds.x), @(volumeBounds.y), @(volumeBounds.z)],
            kSTMapperVolumeHasSupportPlaneKey: @(_slamState.cameraPoseInitializer.lastOutput.hasSupportPlane),
            kSTMapperEnableLiveWireFrameKey: @NO,
        };

        _slamState.mapper = [[STMapper alloc] initWithScene:_slamState.scene options:mapperOptions];
    }
}

- (NSString*)maybeAddKeyframeWithDepthFrame:(STDepthFrame*)depthFrame
                                 colorFrame:(STColorFrame*)colorFrame
              depthCameraPoseBeforeTracking:(GLKMatrix4)depthCameraPoseBeforeTracking
{
    if (colorFrame == nil)
        return nil; // nothing to do

    GLKMatrix4 depthCameraPoseAfterTracking;

    if (_slamState.slamOption == SlamOption::STSlamManager)
    {
        // Only consider adding a new keyframe if the accuracy is high enough.
        if (_slamState.lssTracker.poseAccuracy < STTrackerPoseAccuracyApproximate)
            return nil;

        depthCameraPoseAfterTracking = [_slamState.lssTracker lastFrameCameraPose];
    }
    else
    {
        if (_slamState.slamOption == SlamOption::STSlamManager)
        {
            // Only consider adding a new keyframe if the accuracy is high enough.
            if (_slamState.lssTracker.poseAccuracy < STTrackerPoseAccuracyApproximate)
                return nil;

            depthCameraPoseAfterTracking = [_slamState.lssTracker lastFrameCameraPose];
        }
        else
        {
            // Only consider adding a new keyframe if the accuracy is high enough.
            if (_slamState.tracker.poseAccuracy < STTrackerPoseAccuracyApproximate)
                return nil;

            depthCameraPoseAfterTracking = [_slamState.tracker lastFrameCameraPose];
        }
    }


    // Make sure the pose is in color camera coordinates in case we are not using registered depth.
    GLKMatrix4 iOSColorFromDepthExtrinsics = [depthFrame iOSColorFromDepthExtrinsics];
    GLKMatrix4 colorCameraPoseAfterTracking =
        GLKMatrix4Multiply(depthCameraPoseAfterTracking, GLKMatrix4Invert(iOSColorFromDepthExtrinsics, nil));

    bool showHoldDeviceStill = false;

    // Check if the viewpoint has moved enough to add a new keyframe
    // OR if we don't have a keyframe yet
    if ([_slamState.keyFrameManager wouldBeNewKeyframeWithColorCameraPose:colorCameraPoseAfterTracking])
    {
        const bool isFirstFrame = (_slamState.prevFrameTimeStamp < 0.);
        bool canAddKeyframe = false;

        if (isFirstFrame)
        {
            canAddKeyframe = true;
        }
        else // check the speed.
        {
            float deltaAngularSpeedInDegreesPerSecond = FLT_MAX;
            NSTimeInterval deltaSeconds = depthFrame.timestamp - _slamState.prevFrameTimeStamp;

            // Compute angular speed
            deltaAngularSpeedInDegreesPerSecond =
                deltaRotationAngleBetweenPosesInDegrees(depthCameraPoseBeforeTracking, depthCameraPoseAfterTracking) /
                deltaSeconds;

            // If the camera moved too much since the last frame, we will likely end up
            // with motion blur and rolling shutter, especially in case of rotation. This
            // checks aims at not grabbing keyframes in that case.
            if (deltaAngularSpeedInDegreesPerSecond < _options.maxKeyframeRotationSpeedInDegreesPerSecond)
            {
                canAddKeyframe = true;
            }
        }

        if (canAddKeyframe)
        {
            [_slamState.keyFrameManager
                processKeyFrameCandidateWithColorCameraPose:colorCameraPoseAfterTracking
                                                 colorFrame:colorFrame
                                                 depthFrame:nil]; // Spare the depth frame memory, since we do not need
                                                                  // it in keyframes.
        }
        else
        {
            // Moving too fast. Hint the user to slow down to capture a keyframe
            // without rolling shutter and motion blur.
            showHoldDeviceStill = YES;
        }
    }

    if (showHoldDeviceStill)
        return @"Please hold still so we can capture a keyframe...";

    return nil;
}

- (void)updateMeshAlphaForPoseAccuracy:(STTrackerPoseAccuracy)poseAccuracy
{
    switch (poseAccuracy)
    {
        case STTrackerPoseAccuracyHigh:
        case STTrackerPoseAccuracyApproximate: _display.meshRenderingAlpha = 0.8; break;

        case STTrackerPoseAccuracyLow:
        {
            _display.meshRenderingAlpha = 0.4;
            break;
        }

        case STTrackerPoseAccuracyVeryLow:
        case STTrackerPoseAccuracyNotAvailable:
        {
            _display.meshRenderingAlpha = 0.1;
            break;
        }

        default: NSLog(@"STTracker unknown pose accuracy.");
    };
}

- (void)processDepthFrame:(STDepthFrame*)depthFrame colorFrameOrNil:(STColorFrame*)colorFrame
{
    if (_options.applyExpensiveCorrectionToDepth)
    {
        NSAssert(
            !_options.useHardwareRegisteredDepth,
            @"Cannot enable both expensive depth correction and registered depth.");
        BOOL couldApplyCorrection = [depthFrame applyExpensiveCorrection];
        if (!couldApplyCorrection)
        {
            NSLog(@"Warning: could not improve depth map accuracy, is your firmware too old?");
        }
    }

    if (_runDepthRefinement)
    {
        [depthFrame applyDepthRefinement];
    }

    // Upload the new color image for next rendering.
    if (_useColorCamera && colorFrame == nil)
    {
        return;
    }
    else if (colorFrame != nil)
    {
        [self uploadGLColorTexture:colorFrame];
    }
    else if (!_useColorCamera)
    {
        [self uploadGLColorTextureFromDepth:depthFrame];
    }

    // Update the projection matrices since we updated the frames.
    {
        _display.depthCameraGLProjectionMatrix = [depthFrame glProjectionMatrix];
        if (colorFrame)
        {
            _display.colorCameraGLProjectionMatrix = [colorFrame glProjectionMatrix];
        }
    }

    switch (_slamState.scannerState)
    {
        case ScannerStateCubePlacement:
        {
            STDepthFrame* depthFrameForCubeInitialization = depthFrame;
            GLKMatrix4 depthCameraPoseInColorCoordinateFrame = GLKMatrix4Identity;

            // If we are using color images but not using registered depth, then use a registered
            // version to detect the cube, otherwise the cube won't be centered on the color image,
            // but on the depth image, and thus appear shifted.
            if (_useColorCamera && !_options.useHardwareRegisteredDepth)
            {
                depthCameraPoseInColorCoordinateFrame = [depthFrame iOSColorFromDepthExtrinsics];
                depthFrameForCubeInitialization = [depthFrame registeredToColorFrame:colorFrame];
            }

            // Provide the new depth frame to the cube renderer for ROI highlighting.
            [_display.cubeRenderer setDepthFrame:depthFrameForCubeInitialization];

            // Estimate the new scanning volume position.
            if (GLKVector3Length(_lastGravity) > 1e-5f)
            {
                bool success =
                    [_slamState.cameraPoseInitializer updateCameraPoseWithGravity:_lastGravity
                                                                       depthFrame:depthFrameForCubeInitialization
                                                                            error:nil];

                // Since we potentially detected the cube in a registered depth frame, also save the pose
                // in the original depth sensor coordinate system since this is what we'll use for SLAM
                // to get the best accuracy.
                _slamState.initialDepthCameraPose = GLKMatrix4Multiply(
                    _slamState.cameraPoseInitializer.lastOutput.cameraPose,
                    depthCameraPoseInColorCoordinateFrame);

                if (!success)
                {
                    NSLog(@"Camera pose initializer error.");
                }
            }

            // Tell the cube renderer whether there is a support plane or not.
            [_display.cubeRenderer setCubeHasSupportPlane:_slamState.cameraPoseInitializer.lastOutput.hasSupportPlane];

            // Enable the scan button if the pose initializer could estimate a pose.
            self.scanButton.enabled = _slamState.cameraPoseInitializer.lastOutput.hasValidPose;
            break;
        }

        case ScannerStateScanning:
        {
            // First try to estimate the 3D pose of the new frame.
            NSError* trackingError = nil;

            NSString* trackingMessage = nil;

            NSString* keyframeMessage = nil;

            GLKMatrix4 depthCameraPoseBeforeTracking;

            BOOL trackingOk;

            if (_slamState.slamOption == SlamOption::STSlamManager)
            {
                depthCameraPoseBeforeTracking = [_slamState.lssTracker lastFrameCameraPose];

                trackingOk = [_slamState.lssTracker updateCameraPoseWithDepthFrame:depthFrame colorFrame:colorFrame
                                                                             error:&trackingError];
            }
            else
            {
                depthCameraPoseBeforeTracking = [_slamState.tracker lastFrameCameraPose];

                trackingOk = [_slamState.tracker updateCameraPoseWithDepthFrame:depthFrame colorFrame:colorFrame
                                                                          error:&trackingError];
            }

            // Integrate it into the current mesh estimate if tracking was successful.
            if (!trackingOk)
            {
                NSLog(@"[Structure] STTracker Error: %@.", [trackingError localizedDescription]);
            }
            else
            {
                if (_slamState.slamOption == SlamOption::STSlamManager)
                {
                    // Update the tracking message.
                    trackingMessage = computeTrackerMessage(_slamState.lssTracker.trackerHints);
                    // Set the mesh transparency depending on the current accuracy.
                    [self updateMeshAlphaForPoseAccuracy:_slamState.lssTracker.poseAccuracy];

                    // If the tracker accuracy is high, use this frame for mapper update and maybe as a keyframe too.
                    if (_slamState.lssTracker.poseAccuracy >= STTrackerPoseAccuracyHigh)
                    {
                        //[_slamState.mapper integrateDepthFrame:depthFrame cameraPose:[_slamState.lssTracker
                        //lastFrameCameraPose]];
                    }
                }
                else
                {
                    // Update the tracking message.
                    trackingMessage = computeTrackerMessage(_slamState.tracker.trackerHints);
                    // Set the mesh transparency depending on the current accuracy.
                    [self updateMeshAlphaForPoseAccuracy:_slamState.tracker.poseAccuracy];

                    // If the tracker accuracy is high, use this frame for mapper update and maybe as a keyframe too.
                    if (_slamState.tracker.poseAccuracy >= STTrackerPoseAccuracyHigh)
                    {
                        [_slamState.mapper integrateDepthFrame:depthFrame
                                                    cameraPose:[_slamState.tracker lastFrameCameraPose]];
                    }
                }

                keyframeMessage = [self maybeAddKeyframeWithDepthFrame:depthFrame colorFrame:colorFrame
                                         depthCameraPoseBeforeTracking:depthCameraPoseBeforeTracking];

                if (trackingMessage) // Tracking messages have higher priority.
                    [self showTrackingMessage:trackingMessage];
                else if (keyframeMessage)
                    [self showTrackingMessage:keyframeMessage];
                else
                    [self hideTrackingErrorMessage];
            }

            _slamState.prevFrameTimeStamp = depthFrame.timestamp;

            break;
        }

        case ScannerStateViewing:
        default:
        {
        } // Do nothing, the MeshViewController will take care of this.
    }
}

@end
