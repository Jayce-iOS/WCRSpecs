//
//  WCRWebCourseWare.m
//  WCRLiveCore
//
//  Created by 欧阳铨 on 2018/10/22.
//  Copyright © 2018 com.100tal. All rights reserved.
//

#import "WCRWebCourseWare.h"
#import <WCRBase/WCRYYModel.h>
#import <WCRBase/ReactiveObjC.h>
#import <WCRBase/NSString+Utils.h>
#import <WCRBase/NSDictionary+Utils.h>
#import "WCRCourseWareLog.h"
#import "WCRWKWebviewMessageHandler.h"
#import "WCRError+WebCourseWare.h"
//#import "WCRUtils.h"

static NSString * const kWCRDocJSSDKScriptMessageHandler = @"WCRDocJSSDK";
NSString * const kWCRWebCourseWareJSFuncSetUp = @"setup";
NSString * const kWCRWebCourseWareJSFuncSendMessage = @"sendMessage";
NSString * const kWCRWebCourseWareJSFuncSendMessageWithCallBack = @"sendMessageWithCallback";
NSString * const kWCRWebCourseWareJSErrorMessage = @"BUFFERING_LOAD_ERROR";
NSString * const kWCRWebCourseWareJSScrollMessage = @"PDF_SCROLLTOP_RESULT";
NSString * const kWCRWebCourseWareJSHeightChangeMessage = @"PDF_PAGECONTENT_HEIGHT";

@interface WCRWebCourseWare ()<WKScriptMessageHandler,WKUIDelegate,WKNavigationDelegate,UIScrollViewDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSMutableSet *messagesSet;
@property (nonatomic, copy) NSString *callBackJsString;
@property (nonatomic, assign, getter=isWebViewLoadSuccess) BOOL webViewLoadSuccess;
@property (nonatomic, assign, getter=isShouldGoToPageAfterLoad) BOOL shouldGoToPageAfterLoad;
@property (nonatomic, assign, getter=isShouldRateAfterLoad) BOOL shouldRateAfterLoad;
@property (nonatomic, assign, getter=isShouldMouseClickAfterLoad) BOOL shouldMouseClickAfterLoad;
@property (nonatomic, assign) NSInteger currentPage;
@property (nonatomic, assign) NSInteger currentStep;
@property (nonatomic, assign) CGFloat currentRate;
@property (nonatomic, assign) CGRect mouseClickRect;
@property (nonatomic, assign) CGFloat documentHeight;
@end

@implementation WCRWebCourseWare
-(instancetype)init{
    self = [super init];
    if (self) {
        _currentPage = 1;
        _currentStep = -1;
    }
    return self;
}

-(void)dealloc{
    WCRCWLogInfo(@"WCRWebCourseWare dealloc");
    [_webView.configuration.userContentController removeScriptMessageHandlerForName:kWCRDocJSSDKScriptMessageHandler];
    //iOS8中销毁webView时奔溃
    _webView.scrollView.delegate = nil;
}

- (WCRError * _Nullable)loadURL:(NSURL *)url{
    WCRCWLogError(@"加载网页:%@",url);
    self.view = self.webView;
    
    if (url == nil) {
        WCRCWLogError(@"加载网页 url为nil");
        return [WCRError webCourseWareErrorWithErrorCode:WCRWCWErrorCodeNilUrl];
    }
    
    if ([NSString wcr_isBlankString:url.absoluteString]) {
        WCRCWLogError(@"加载网页 url absoluteString 为空");
        return [WCRError webCourseWareErrorWithErrorCode:WCRWCWErrorCodeNilUrl];
    }
    
    self.webViewLoadSuccess = NO;
    NSURLRequest* urlRequest = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:urlRequest];
    
    return nil;
}
- (void)goToPage:(NSInteger)page step:(NSInteger)step{
    WCRCWLogInfo(@"跳转到某一页page:%lu step:%lu",(unsigned long)page,(unsigned long)step);
    if (page <= 0 || step == -1){
        WCRCWLogError(@"page小于0或者step等于-1");
        return;
    }
    if (page == self.currentPage && step == self.currentStep) {
        WCRCWLogInfo(@"已经是当前页的某一步");
        return;
    }
    self.currentPage = page;
    self.currentStep = step;
    if (self.isWebViewLoadSuccess) {
        [self toPage:page step:step];
        self.shouldGoToPageAfterLoad = NO;
    }else{
        self.shouldGoToPageAfterLoad = YES;
    }
   
}

- (void)toPage:(NSInteger)page step:(NSInteger)step{
    NSString* toPageScript = [NSString stringWithFormat:
                              @"if (window.slideAPI) {"
                              "    window.slideAPI.gotoSlideStep(%d, %d);"
                              "} else {"
                              "    window.enableGotoSlide = true; "
                              "    window.gotoSlide(%d, %d);"
                              "}"
                              , (int)(page-1), (int)(step), (int)(page-1), (int)(step)];
    [self evaluateJavaScript:toPageScript completionHandler:nil];
}

- (void)page:(NSInteger)page scrollToRate:(CGFloat)rate{
    WCRCWLogInfo(@"某页滚动page:%lu scrollToRate:%f",(unsigned long)page,rate);
    if (page != self.currentPage) {
        WCRCWLogError(@"page不等于当前页");
        return;
    }
    if (rate <0.0f || rate > 1.0f) {
        WCRCWLogError(@"rate <0.0或者rate > 1.0");
        return;
    }
    self.currentRate = rate;
    if (self.isWebViewLoadSuccess) {
        NSString* rateScript = [NSString stringWithFormat:@"window.slideAPI.scrollTo(%d);", (int)(self.currentRate * self.documentHeight)];
        [self evaluateJavaScript:rateScript completionHandler:nil];
        self.shouldRateAfterLoad = NO;
    }else{
        self.shouldRateAfterLoad = YES;
    }
}
- (void)mouseClick:(CGRect)click{
    WCRCWLogInfo(@"模拟鼠标点击 x:%f y:%f w:%f h:%f",click.origin.x,click.origin.y,click.size.width,click.size.height);
    self.mouseClickRect = click;
    if (self.isWebViewLoadSuccess) {
        CGFloat webViewWidth = self.webView.bounds.size.width;
        CGFloat webViewHeight = self.webView.bounds.size.height;
        
        CGFloat x = click.origin.x;
        CGFloat y = click.origin.y;
        CGFloat w = click.size.width;
        CGFloat h = click.size.height;
        
        CGFloat newX = webViewWidth * x / w;
        CGFloat newY = webViewHeight * y / h;
        NSString *mouseClickScript = [NSString stringWithFormat:@"mouse_click(%d,%d)",(int)newX,(int)newY];
        [self evaluateJavaScript:mouseClickScript completionHandler:nil];
        self.shouldMouseClickAfterLoad = NO;
    }else{
        self.shouldMouseClickAfterLoad = YES;
    }
}
- (void)registerMessageWithMessageName:(NSString *)messageName{
    [self.messagesSet addObject:messageName];
}
- (void)unregisterMessageWithMessageName:(NSString *)messageName{
    [self.messagesSet removeObject:messageName];
}
- (void)unregisterAllMessages{
    [self.messagesSet removeAllObjects];
}
- (NSArray *)allRegisterMessages{
    return [self.messagesSet allObjects];
}
- (void)sendMessage:(NSString *)messageName withBody:(NSDictionary *)messageBody completionHandler:(void (^ _Nullable)(_Nullable id, NSError * _Nullable error))completionHandler{
    if (![NSString wcr_isBlankString:self.callBackJsString]) {
        NSString* content = [NSString stringWithFormat:@"{\"msg\":\"%@\", \"body\":%@}", messageName, [NSString wcr_jsonWithDictionary:messageBody]];
        
        NSString* js = [NSString stringWithFormat:@"try{%@(%@);}catch(e){window.WCRDocSDK.log(e);}", self.callBackJsString, content];
        [self evaluateJavaScript:js completionHandler:completionHandler];
    }else{
        WCRCWLogError(@"callBackJsString为空 messageName:%@ messageBody:%@",messageName,messageBody);
    }
    
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message{
    if ([message.name isEqualToString:@"WCRDocJSSDK"]) {
        NSString* msgBodyString = (NSString*)message.body;
        NSDictionary* msgBody = [NSDictionary wcr_dictionaryWithJSON:msgBodyString];
        NSString* msgName = [msgBody objectForKey:@"message"];
        WCRCWLogInfo(@"收到WCRDocJSSDK消息:%@ msgBody:%@",msgName,msgBody);
        if ([msgName isEqualToString:kWCRWebCourseWareJSFuncSetUp]) {
            [self onJsFuncSetUp:msgBody];
        } else if ([msgName isEqualToString:kWCRWebCourseWareJSFuncSendMessage]) {
            [self onJsFuncSendMessage:msgBody];
        } else if ([msgName isEqualToString:kWCRWebCourseWareJSFuncSendMessageWithCallBack]) {
            [self onJsFuncSendMessageWithCallBack:msgBody];
        }else if ([msgName isEqualToString:kWCRWebCourseWareJSErrorMessage]) {
            [self onJsFuncError:msgBody];
        } else if ([msgName isEqualToString:kWCRWebCourseWareJSScrollMessage]) {
            [self onJsFuncScroll:msgBody];
        } else if ([msgName isEqualToString:kWCRWebCourseWareJSHeightChangeMessage]) {
            [self onJsFuncHeightChange:msgBody];
        }
        [self callBackJsFunc:msgName body:msgBody];
    }else{
        WCRCWLogInfo(@"收到非WCRDocJSSDK消息:%@",message.name);
    }
}

- (void)callBackJsFunc:(NSString *)name body:(NSDictionary *)body{
    if ([self.messagesSet containsObject:name]) {
        if ([self.webCourseDelegate respondsToSelector:@selector(webCourseWare:receiveMessage:withBody:)]) {
            [self.webCourseDelegate webCourseWare:self receiveMessage:name withBody:body];
        }
    }
}

- (void)onJsFuncSetUp:(NSDictionary *)message{
    WCRCWLogInfo(@"onJsFuncSetUp%@ - message:%@", self.url,message);
    
    NSDictionary *config = [message objectForKey:@"body"];
    if (config == nil) {
        WCRCWLogError(@"setUp方法config为空");
        return;
    }
    self.callBackJsString = [config objectForKey:@"msg_callback"];
    
    NSString *callBack = [message objectForKey:@"callback"];
    
    if (callBack == nil) {
        WCRCWLogError(@"setUp方法callBack为空");
        return;
    }
    
    
    if ([self.webCourseDelegate respondsToSelector:@selector(webCourseWareSetUpDocumentMessageDictionary:)]) {
        NSDictionary *callbackContent = [self.webCourseDelegate webCourseWareSetUpDocumentMessageDictionary:self];
        NSString* callbackMsg = [NSString stringWithFormat:@"try{%@(%@);}catch(e){window.WCRDocSDK.log(e);}"
                                 , callBack
                                 , [NSString wcr_jsonWithDictionary:callbackContent]];
        [self evaluateJavaScript:callbackMsg completionHandler:nil];
    }
}

- (void)onJsFuncSendMessage:(NSDictionary *)message{
    WCRCWLogInfo(@"onJsFuncSendMessage:%@ - message:%@",self.url,message);
    
    NSDictionary *body = [message objectForKey:@"body"];
    if (body == nil) {
        WCRCWLogError(@"body 为空");
        return;
    }
    
    NSString* msgName = [body objectForKey:@"msg"];
    NSDictionary* msgBody = [body objectForKey:@"body"];
    
    if ([NSString wcr_isBlankString:msgName] || msgBody == nil) {
        WCRCWLogError(@"megName:%@ 或者 msgBody:%@为空",msgName,msgBody);
        return;
    }
    
    if ([self.webCourseDelegate respondsToSelector:@selector(webCourseWare:sendDocMessage:withBody:completion:)]) {
        [self.webCourseDelegate webCourseWare:self sendDocMessage:msgName withBody:msgBody completion:nil];
    }
    
}

- (void)onJsFuncSendMessageWithCallBack:(NSDictionary *)message{
    WCRCWLogInfo(@"onJsFuncSendMessageWithCallBack:%@ - message:%@",self.url,message);
    
    NSDictionary *body = [message objectForKey:@"body"];
    if (body == nil) {
        WCRCWLogError(@"body 为空");
        return;
    }
    
    NSString* msgName = [body objectForKey:@"msg"];
    NSDictionary* msgBody = [body objectForKey:@"body"];
    
    if ([NSString wcr_isBlankString:msgName] || msgBody == nil) {
        WCRCWLogError(@"megName:%@ 或者 msgBody:%@为空",msgName,msgBody);
        return;
    }
    
    NSString* callback = [message objectForKey:@"callback"];
    
    if ([self.webCourseDelegate respondsToSelector:@selector(webCourseWare:sendDocMessage:withBody:completion:)]) {
        if ([NSString wcr_isBlankString:callback]) {
            [self.webCourseDelegate webCourseWare:self sendDocMessage:msgName withBody:msgBody completion:nil];
        }else{
            [self.webCourseDelegate webCourseWare:self sendDocMessage:msgName withBody:msgBody completion:^(NSDictionary * _Nonnull dict) {
                NSString *jsonData = @"";
                if ([dict objectForKey:@"content"]) {
                    jsonData = [NSString wcr_jsonWithDictionary:[dict objectForKey:@"content"]];
                }
                NSString* js = [NSString stringWithFormat:@"try{%@(%@);}catch(e){window.WCRDocSDK.log(e);}"
                                , callback
                                , jsonData];
                [self evaluateJavaScript:js completionHandler:nil];
            }];
        }
    }
}

- (void)onJsFuncError:(NSDictionary *)message{
    WCRCWLogError(@"onJsFuncError：%@",message);
}

- (void)onJsFuncScroll:(NSDictionary *)message{
    WCRCWLogInfo(@"onJsFuncScroll:%@ - message:%@", self.url,message);
    NSNumber *body = [message objectForKey:@"body"];
    CGFloat offsetY = [body floatValue];
    self.currentRate = offsetY/self.documentHeight;
    if (body != nil && [self.webCourseDelegate respondsToSelector:@selector(webCourseWare:webViewDidScroll:)]) {
        [self.webCourseDelegate webCourseWare:self webViewDidScroll:self.currentRate];
    }
}

- (void)onJsFuncHeightChange:(NSDictionary *)message{
    WCRCWLogInfo(@"onJsFuncHeightChange:%@ - message:%@", self.url,message);
    NSNumber *body = [message objectForKey:@"body"];
    self.documentHeight = [body floatValue];
    if (body != nil && [self.webCourseDelegate respondsToSelector:@selector(webCourseWare:webViewHeightDidChange:)]) {
        [self.webCourseDelegate webCourseWare:self webViewHeightDidChange:self.documentHeight];
    }
    if (self.isWebViewLoadSuccess) {
        NSString* rateScript = [NSString stringWithFormat:@"window.slideAPI.scrollTo(%d);", (int)(self.currentRate * self.documentHeight)];
        [self evaluateJavaScript:rateScript completionHandler:nil];
        self.shouldRateAfterLoad = NO;
    }else{
        self.shouldRateAfterLoad = YES;
    }
}

- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^ _Nullable)(_Nullable id, NSError * _Nullable error))completionHandler{
    WCRCWLogInfo(@"javaScriptString :%@",javaScriptString);
    if ([NSString wcr_isBlankString:javaScriptString]) {
        WCRCWLogError(@"javaScriptString 为空");
        return;
    }
    [self.webView evaluateJavaScript:javaScriptString completionHandler:completionHandler];
}

- (UIView*)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    //取消scrollview手势缩放
    return nil;
}

-(void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation{
    WCRCWLogInfo(@"wkwebview开始加载:%@",self.url);
    if ([self.delegate respondsToSelector:@selector(courseWareWillLoad:)]) {
        [self.delegate courseWareWillLoad:self];
    }
}

-(void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation{
    WCRCWLogInfo(@"wkwebview加载完成:%@",self.url);
    self.webViewLoadSuccess = YES;
    [self disableDoubleTapScroll];
    if (self.isShouldGoToPageAfterLoad) {
        [self toPage:self.currentPage step:self.currentStep];
    }
    if (self.isShouldRateAfterLoad) {
        [self page:self.currentPage scrollToRate:self.currentRate];
    }
    if (self.isShouldMouseClickAfterLoad) {
        [self mouseClick:self.mouseClickRect];
    }
    
    if ([self.delegate respondsToSelector:@selector(courseWareDidLoad:error:)]) {
        [self.delegate courseWareDidLoad:self error:nil];
    }
    
}

-(void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error{
    WCRCWLogInfo(@"wkwebview加载失败:%@",self.url);
    WCRError *wcrError = [WCRError webCourseWareErrorWithNSError:error];
    if ([self.delegate respondsToSelector:@selector(courseWareDidLoad:error:)]) {
        [self.delegate courseWareDidLoad:self error:wcrError];
    }
    //重试逻辑
    [self retryAfterRetryInterval:self.retryInterval];
}

- (void)retryAfterRetryInterval:(NSUInteger)interval{
    @weakify(self);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @strongify(self);
        NSURL *url = [self getBackUpUrl];
        WCRCWLogInfo(@"retryAfterRetryInterval:%lu url:%@",(unsigned long)interval,url);
        if (url != nil && ![NSString wcr_isBlankString:url.absoluteString]) {
            NSURLRequest* urlRequest = [NSURLRequest requestWithURL:url];
            [self.webView loadRequest:urlRequest];
        }
    });
    
}

-(void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation{
    WCRCWLogInfo(@"wkwebview内容开始返回:%@",self.url);
    //设置内容的宽高
    NSString *sizeJavascript = @"var meta = document.createElement('meta');meta.setAttribute('name', 'viewport');meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no,shrink-to-fit=YES');document.getElementsByTagName('head')[0].appendChild(meta);";
    if ([[UIDevice currentDevice].systemVersion floatValue] < 9.0) {
        sizeJavascript = [NSString stringWithFormat:@"var meta = document.createElement('meta');meta.setAttribute('name', 'viewport');meta.setAttribute('content', 'width=%f, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');document.getElementsByTagName('head')[0].appendChild(meta);", self.view.bounds.size.width];
    }
    [webView evaluateJavaScript:sizeJavascript completionHandler:nil];
    //设置课件t透明
    NSString *opaqueJavascript = @"document.body.style.backgroundColor='transparent';document.getElementsByTagName('html')[0].style.backgroundColor='transparent'";
    [webView evaluateJavaScript:opaqueJavascript completionHandler:nil];
    //注入停用长按图片显示保存菜单,在课件中停用iOS11后的drag&drop功能
    NSString *dragJavascript = @"document.body.style.webkitTouchCallout='none';document.body.setAttribute('ondragstart','return false');";
    [webView evaluateJavaScript:dragJavascript completionHandler:nil];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    WCRCWLogInfo(@"wkwebview判断是否取消加载:%@",self.url);
    if (navigationResponse.isForMainFrame && [navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]] && ((NSHTTPURLResponse *)navigationResponse.response).statusCode >= 400) {
        //mainFrame状态码400以上，算失败，取消加载，会自动走到失败的代理里面
        decisionHandler(WKNavigationResponsePolicyCancel);
    } else {
        decisionHandler(WKNavigationResponsePolicyAllow);
    }
}

-(void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler{
    WCRCWLogInfo(@"wkwebview需要进行身份验证:%@",self.url);
    NSURLCredential * credential = [[NSURLCredential alloc] initWithTrust:[challenge protectionSpace].serverTrust];
    completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    WCRCWLogInfo(@"wkwebview内容处理中断:%@",self.url);
    [webView reload];
}

-(WKWebView *)webView{
    if (!_webView) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.allowsInlineMediaPlayback = YES;
        config.mediaPlaybackRequiresUserAction = false;
        if ([_webView.scrollView respondsToSelector:@selector(setContentInsetAdjustmentBehavior:)]) {
            if (@available(iOS 11.0, *)) {
                _webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
            }
        }
        if([config respondsToSelector:@selector(setIgnoresViewportScaleLimits:)]) {
            if (@available(iOS 10.0, *)) {
                config.ignoresViewportScaleLimits = YES;
            }
        }
        if([config respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) {
            if (@available(iOS 10.0, *)) {
                config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
            }
        } else if ([config respondsToSelector:@selector(setRequiresUserActionForMediaPlayback:)]) {
            if (@available(iOS 9.0, *)) {
                config.requiresUserActionForMediaPlayback = NO;
            }
        } else if ([config respondsToSelector:@selector(setMediaPlaybackRequiresUserAction:)]) {
            config.mediaPlaybackRequiresUserAction = NO;
        }
        WCRWKWebviewMessageHandler *messageHandler = [[WCRWKWebviewMessageHandler alloc] init];
        messageHandler.delegate = self;
        [config.userContentController addScriptMessageHandler:messageHandler name:kWCRDocJSSDKScriptMessageHandler];
        
        _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
        _webView.allowsBackForwardNavigationGestures = YES;
        _webView.UIDelegate = self;
        _webView.navigationDelegate = self;
        _webView.opaque = NO;
        
        _webView.scrollView.bounces = NO;
        _webView.scrollView.bouncesZoom = NO;
        _webView.scrollView.scrollEnabled = NO;
        _webView.scrollView.delegate = self;
    }
    return _webView;
}

/** 禁用单指双击滚动课件 */
- (void)disableDoubleTapScroll {
    // iterate over all subviews of the WKWebView's scrollView
    for (UIView *subview in self.webView.scrollView.subviews) {
        // iterate over recognizers of subview
        for (UIGestureRecognizer *recognizer in subview.gestureRecognizers) {
            // check the recognizer is  a UITapGestureRecognizer
            if ([recognizer isKindOfClass:UITapGestureRecognizer.class]) {
                // cast the UIGestureRecognizer as UITapGestureRecognizer
                UITapGestureRecognizer *tapRecognizer = (UITapGestureRecognizer*)recognizer;
                // check if it is a 1-finger double-tap
                if (tapRecognizer.numberOfTapsRequired == 2 && tapRecognizer.numberOfTouchesRequired == 1) {
                    [subview removeGestureRecognizer:recognizer];
                }
            }
        }
    }
}

-(UIView *)view{
    return self.webView;
}

-(NSMutableSet *)messagesSet{
    if (!_messagesSet) {
        _messagesSet = [NSMutableSet set];
    }
    return _messagesSet;
}
@end