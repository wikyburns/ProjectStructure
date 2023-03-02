/*
 This file is part of the Structure SDK.
 Copyright © 2022 Occipital, Inc. All rights reserved.
 http://structure.io
 */


#import <UIKit/UIKit.h>
#import "DisclaimerActivityItemSource.h"

@implementation DisclaimerActivityItemSource

- (nullable id)activityViewController:(nonnull UIActivityViewController *)activityViewController itemForActivityType:(nullable UIActivityType)activityType {
  if  ([activityType isEqualToString:UIActivityTypeAirDrop]) {
    return nil;
  } else {
    return @"More info about the Structure SDK: http://structure.io/developers";
  }
}

- (nonnull id)activityViewControllerPlaceholderItem:(nonnull UIActivityViewController *)activityViewController {
  return @"";
}

@end
