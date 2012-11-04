//
//  SPMessage.m
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

#import "SPMessage.h"
#import <libxml/xpath.h>
#import <libxml/xpathInternals.h>

char * const SPMessageNamespaceURISchemaInstance = "http://www.w3.org/2001/XMLSchema-instance";
char * const SPMessageNamespaceURISchema         = "http://www.w3.org/2001/XMLSchema";
char * const SPMessageNamespaceURISOAP12         = "http://www.w3.org/2003/05/soap-envelope";
char * const SPMessageNamespaceURISharePointSOAP = "http://schemas.microsoft.com/sharepoint/soap/";
char * const SPMessageNamespaceRowset            = "urn:schemas-microsoft-com:rowset";
char * const SPMessageNamespaceRowsetSchema      = "#RowsetSchema";


static NSMutableString *xmlErrorMessage = nil;
static void xmlErrorFunc(void *ctx, const char *msg, ...)
{
    if (xmlErrorMessage == nil)
        xmlErrorMessage = [[NSMutableString alloc] init];
    
    NSString *fmt = [[NSString alloc] initWithCString:msg encoding:NSUTF8StringEncoding];
    va_list args;
    va_start(args, msg);
    NSString *str = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    
    [xmlErrorMessage appendString:str];
}


@interface SPMessage () {
    xmlDocPtr _xmlDoc;
@protected
    xmlNodePtr _methodNode;
}

+ (xmlNodePtr)newSOAPEnvelopeNode;

- (void)enumerateNodesForXPath:(NSString *)path namespace:(void (^)(xmlXPathContextPtr ctx))namespace withBlock:(void (^)(xmlNodePtr node))block;

@end


@implementation SPMessage

- (id)initWithMethod:(NSString *)method
{
    self = [super init];
    if (self)
    {
        _xmlDoc = xmlNewDoc(NULL);
        
        xmlNodePtr envelope = [[self class] newSOAPEnvelopeNode];
        xmlDocSetRootElement(_xmlDoc, envelope);
        
        _methodNode = xmlNewNode(NULL, (xmlChar *)[method UTF8String]);
        xmlNewNs(_methodNode, (xmlChar*)SPMessageNamespaceURISharePointSOAP, NULL);
        xmlAddChild(xmlGetLastChild(envelope), _methodNode);
    }
    return self;
}

- (id)initWithData:(NSData *)data error:(NSError **)error
{
    self = [super init];
    if (self)
    {
        xmlSetGenericErrorFunc(NULL, xmlErrorFunc);
        
        _xmlDoc = xmlReadMemory((const char *)[data bytes], (int)[data length], NULL, NULL, XML_PARSE_NOCDATA | XML_PARSE_NOBLANKS);
        
        if (_xmlDoc == NULL && error)
        {
            NSString *reason = [xmlErrorMessage copy];
            [xmlErrorMessage setString:@""];
            NSDictionary *userInfo = @{ NSLocalizedFailureReasonErrorKey : reason };
            *error = [NSError errorWithDomain:@"com.woodnathan.SPConnector"
                                         code:-1
                                     userInfo:userInfo];
        }
    }
    return self;
}

- (void)dealloc
{
    xmlFreeDoc(_xmlDoc);
    _methodNode = NULL;
    _xmlDoc = NULL;
}

+ (xmlNodePtr)newSOAPEnvelopeNode
{
    xmlNodePtr envelope = NULL, body = NULL;
    
    xmlNsPtr soapNS = xmlNewNs(NULL, (xmlChar*)SPMessageNamespaceURISOAP12, (xmlChar*)"soap12");
    
    envelope = xmlNewNode(soapNS, (xmlChar*)"Envelope");
    body = xmlNewNode(soapNS, (xmlChar*)"Body");
    
    xmlNewNs(envelope, (xmlChar*)SPMessageNamespaceURISchema, (xmlChar*)"xsi");
    xmlNewNs(envelope, (xmlChar*)SPMessageNamespaceURISchemaInstance, (xmlChar*)"xsd");
    xmlNewNs(envelope, (xmlChar*)SPMessageNamespaceURISOAP12, (xmlChar*)"soap12");
    
    xmlAddChild(envelope, body);
    
    return envelope;
}

- (xmlDocPtr)XMLDocument
{
    return _xmlDoc;
}

- (xmlNodePtr)rootElement
{
    return xmlDocGetRootElement(_xmlDoc);
}

- (xmlNodePtr)methodElement
{
    return _methodNode;
}

- (NSData *)XMLData
{
    if (_xmlDoc)
    {
        xmlChar *buffer = NULL;
        int bufferSize = 0;
        
        xmlDocDumpMemory(_xmlDoc, &buffer, &bufferSize);
        
        if (buffer)
        {
            NSData *data = [[NSData alloc] initWithBytes:buffer length:bufferSize];
            xmlFree(buffer);
            return data;
        }
    }
    return nil;
}

- (void)enumerateNodesForXPath:(NSString *)path namespace:(void (^)(xmlXPathContextPtr ctx))namespace withBlock:(void (^)(xmlNodePtr node))block
{
    xmlXPathContextPtr ctx = xmlXPathNewContext(_xmlDoc);
    
    if (namespace)
        namespace(ctx);
    
    xmlChar *xpath = (xmlChar *)[path UTF8String];
    xmlXPathObjectPtr obj = xmlXPathEvalExpression(xpath, ctx);
    
    if (obj && xmlXPathNodeSetIsEmpty(obj->nodesetval) == NO)
    {
        for (int i = 0; i < xmlXPathNodeSetGetLength(obj->nodesetval); i++)
        {
            xmlNodePtr currNode = obj->nodesetval->nodeTab[i];
            
            if (block)
                block(currNode);
        }
    }
    
    xmlXPathFreeObject(obj);
    xmlXPathFreeContext(ctx);
}

- (void)enumerateNodesForXPath:(NSString *)path withBlock:(void (^)(xmlNodePtr node))block
{
    [self enumerateNodesForXPath:path
                       namespace:^(xmlXPathContextPtr ctx) {
                           xmlXPathRegisterNs(ctx, (xmlChar*)"soap", (xmlChar*)SPMessageNamespaceURISharePointSOAP);
                       }
                       withBlock:block];
}

- (void)enumerateRowNodesForXPath:(NSString *)path withBlock:(void (^)(xmlNodePtr node))block
{
    [self enumerateNodesForXPath:path
                       namespace:^(xmlXPathContextPtr ctx) {
                           xmlXPathRegisterNs(ctx, (xmlChar*)"z", (xmlChar*)SPMessageNamespaceRowsetSchema);
                           xmlXPathRegisterNs(ctx, (xmlChar*)"rs", (xmlChar*)SPMessageNamespaceRowset);
                       }
                       withBlock:block];
}

@end