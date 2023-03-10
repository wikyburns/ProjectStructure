/*
  This file is part of the Structure SDK.
  Copyright © 2019 Occipital, Inc. All rights reserved.
  http://structure.io
*/
#import <UIKit/UIKit.h>


// Predefined colors used in the app.
extern UIColor* const redButtonColorWithAlpha;
extern UIColor* const blueButtonColorWithAlpha;
extern UIColor* const blueGrayButtonColorWithAlpha;
extern UIColor* const redButtonColorWithLightAlpha;
extern UIColor* const blackLabelColorWithLightAlpha;

@interface UIButton (customStyle)

- (void)applyCustomStyleWithBackgroundColor:(UIColor*)color;

@end


@interface UILabel (customStyle)

- (void)applyCustomStyleWithBackgroundColor:(UIColor*)color;

@end
