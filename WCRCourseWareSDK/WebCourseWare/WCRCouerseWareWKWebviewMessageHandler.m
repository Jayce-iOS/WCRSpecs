//
//  WCRCouerseWareWKWebviewMessageHandler.m
//  WCRWebView
//
//  Created by 欧阳铨 on 2018/10/31.
//  Copyright © 2018 oyq. All rights reserved.
//

#import "WCRCouerseWareWKWebviewMessageHandler.h"

@implementation WCRCouerseWareWKWebviewMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    if([self.delegate respondsToSelector:@selector(userContentController:didReceiveScriptMessage:)]){
        [self.delegate userContentController:userContentController didReceiveScriptMessage:message];
    }
}
@end