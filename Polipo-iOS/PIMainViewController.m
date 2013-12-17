//
//  PIMainViewController.m
//  Polipo-iOS
//
//  Created by Yifan Lu on 8/4/13.
//  Copyright (c) 2013 Yifan Lu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "PIMainViewController.h"
#import "PIPolipo.h"

@interface PIMainViewController ()

@property (nonatomic) bool isWorking;
@property (nonatomic, strong) PIPolipo *polipo;
#ifdef NO_AUDIO_BACKGROUNDING
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTask;
#else
@property (nonatomic, strong) AVPlayer *bgPlayer;
#endif

@end

@implementation PIMainViewController

@synthesize activityIndicator, startProxySwitch, statusLabel, logTextView;
@synthesize isWorking = _isWorking, polipo = _polipo;
#ifdef NO_AUDIO_BACKGROUNDING
@synthesize backgroundTask;
#else
@synthesize bgPlayer;
#endif

#pragma mark View Delegate methods

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setPolipo:[[PIPolipo alloc] initWithDelegate:self]];
    
#ifndef NO_AUDIO_BACKGROUNDING
    // Set AVAudioSession
    NSError *sessionError = nil;
    [[AVAudioSession sharedInstance] setDelegate:self];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&sessionError];
    
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[[NSBundle mainBundle] URLForResource:@"silence" withExtension:@"mp3"]];
    
    [self setBgPlayer:[[AVPlayer alloc] initWithPlayerItem:item]];
    [[self bgPlayer] setActionAtItemEnd:AVPlayerActionAtItemEndNone];
#endif
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark Main view methods

- (bool)isWorking
{
    return _isWorking;
}

- (void)setIsWorking:(bool)isWorking
{
    _isWorking = isWorking;
    if (isWorking)
    {
        [[self activityIndicator] startAnimating];
        [[self startProxySwitch] setEnabled:false];
    }
    else
    {
        [[self activityIndicator] stopAnimating];
        [[self startProxySwitch] setEnabled:true];
    }
}

#pragma mark Actions

- (IBAction)toggleProxy:(id)sender
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
    ^ {
        if ([sender isOn])
        {
            [[self polipo] start];
        }
        else
        {
            [[self polipo] stop];
        }
    });
}

- (IBAction)installProfile:(id)sender
{
    // prepare profile
    NSArray *paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *documentsDirectory = [paths objectAtIndex:0];
    NSURL *wwwDirectory = [documentsDirectory URLByAppendingPathComponent:@"www" isDirectory:YES];
    NSString *configfile = [[NSBundle mainBundle] pathForResource: @"polipo" ofType: @"mobileconfig"];
    NSMutableDictionary* prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:configfile];
    id payloadContent = [prefs valueForKey:@"PayloadContent"];
    id payload = [payloadContent firstObject];
    payloadContent = [payload valueForKey:@"PayloadContent"];
    payload = [payloadContent firstObject];
    id defaults = [payload valueForKey:@"DefaultsData"];
    id apns = [defaults valueForKey:@"apns"];
    id apn = [apns firstObject];
    
    // create profile
    NSString *apnstr = [[NSUserDefaults standardUserDefaults] stringForKey:@"apn"];
    if (!apnstr)
    {
        apnstr = [NSString string];
    }
    [apn setObject:apnstr forKey:@"apn"];
    [apn setObject:[[self polipo] listenAddress] forKey:@"proxy"];
    [apn setObject:[NSString stringWithFormat:@"%04d", [[self polipo] listenPort]] forKey:@"proxyPort"];
    [prefs writeToURL:[wwwDirectory URLByAppendingPathComponent:@"polipo.mobileconfig"] atomically:NO];
    
    // open link to profile
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%d/%@", [[self polipo] listenAddress], (int) [[self polipo] listenPort], @"polipo.mobileconfig"]]];
}

#pragma mark Polipo Delegate methods

- (void)polipoWillStart:(PIPolipo *)polipo
{
    [self setIsWorking:true];
    [[self statusLabel] setText:@"Starting..."];
}

- (void)polipoWillStop:(PIPolipo *)polipo
{
    [self setIsWorking:true];
    [[self statusLabel] setText:@"Stopping..."];
}

- (void)polipoDidStart:(PIPolipo *)polipo
{
    [self setIsWorking:false];
    [[self startProxySwitch] setOn:[polipo isRunning]];
    [[self installProfileButton] setEnabled:true];
    [[self statusLabel] setText:[NSString stringWithFormat:@"Listening on %@:%d", [[self polipo] listenAddress], (int)[[self polipo] listenPort]]];
    
    // start backgrounding
#ifndef NO_AUDIO_BACKGROUNDING
    [[self bgPlayer] play];
#else
    [self setBackgroundTask:[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        NSLog(@"Background handler about to expire.");
        [[UIApplication sharedApplication] endBackgroundTask:[self backgroundTask]];
        [self setBackgroundTask:UIBackgroundTaskInvalid];
    }]];
#endif
}

- (void)polipoDidStop:(PIPolipo *)polipo
{
    [self setIsWorking:false];
    [[self startProxySwitch] setOn:[polipo isRunning]];
    [[self installProfileButton] setEnabled:false];
    [[self statusLabel] setText:@"Stopped"];
#ifdef NO_AUDIO_BACKGROUNDING
    if ([self backgroundTask] != UIBackgroundTaskInvalid)
    {
        [[UIApplication sharedApplication] endBackgroundTask:[self backgroundTask]];
        [self setBackgroundTask:UIBackgroundTaskInvalid];
    }
#endif
}

- (void)polipoDidFailWithError:(NSString *)error polipo:(PIPolipo *)polipo
{
    [self setIsWorking:false];
    [[self startProxySwitch] setOn:[polipo isRunning]];
    [[self installProfileButton] setEnabled:false];
    UIAlertView *message = [[UIAlertView alloc] initWithTitle:@"Error" message:error delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [message show];
    [[self statusLabel] setText:@"Error"];
#ifdef NO_AUDIO_BACKGROUNDING
    if ([self backgroundTask] != UIBackgroundTaskInvalid)
    {
        [[UIApplication sharedApplication] endBackgroundTask:[self backgroundTask]];
        [self setBackgroundTask:UIBackgroundTaskInvalid];
    }
#endif
}

- (void)polipoLogMessage:(NSString *)message
{
    [[self logTextView] setText:[NSString stringWithFormat:@"%@%@", [[self logTextView] text], message]];
    NSRange range = NSMakeRange([[[self logTextView] text] length] - 1, 1);
    [[self logTextView] scrollRangeToVisible:range];
#if DEBUG
    NSLog(@"%@", message);
#endif
}

@end
