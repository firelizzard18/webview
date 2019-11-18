/*
 * MIT License
 *
 * Copyright (c) 2019 The WebView Authors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// +build darwin
// +build webkit

#ifndef __WEBVIEW_OS_H
#define __WEBVIEW_OS_H

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <CoreGraphics/CoreGraphics.h>

// https://github.com/WebKit/webkit/blob/master/Source/WebKit/UIProcess/API/Cocoa/_WKDownload.h
@class _WKDownload;

// https://github.com/WebKit/webkit/blob/master/Source/WebKit/UIProcess/API/Cocoa/_WKDownloadDelegate.h
// https://github.com/WebKit/webkit/blob/master/Tools/TestWebKitAPI/Tests/WebKitCocoa/Download.mm
@protocol WKDownloadDelegate
@optional
- (void)_downloadDidStart:(_WKDownload *)download;
- (void)_download:(_WKDownload *)download didReceiveServerRedirectToURL:(NSURL *)url;
- (void)_download:(_WKDownload *)download didReceiveResponse:(NSURLResponse *)response;
- (void)_download:(_WKDownload *)download didReceiveData:(uint64_t)length;
- (void)_download:(_WKDownload *)download decideDestinationWithSuggestedFilename:(NSString *)filename completionHandler:(void (^)(BOOL allowOverwrite, NSString *destination))completionHandler;
- (void)_downloadDidFinish:(_WKDownload *)download;
- (void)_download:(_WKDownload *)download didFailWithError:(NSError *)error;
- (void)_downloadDidCancel:(_WKDownload *)download;
- (void)_download:(_WKDownload *)download didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential*))completionHandler;
- (void)_download:(_WKDownload *)download didCreateDestination:(NSString *)destination;
- (void)_downloadProcessDidCrash:(_WKDownload *)download;
- (BOOL)_download:(_WKDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)MIMEType;
@end

@interface WKProcessPool (Download)
- (void) _setDownloadDelegate:(id<WKDownloadDelegate>)del;
@end

@interface WKPreferences (DevExtras)
- (void) _setDeveloperExtrasEnabled:(BOOL)enabled;
@end

enum webview_dialog_type;

@interface WebViewDelegate : NSObject <NSWindowDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate>
{
    NSAutoreleasePool *_pool;
    NSWindow *_window;
    WKWebView *_webview;
    BOOL _shouldExit;
    void *_context;
}

- (id) initWithContext:(void *)context url:(NSURL *)url title:(NSString *)title width:(int)width height:(int)height resizable:(BOOL)resizable debug:(BOOL)debug;

- (int) loop:(BOOL)blocking;
- (int) eval:(NSString *)js;
- (void) setTitle:(NSString *)title;
- (void) setFullscreen:(BOOL)fullscreen;
- (void) setColor:(NSColor *)color;
- (NSString *) dialog:(enum webview_dialog_type)type flags:(int)flags title:(NSString *)title arg:(NSString *)arg;
- (void) stop;
@end

#endif