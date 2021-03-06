//
//  SPMethod.m
//
//  Copyright (c) 2013 Nathan Wood (http://www.woodnathan.com/)
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

#import "SPMethod.h"
#import "SPMessage.h"
#import "SPMethodRequest.h"
#import "SPContext.h"
#import "SPObject.h"
#import <libxml/tree.h>
#import <libxml/xpath.h>
#import <libxml/xpathInternals.h>
#import "SPCAMLQuery.h"

@interface SPMethod () {
@protected
    SPCAMLQueryOptions *_queryOptions;
}

@property (nonatomic, assign, readwrite) BOOL isExecuting;
@property (nonatomic, assign, readwrite) BOOL isFinished;

@property (nonatomic, weak, readwrite) SPContext *context;

@property (nonatomic, strong, readwrite) SPMessage *requestMessage;
@property (nonatomic, strong, readwrite) SPMessage *responseMessage;
@property (nonatomic, strong, readwrite) NSArray *responseObjects;

@property (nonatomic, strong, readwrite) NSError *error;

@property (nonatomic, strong) NSObject <SPMethodRequestOperation>* requestOperation;

- (void)finish;

@end


@implementation SPMethod

@synthesize context = _context, delegate = _delegate;
@synthesize requestMessage = _requestMessage, responseMessage = _responseMessage;
@synthesize queryOptions = _queryOptions;
@synthesize predicate = _predicate, sortDescriptors = _sortDescriptors;
@synthesize dateRangeOverlapValue = _dateRangeOverlapValue;
@synthesize responseObjects = _responseObjects;
@synthesize error = _error;
@synthesize isExecuting = _isExecuting, isFinished = _isFinished;
@synthesize requestOperation = _requestOperation;

- (id)initWithContext:(SPContext *)context
{
    self = [super init];
    if (self)
    {
        self.context = context;
        
        self.requestMessage = [[SPMessage alloc] initWithMethod:[[self class] method] version:context.version];
    }
    return self;
}

+ (NSString *)method
{
    return nil;
}

+ (NSString *)endpoint
{
    return nil;
}

+ (NSString *)objectPath
{
    return nil;
}

+ (Class)objectClass
{
    return Nil;
}

+ (NSString *)SOAPAction
{
    return nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == self.requestOperation)
        [self finish];
}

- (SPCAMLQueryOptions *)queryOptions
{
    if (self->_queryOptions == nil)
        self->_queryOptions = [[SPCAMLQueryOptions alloc] init];
    
    return self->_queryOptions;
}

- (void)start
{
    [self willChangeValueForKey:@"isExecuting"];
    self.isExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    NSURL *URL = [self.context URLRelativeToSiteWithString:[[self class] endpoint]];
    NSMutableURLRequest *URLRequest = [[NSMutableURLRequest alloc] initWithURL:URL];
    
    self.queryOptions.dateInUTC = YES;
    
    [self prepareRequestMessage];
    
    xmlNodePtr queryOptsElement = [self->_queryOptions queryOptionsNode];
    if (queryOptsElement)
    {
        xmlNodePtr rootQueryOptsElement = xmlNewNode(NULL, (xmlChar *)"queryOptions");
        xmlAddChild(rootQueryOptsElement, queryOptsElement);
        [self.requestMessage addMethodElementChild:rootQueryOptsElement];
    }
    
    xmlNodePtr queryElement = [SPCAMLQuery queryElementWithPredicate:self.predicate sortDescriptors:self.sortDescriptors];
    if (self.dateRangeOverlapValue)
    {
        if (queryElement == NULL)
            queryElement = xmlNewNode(NULL, (xmlChar *)"Query");
        
        xmlNodePtr overlap = xmlNewNode(NULL, (xmlChar *)"DateRangesOverlap");
        xmlNodePtr eventDateField = xmlNewNode(NULL, (xmlChar *)"FieldRef");
        xmlNewProp(eventDateField, (xmlChar *)"Name", (xmlChar *)"EventDate");
        xmlAddChild(overlap, eventDateField);
        xmlNodePtr endDateField = xmlNewNode(NULL, (xmlChar *)"FieldRef");
        xmlNewProp(endDateField, (xmlChar *)"Name", (xmlChar *)"EndDate");
        xmlAddChild(overlap, endDateField);
        xmlNodePtr recurrenceField = xmlNewNode(NULL, (xmlChar *)"FieldRef");
        xmlNewProp(recurrenceField, (xmlChar *)"Name", (xmlChar *)"RecurrenceID");
        xmlAddChild(overlap, recurrenceField);
        xmlNodePtr valueField = xmlNewNode(NULL, (xmlChar *)"Value");
        xmlNewProp(valueField, (xmlChar *)"Type", (xmlChar *)"DateTime");
        xmlAddChild(valueField, xmlNewNode(NULL, (xmlChar *)[self.dateRangeOverlapValue UTF8String]));
        xmlAddChild(overlap, valueField);
        
        xmlNodePtr currNode = NULL;
        for (currNode = queryElement->children; currNode != NULL; currNode = currNode->next)
        {
            if (xmlStrcmp(currNode->name, (xmlChar *)"Where") == 0)
                break;
        }
        if (currNode == NULL)
        {
            currNode = xmlNewNode(NULL, (xmlChar *)"Where");
            xmlAddChild(queryElement, currNode);
        }
        
        xmlAddChild(currNode, overlap);
    }
    
    if (queryElement)
    {
        xmlNodePtr rootQueryElement = xmlNewNode(NULL, (xmlChar *)"query");
        xmlAddChild(rootQueryElement, queryElement);
        [self.requestMessage addMethodElementChild:rootQueryElement];
    }
    
    NSData *XMLData = [self.requestMessage XMLData];
    
    [URLRequest setHTTPMethod:@"POST"];
    
    SPSOAPVersion version = self.context.version;
    switch (version) {
        case SPSOAPVersion11:{
            [URLRequest setValue:@"text/xml; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
            NSString *action = [[self class] SOAPAction];
            if (action)
                [URLRequest setValue:[NSString stringWithFormat:@"\"%@\"", action] forHTTPHeaderField:@"SOAPAction"];
            break;
        }
        case SPSOAPVersion12:
        default:{
            [URLRequest setValue:@"application/soap+xml; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
            [URLRequest setValue:@"application/soap+xml; charset=utf-8" forHTTPHeaderField:@"Accept"];
            break;
        }
    }
    
    [URLRequest setHTTPBody:XMLData];
    
    self.requestOperation = [self.context requestOperationWithRequest:URLRequest];
    [self.requestOperation addObserver:self
                            forKeyPath:@"isFinished"
                               options:(NSKeyValueObservingOptionOld |  NSKeyValueObservingOptionNew)
                               context:NULL];
    [self.requestOperation start];
}

- (void)finish
{
    NSObject <SPMethodRequestOperation> *requestOperation = self.requestOperation;
    NSError *requestError = requestOperation.error;
    NSError *messageError = nil;
    self.responseMessage = [[SPMessage alloc] initWithData:[self.requestOperation responseData]
                                                     error:&messageError];
    NSError *error = (requestError != nil) ? requestError : messageError;
    if (error)
    {
        self.error = error;
        [self.delegate method:self didFailWithError:error];
    }
    
    [self parseResponseMessage];
    
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    self.isExecuting = NO;
    self.isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (void)prepareRequestMessage
{
    
}

- (void)parseResponseMessage
{
    NSMutableArray *objects = [[NSMutableArray alloc] init];
    
    NSString *path = [[self class] objectPath];
    [self.responseMessage enumerateNodesForXPath:path withBlock:^(xmlNodePtr node, BOOL *stop) {
        id obj = [[[self class] objectClass] alloc];
        obj = [obj initWithNode:node context:self.context];
        [objects addObject:obj];
    }];
    
    self.responseObjects = [objects copy];
}

@end
