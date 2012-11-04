//
//  SPListItem.m
//
//  Copyright (c) 2012 Nathan Wood (http://www.woodnathan.com/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


#import "SPListItem.h"
#import "SPContext.h"

@implementation SPListItem

@synthesize listName = _listName;
@dynamic title, filename, URLString, contentType, fileRef, modifiedDate;

+ (NSDictionary *)propertyToAttributeMap
{
    return @{ @"title" : @"ows_Title", @"filename" : @"ows_LinkFilename", @"URLString" : @"ows_EncodedAbsUrl", @"contentType" : @"ows_ContentType", @"fileRef" : @"ows_FileRef", @"modifiedDate" : @"ows_Modified" };
}

+ (NSArray *)dateProperties
{
    return @[ @"modifiedDate" ];
}

- (void)loadChildren:(void (^)(NSArray *items))completion
{
    [self.context getList:self.listName
                parentRef:self.fileRef
                    items:^(NSArray *items) {
                        self.children = items;
                        [self.children makeObjectsPerformSelector:@selector(setParent:) withObject:self];
                        
                        if (completion)
                            completion(items);
                    }];
}

@end