// Exercise Sparkle's real network and signature path without windows or installation.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
@interface FeedProbe : NSObject <SPUUserDriver, SPUUpdaterDelegate>
@property(nonatomic, copy) NSString *feed;
@property(nonatomic, strong) SPUUpdater *updater;
@end
@implementation FeedProbe
- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater { return self.feed; }
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply { exit(3); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {
    printf("PASS: Sparkle fetched and validated signed feed; latest %s\n", item.displayVersionString.UTF8String);
    exit(0); // Never download or install.
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack { fprintf(stderr, "Unexpected no-update result: %s\n", error.description.UTF8String); exit(2); }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack { fprintf(stderr, "FAIL: %s\n", error.description.UTF8String); exit(1); }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancel { cancel(); exit(3); }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate { exit(3); }
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { exit(3); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry { exit(3); }
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack { exit(3); }
- (void)dismissUpdateInstallation {}
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 64;
        [NSApplication sharedApplication];
        FeedProbe *probe = [FeedProbe new];
        probe.feed = [NSString stringWithUTF8String:argv[1]];
        probe.updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:probe delegate:probe];
        NSError *error = nil;
        if (![probe.updater startUpdater:&error]) { NSLog(@"%@", error); return 1; }
        [probe.updater checkForUpdates];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ fprintf(stderr, "Feed check timed out\n"); exit(4); });
        [NSApp run];
    }
    return 4;
}
