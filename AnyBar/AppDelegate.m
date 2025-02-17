//
//  AppDelegate.m
//  AnyBar
//
//  Created by Nikita Prokopov on 14/02/15.
//  Copyright (c) 2015 Nikita Prokopov. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate()

@property (weak, nonatomic) IBOutlet NSWindow *window;
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) GCDAsyncUdpSocket *udpSocket;
@property (strong, nonatomic) NSString *imageName;
@property (assign, nonatomic) int udpPort;
@property (assign, nonatomic) NSString *appTitle;

@end

@implementation AppDelegate

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _udpPort = -1;
    _imageName = [self readStringFromEnvironmentVariable:@"ANYBAR_INIT" usingDefault:@"hollow"];
    self.statusItem = [self initializeStatusBarItem];
    [self setImage:_imageName];

    @try {
        _udpPort = [self getUdpPort];
        _udpSocket = [self initializeUdpSocket: _udpPort];
        _appTitle = [self readStringFromEnvironmentVariable:@"ANYBAR_TITLE" usingDefault:nil];
        _statusItem.toolTip = _appTitle == nil ? [NSString stringWithFormat:@"AnyBar @ %d", _udpPort] : _appTitle;
    }
    @catch(NSException *ex) {
      [[NSApplication sharedApplication] terminate:nil];
    }
    @finally {
        NSString *portTitle = [NSString stringWithFormat:@"UDP port: %@", _udpPort >= 0 ? [NSNumber numberWithInt:_udpPort] : @"unavailable"];
        NSMenu *menu = [[NSMenu alloc] init];
        
        if (_appTitle != nil)
            [menu addItemWithTitle:_appTitle action:nil keyEquivalent:@""];
        [menu addItemWithTitle:portTitle action:nil keyEquivalent:@""];
        [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@""];

        _statusItem.menu = menu;
    }
}

-(void)applicationWillTerminate:(NSNotification *)aNotification {
    [self shutdownUdpSocket: _udpSocket];
    _udpSocket = nil;

    [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
    _statusItem = nil;
}

-(int) getUdpPort {
    int port = [self readIntFromEnvironmentVariable:@"ANYBAR_PORT" usingDefault:@"1738"];

    if (port < 0 || port > 65535) {
        @throw([NSException exceptionWithName:@"Argument Exception"
                            reason:[NSString stringWithFormat:@"UDP Port range is invalid: %d", port]
                            userInfo:@{@"argument": [NSNumber numberWithInt:port]}]);

    }

    return port;
}

-(GCDAsyncUdpSocket*)initializeUdpSocket:(int)port {
    NSError *error = nil;
    GCDAsyncUdpSocket *udpSocket = [[GCDAsyncUdpSocket alloc]
                                    initWithDelegate:self
                                    delegateQueue:dispatch_get_main_queue()];

    [udpSocket bindToPort:port error:&error];
    if (error) {
        @throw([NSException exceptionWithName:@"UDP Exception"
                            reason:[NSString stringWithFormat:@"Binding to %d failed", port]
                            userInfo:@{@"error": error}]);
    }

    [udpSocket beginReceiving:&error];
    if (error) {
        @throw([NSException exceptionWithName:@"UDP Exception"
                            reason:[NSString stringWithFormat:@"Receiving from %d failed", port]
                            userInfo:@{@"error": error}]);
    }

    return udpSocket;
}

-(void)shutdownUdpSocket:(GCDAsyncUdpSocket*)sock {
    if (sock != nil) {
        [sock close];
    }
}

-(void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address withFilterContext:(id)filterContext {
    [self processUdpSocketMsg:sock withData:data fromAddress:address];
}

-(NSImage*)tryImage:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:path])
        return [[NSImage alloc] initWithContentsOfFile:path];
    else
        return nil;
}

-(NSString*)bundledImagePath:(NSString *)name {
    return [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
}

-(NSString*)homedirImagePath:(NSString *)name {
    return [NSString stringWithFormat:@"%@/%@/%@.png", NSHomeDirectory(), @".AnyBar", name];
}

-(void)setImage:(NSString*) name {
    NSImage *image = nil;
    image = [self tryImage:[self homedirImagePath:[name stringByAppendingString:@"@2x"]]];
    if (!image)
        image = [self tryImage:[self homedirImagePath:name]];
    if (!image)
        image = [self tryImage:[self bundledImagePath:[name stringByAppendingString:@"@2x"]]];
    if (!image)
        image = [self tryImage:[self bundledImagePath:name]];
    if (!image) {
        NSLog(@"Cannot find image '%@'", name);
        image = [self tryImage:[self bundledImagePath:@"question@2x"]];
        _statusItem.image = image;
        [_statusItem.image setTemplate:NO];
    } else {
        _statusItem.image = image;
        if ([name isEqualToString:@"filled"] || [name isEqualToString:@"hollow"])
            [_statusItem.image setTemplate:YES];
        else
            [_statusItem.image setTemplate:NO];
        _imageName = name;
    }
}

-(void)processUdpSocketMsg:(GCDAsyncUdpSocket *)sock withData:(NSData *)data
    fromAddress:(NSData *)address {
    NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    if ([msg isEqualToString:@"quit"])
        [[NSApplication sharedApplication] terminate:nil];
    else
        [self setImage:msg];
}

-(NSStatusItem*) initializeStatusBarItem {
    NSStatusItem *statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
//    statusItem.image = [NSImage imageNamed:@"white@2x.png"];
    statusItem.highlightMode = YES;
    return statusItem;
}

-(int) readIntFromEnvironmentVariable:(NSString*) envVariable usingDefault:(NSString*) defStr {
    int intVal = -1;

    NSString *envStr = [[[NSProcessInfo processInfo]
                         environment] objectForKey:envVariable];
    if (!envStr) {
        envStr = defStr;
    }

    NSNumberFormatter *nFormatter = [[NSNumberFormatter alloc] init];
    nFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSNumber *number = [nFormatter numberFromString:envStr];

    if (!number) {
        @throw([NSException exceptionWithName:@"Argument Exception"
                            reason:[NSString stringWithFormat:@"Parsing integer from %@ failed", envStr]
                            userInfo:@{@"argument": envStr}]);

    }

    intVal = [number intValue];

    return intVal;
}

-(NSString*) readStringFromEnvironmentVariable:(NSString*) envVariable usingDefault:(NSString*) defStr {
    NSString *envStr = [[[NSProcessInfo processInfo]
                         environment] objectForKey:envVariable];
    
    if (!envStr) {
        envStr = defStr;
    }
    
    return envStr;
}

-(id) osaImageBridge {
    NSLog(@"OSA Event: %@ - %@", NSStringFromSelector(_cmd), _imageName);

    return _imageName;
}


-(void) setOsaImageBridge:(id)imgName {
    NSLog(@"OSA Event: %@ - %@", NSStringFromSelector(_cmd), imgName);

    _imageName = (NSString *)imgName;

    [self setImage:_imageName];
}

@end

