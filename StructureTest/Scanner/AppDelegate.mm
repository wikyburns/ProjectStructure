/*
  This file is part of the Structure SDK.
  Copyright © 2019 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "AppDelegate.h"
#import "ViewController.h"

//------------------------------------------------------------------------------

@implementation AppDelegate

- (void)registerDefaultsFromSettingsBundle
{
    // this function writes default settings as settings
    NSString* settingsBundle = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    if (!settingsBundle)
    {
        NSLog(@"Could not find Settings.bundle");
        return;
    }

    NSDictionary* settings =
        [NSDictionary dictionaryWithContentsOfFile:[settingsBundle stringByAppendingPathComponent:@"Root.plist"]];
    NSArray* preferences = [settings objectForKey:@"PreferenceSpecifiers"];

    NSMutableDictionary* defaultsToRegister = [[NSMutableDictionary alloc] initWithCapacity:[preferences count]];
    for (NSDictionary* prefSpecification in preferences)
    {
        NSString* key = [prefSpecification objectForKey:@"Key"];
        if (key)
        {
            [defaultsToRegister setObject:[prefSpecification objectForKey:@"DefaultValue"] forKey:key];
            NSLog(@"writing as default %@ to the key %@", [prefSpecification objectForKey:@"DefaultValue"], key);
        }
    }

    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultsToRegister];
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    if (false)
    {
        // STWirelessLog is very helpful for debugging while your Structure Sensor is plugged in.
        // See SDK documentation for how to start a listener on your computer.

        NSError* error = nil;
        NSString* remoteLogHost = @"192.168.1.1";
        [STWirelessLog broadcastLogsToWirelessConsoleAtAddress:remoteLogHost usingPort:4999 error:&error];
        if (error)
            NSLog(@"Oh no! Can't start wireless log: %@", [error localizedDescription]);
    }

    [self registerDefaultsFromSettingsBundle];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    self.viewController = [ViewController viewController];
    self.window.rootViewController = self.viewController;
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication*)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of
    // temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application
    // and it begins the transition to the background state. Use this method to pause ongoing tasks, disable timers, and
    // throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication*)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application
    // state information to restore your application to its current state in case it is terminated later. If your
    // application supports background execution, this method is called instead of applicationWillTerminate: when the
    // user quits.
}

- (void)applicationWillEnterForeground:(UIApplication*)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes
    // made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication*)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application
    // was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication*)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also
    // applicationDidEnterBackground:.
}

@end
