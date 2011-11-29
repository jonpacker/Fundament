//
//  FAppDelegate.h
//  Fundament
//
//  Created by Jon Packer on 29/11/11.
//  Copyright (c) 2011 Creative Intersection. All rights reserved.
//

#import <UIKit/UIKit.h>

@class FViewController;

@interface FAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (strong, nonatomic) FViewController *viewController;

@end
