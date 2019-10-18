// AFSecurityPolicy.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
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

#import "AFSecurityPolicy.h"

#import <AssertMacros.h>

#if !TARGET_OS_IOS && !TARGET_OS_WATCH && !TARGET_OS_TV
static NSData * AFSecKeyGetData(SecKeyRef key) {
    CFDataRef data = NULL;

    __Require_noErr_Quiet(SecItemExport(key, kSecFormatUnknown, kSecItemPemArmour, NULL, &data), _out);

    return (__bridge_transfer NSData *)data;

_out:
    if (data) {
        CFRelease(data);
    }

    return nil;
}
#endif

//判断两个公钥是否相同
static BOOL AFSecKeyIsEqualToKey(SecKeyRef key1, SecKeyRef key2) {
#if TARGET_OS_IOS || TARGET_OS_WATCH || TARGET_OS_TV
    return [(__bridge id)key1 isEqual:(__bridge id)key2];
#else
    return [AFSecKeyGetData(key1) isEqual:AFSecKeyGetData(key2)];
#endif
}
// 获取证书中的公钥
static id AFPublicKeyForCertificate(NSData *certificate) {
    id allowedPublicKey = nil;
    SecCertificateRef allowedCertificate;
    SecPolicyRef policy = nil;
    SecTrustRef allowedTrust = nil;
    SecTrustResultType result;

    allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificate);
    __Require_Quiet(allowedCertificate != NULL, _out);

    policy = SecPolicyCreateBasicX509();
    __Require_noErr_Quiet(SecTrustCreateWithCertificates(allowedCertificate, policy, &allowedTrust), _out);
    __Require_noErr_Quiet(SecTrustEvaluate(allowedTrust, &result), _out);

    allowedPublicKey = (__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust);

_out:
    if (allowedTrust) {
        CFRelease(allowedTrust);
    }

    if (policy) {
        CFRelease(policy);
    }

    if (allowedCertificate) {
        CFRelease(allowedCertificate);
    }

    return allowedPublicKey;
}


// 这个方法用来验证serverTrust是否有效，其中主要是交由系统APISecTrustEvaluate来验证的，它验证完之后会返回一个SecTrustResultType枚举类型的result，然后我们根据这个result去判断是否证书是否有效。
static BOOL AFServerTrustIsValid(SecTrustRef serverTrust) {
    BOOL isValid = NO;
    SecTrustResultType result;
    
    //__Require_noErr_Quiet 用来判断前者是0还是非0，如果0则表示没错，就跳到后面的表达式所在位置去执行，否则表示有错就继续往下执行。
    //SecTrustEvaluate系统评估证书的是否可信的函数，去系统根目录找，然后把结果赋值给result。评估结果匹配，返回0，否则出错返回非0
    //do while 0 ,只执行一次，为啥要这样写....
    
    __Require_noErr_Quiet(SecTrustEvaluate(serverTrust, &result), _out);
    
    // kSecTrustResultUnspecified: 系统隐式地信任这个证书
    // This value may be returned by the SecTrustEvaluate function or stored as part of the user trust settings. In the Keychain Access utility, this value is called "Use System Policy." This is the default user setting.
    
    // kSecTrustResultProceed: 用户加入自己的信任锚点，显式地告诉系统这个证书是值得信任的
    // This value may be returned by the SecTrustEvaluate function or stored as part of the user trust settings. In the Keychain Access utility, this value is called "Always Trust."
    
    //__Require_noErr_Quiet 用来判断前者是0还是非0，如果0则表示没错，就跳到后面的表达式所在位置去执行，否则表示有错就继续往下执行。
    //SecTrustEvaluate系统评估证书的是否可信的函数，去系统根目录找，然后把结果赋值给result。评估结果匹配，返回0，否则出错返回非0
    //do while 0 ,只执行一次，为啥要这样写....

    isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
    
    //out函数块,如果为SecTrustEvaluate，返回非0，则评估出错，则isValid为NO
_out:
    return isValid;
}

//获取证书链
static NSArray * AFCertificateTrustChainForServerTrust(SecTrustRef serverTrust) {
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];

    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        [trustChain addObject:(__bridge_transfer NSData *)SecCertificateCopyData(certificate)];
    }

    return [NSArray arrayWithArray:trustChain];
}

// 从serverTrust中取出服务器端传过来的所有可用的证书，并依次得到相应的公钥
static NSArray * AFPublicKeyTrustChainForServerTrust(SecTrustRef serverTrust) {
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);

        SecCertificateRef someCertificates[] = {certificate};
        CFArrayRef certificates = CFArrayCreate(NULL, (const void **)someCertificates, 1, NULL);

        SecTrustRef trust;
        __Require_noErr_Quiet(SecTrustCreateWithCertificates(certificates, policy, &trust), _out);

        SecTrustResultType result;
        __Require_noErr_Quiet(SecTrustEvaluate(trust, &result), _out);

        [trustChain addObject:(__bridge_transfer id)SecTrustCopyPublicKey(trust)];

    _out:
        if (trust) {
            CFRelease(trust);
        }

        if (certificates) {
            CFRelease(certificates);
        }

        continue;
    }
    CFRelease(policy);

    return [NSArray arrayWithArray:trustChain];
}

#pragma mark -

@interface AFSecurityPolicy()
@property (readwrite, nonatomic, assign) AFSSLPinningMode SSLPinningMode;
@property (readwrite, nonatomic, strong) NSSet *pinnedPublicKeys;
@end

@implementation AFSecurityPolicy

+ (NSSet *)certificatesInBundle:(NSBundle *)bundle {
    NSArray *paths = [bundle pathsForResourcesOfType:@"cer" inDirectory:@"."];

    NSMutableSet *certificates = [NSMutableSet setWithCapacity:[paths count]];
    for (NSString *path in paths) {
        NSData *certificateData = [NSData dataWithContentsOfFile:path];
        [certificates addObject:certificateData];
    }

    return [NSSet setWithSet:certificates];
}

+ (NSSet *)defaultPinnedCertificates {
    static NSSet *_defaultPinnedCertificates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        _defaultPinnedCertificates = [self certificatesInBundle:bundle];
    });

    return _defaultPinnedCertificates;
}

+ (instancetype)defaultPolicy {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = AFSSLPinningModeNone;

    return securityPolicy;
}

+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode {
    return [self policyWithPinningMode:pinningMode withPinnedCertificates:[self defaultPinnedCertificates]];
}

+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode withPinnedCertificates:(NSSet *)pinnedCertificates {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = pinningMode;
    // 设置本地证书: 默认在bundle中查找
    [securityPolicy setPinnedCertificates:pinnedCertificates];

    return securityPolicy;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.validatesDomainName = YES;

    return self;
}

//设置证书数组
- (void)setPinnedCertificates:(NSSet *)pinnedCertificates {
    _pinnedCertificates = pinnedCertificates;

    if (self.pinnedCertificates) {
        NSMutableSet *mutablePinnedPublicKeys = [NSMutableSet setWithCapacity:[self.pinnedCertificates count]];
        for (NSData *certificate in self.pinnedCertificates) {
            id publicKey = AFPublicKeyForCertificate(certificate);
            if (!publicKey) {
                continue;
            }
            [mutablePinnedPublicKeys addObject:publicKey];
        }
        // 获取所有证书中的公钥
        self.pinnedPublicKeys = [NSSet setWithSet:mutablePinnedPublicKeys];
    } else {
        self.pinnedPublicKeys = nil;
    }
}

#pragma mark -

/** 术语解释 https://developer.apple.com/library/archive/technotes/tn2232/_index.html#//apple_ref/doc/uid/DTS40012884-CH1-SECGLOSSARY
 If you're not familiar with TLS, and specifically X.509 public key infrastructure, many of the terms used in this technote may be daunting. This glossary explains these terms and their specific meaning in this context.
 
 authentication challenge — An HTTP or HTTPS response indicating that the server requires authentication information from the client. Foundation represents this with the NSURLAuthenticationChallenge class, and it also uses this infrastructure to support custom HTTPS server trust evaluation. An authentication challenge originates from a protection space.
 
 certificate — See digital certificate.
 
 certificate authority — An organization responsible for issuing certificates. Each certificate authority publishes one or more root certificates for the purposes of evaluating trust on certificates issued by that authority. See also trusted certificate authority.
 
 certificate authority pinning — A stricter form of trust evaluation that requires that the server's certificate be issued by a specific certificate authority (not just any trusted certificate authority).
 
 certificate pinning — A stricter form of trust evaluation that requires that the server use a specific certificate or a certificate containing a specific public key.
 
 certificate revocation list (also CRL) — A list of certificates that have been revoked, and thus should not be trusted.
 
 CRL — See certificate revocation list.
 
 digital certificate (most commonly just certificate) — A data structure that uses a digital signature to associate information about an entity with a public key. In TLS, all digital certificates are actually X.509 digital certificates. See also subject, issuer, self-signed certificate, server certificate, intermediate certificate, root certificate and trusted anchor.
 
 digital identity (also identity) — The combination of a certificate and the private key associated with the public key embedded in that certificate.
 
 digital signature — A data structure that proves the authenticity of some other data. In public key cryptography, you can verify a digital signature with a public key and be guaranteed that it was created with the associated private key.
 
 extended validation — A strict trust evaluation policy used for extended validation certificates.
 
 HTTP — See Hypertext Transport Protocol.
 
 HTTPS — HTTP over TLS. See RFC 2818.
 
 HTTPS server trust evaluation — HTTPS is HTTP over TLS, so this is equivalent to TLS server trust evaluation.
 
 Hypertext Transport Protocol (also HTTP) — Really? You're looking this up in the glossary!?! Anyway, see RFC 2616.
 
 identity — See digital identity.
 
 intermediate certificate — A certificate that exists on the path of issuers between a server certificate and a root certificate.
 
 issuer — For an X.509 digital certificate, this is the entity that signed the certificate.
 
 OCSP — See Online Certificate Status Protocol.
 
 Online Certificate Status Protocol (also OCSP) — A protocol to check whether a digital certificate has been revoked. See RFC 2560.
 
 private key — Within public key cryptography, this is the key used to decrypt data or generate a digital signature.
 
 protection space (also realm) — An HTTP or HTTPS server, or an area on such a server, that requires authentication. Within Foundation this is represented by the NSURLProtectionSpace class. See also authentication challenge.
 
 public key — Within public key cryptography, this is the key used to encrypt data or verify a digital signature.
 
 public key cryptography — A cryptographic system that uses two separate keys, a public key to encrypt and a private key to decrypt. A private key can also be used to generate a digital signature, which a public key can verify.
 
 public key infrastructure — A mechanism for managing public and private keys, and specifically the way that a public key is embedded within a certificate. TLS uses the X.509 public key infrastructure.
 
 realm — See protection space.
 
 root certificate — A self-signed certificate provided by a certificate authority for the purposes of evaluating trust on certificates issued by that authority.
 
 Secure Sockets Layer (also SSL) — A predecessor to TLS.
 
 self-signed certificate — An X.509 digital certificate where the subject and the issuer are the same. Root certificates are self-signed, but anyone can create their own self-signed certificate.
 
 server certificate — The X.509 digital certificate provided by a TLS server. The TLS protocol ensures that the server holds the private key associated with the public key embedded in this certificate. It's this certificate that's the subject of TLS server trust evaluation.
 
 server trust evaluation — The trust evaluation mechanism used by a client to determine whether it trusts a server. In this context, this is a synonym for TLS server trust evaluation.
 
 SSL — See Secure Sockets Layer.
 
 subject — For an X.509 digital certificate, this is the entity that is identified by the certificate. In TLS the subject of a server certificate is typically the server's DNS name.
 
 TLS — See Transport Layer Security.
 
 TLS server trust evaluation — Trust evaluation that consists of X.509 certificate trust evaluation followed by additional TLS-specific checks. Operates on the server certificate.
 
 Transport Layer Security (also TLS) — A security protocol in common use on the Internet. The successor to SSL. See RFC 5246.
 
 trust evaluation — This is the process by which an entity decides whether to trust another entity, based on the other entity's digital certificate. See also TLS server trust evaluation.
 
 trusted anchor — A certificate that the system trusts implicitly. This is typically a certificate authority's root certificate that has been baked into the system, but in some situations you can programmatically mark any certificate as a trusted anchor.
 
 trusted certificate authority — A certificate authority whose root certificate is baked into the system as a trusted anchor.
 
 valid date range — For an X.509 digital certificate, this is the range of dates during which the certificate should be considered valid.
 
 verify date — In X.509 certificate trust evaluation, this is the date at which the trust evaluation is deemed to have occurred. This is relevant because each certificate includes a valid date range.
 
 X.509 certificate — See X.509 digital certificate.
 
 X.509 certificate trust evaluation — Trust evaluation based on X.509 certificates. See also TLS server trust evaluation.
 
 X.509 digital certificate (also X.509 certificate) — A specific type of digital certificate. This is the only type of certificate that's relevant to TLS.
 
 X.509 public key infrastructure — The public key infrastructure used by TLS.
 */


/**
 数字证书:
    数字证书的生成是分层级的，下一级的证书需要其上一级证书的私钥签名，所以后者是前者的证书颁发者。
    在得到证书申请者的一些必要信息（对象名称，公钥私钥）之后，证书颁发者通过 SHA-256 哈希得到证书内容的摘要，再用自己的私钥给这份摘要加密，得到数字签名。
    数字证书中重要信息:  公钥、数字签名(证书信息摘要后私钥加密的结果)、各种其他信息
 
 CA:
    数字证书认证机构（Certificate Authority, CA）签署和管理的 CA 根证书，会被纳入到你的浏览器和操作系统的可信证书列表中，并由这个列表判断根证书是否可信。所以不要随便导入奇奇怪怪的根证书到你的操作系统中。
 
 iOS中证书有效标准：
    When a TLS certificate is verified, the operating system verifies its chain of trust. If that chain of trust contains only valid certificates and ends at a known (trusted) anchor certificate, then the certificate is considered valid.
 信任链中如果只含有有效证书并且以可信锚点（trusted anchor）结尾，那么这个证书就被认为是有效的。
 其中可信锚点指的是系统隐式信任的证书，通常是包括在系统中的 CA 根证书。不过你也可以在验证证书链时，设置自定义的证书作为可信的锚点。
 

 通过分析源代码
 - (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
 forDomain:(NSString *)domain
     serverTrust
                CFType used for performing X.509 certificate trust evaluations.
                是一种执行信任链验证的抽象实体，包含着验证策略（SecPolicyRef）以及一系列受信任的锚点证书
                The trust management object containing the certificate you want to evaluate. A trust management object includes the certificate to be verified plus the policy or policies to be used in evaluating trust. It can optionally also include other certificates to be used in verifying the first certificate. Use the SecTrustCreateWithCertificates function to create a trust management object.
 
     AFSSLPinningModeNone: 采用系统root证书验证服务器返回的证书。
     AFSSLPinningModePublicKey: 采用预埋证书【pinnedCertificates】校验服务器返回的证书公约。
     AFSSLPinningModeCertificate: 采用预埋证书【pinnedCertificates】校验服务器返回的证书。（可防止中间人攻击 如charls这种抓包工具）
     注意：
     validatesDomainName 是否校验证书域名
 
     allowInvalidCertificates 定义了客户端是否信任非法证书。一般来说，每个版本的iOS设备中，都会包含一些既有的CA根证书。如果接收到的证书是iOS信任的CA根证书签名的，那么则为合法证书；否则则为“非法”证书。allowInvalidCertificates 就是用来确认是否信任这样的证书的。当然，我们也可以给iOS加入新的信任的CA证书
 
     allowInvalidCertificates 是否允许非法证书，基本模式预埋证书都是未经过第三方权威机构签名的证书 故使用 AFSSLPinningModePublicKey和 AFSSLPinningModeCertificate 时候 请将其设置成YES
     validatesCertificateChain 是否校验服务服务器证书签发root证书
 */

/// AF可以让你在系统验证证书之前，就去自主验证。然后如果自己验证不正确，直接取消网络请求。否则验证通过则继续进行系统验证。
- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain
{
    
    //判断矛盾的条件
    //判断有域名，且允许自建证书，需要验证域名，
    //因为要验证域名，所以必须不能是后者两种：AFSSLPinningModeNone或者添加到项目里的证书为0个。
    if (domain && self.allowInvalidCertificates && self.validatesDomainName && (self.SSLPinningMode == AFSSLPinningModeNone || [self.pinnedCertificates count] == 0)) {
        // https://developer.apple.com/library/mac/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/OverridingSSLChainValidationCorrectly.html
        //  According to the docs, you should only trust your provided certs for evaluation.
        //  Pinned certificates are added to the trust. Without pinned certificates,
        //  there is nothing to evaluate against.
        //
        //  From Apple Docs:
        //          "Do not implicitly trust self-signed certificates as anchors (kSecTrustOptionImplicitAnchors).
        //           Instead, add your own (self-signed) CA certificate to the list of trusted anchors."
        NSLog(@"In order to validate a domain name for self signed certificates, you MUST use pinning.");
        //不受信任，返回
        return NO;
    }

    NSMutableArray *policies = [NSMutableArray array];
    if (self.validatesDomainName) {
        // 如果需要验证domain，那么就使用SecPolicyCreateSSL函数创建验证策略，其中第一个参数为true表示验证整个SSL证书链，第二个参数传入domain，用于判断整个证书链上叶子节点表示的那个domain是否和此处传入domain一致
        //添加验证策略
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        // 如果不需要验证domain，就使用默认的BasicX509验证策略
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }
    // 为serverTrust设置验证策略，即告诉客户端如何验证serverTrust
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
    // 如果是采用系统root证书验证服务器返回的证书的情况
    if (self.SSLPinningMode == AFSSLPinningModeNone) {
        //如果允许无效证书，直接返回YES,不允许才去判断第二个条件，判断serverTrust是否有效
        return self.allowInvalidCertificates || AFServerTrustIsValid(serverTrust);
        
        //如果验证无效AFServerTrustIsValid，而且allowInvalidCertificates不允许无效证书，返回NO
    } else if (!AFServerTrustIsValid(serverTrust) && !self.allowInvalidCertificates) {
        return NO;
    }

    switch (self.SSLPinningMode) {
        case AFSSLPinningModeNone:
        default:
            return NO;
        // 采用预埋证书【pinnedCertificates】校验服务器返回的证书。
        case AFSSLPinningModeCertificate: {
            NSMutableArray *pinnedCertificates = [NSMutableArray array];
            //把证书data，用系统api转成 SecCertificateRef 类型的数据,SecCertificateCreateWithData函数对原先的pinnedCertificates做一些处理，保证返回的证书都是DER编码的X.509证书
            for (NSData *certificateData in self.pinnedCertificates) {
                [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
            }
           
            /**
             自签名的证书链验证
             在 App 中想要防止上面提到的中间人攻击，比较好的做法是将公钥证书打包进 App 中，然后在收到服务端证书链的时候，能够有效地验证服务端是否可信，这也是验证自签名的证书链所必须做的。
             假设你的服务器返回：[你的自签名的根证书] -- [你的二级证书] -- [你的客户端证书]，系统是不信任这个三个证书的。
             所以你在验证的时候需要将这三个的其中一个设置为锚点证书，当然，多个也行。
             比如将 [你的二级证书] 作为锚点后，SecTrustEvaluate() 函数只要验证到 [你的客户端证书] 确实是由 [你的二级证书] 签署的，那么验证结果为 kSecTrustResultUnspecified，表明了 [你的客户端证书] 是可信的。
             
                kSecTrustResultUnspecified: 系统隐式地信任这个证书
                This value may be returned by the SecTrustEvaluate function or stored as part of the user trust settings. In the Keychain Access utility, this value is called "Use System Policy." This is the default user setting.
             
                kSecTrustResultProceed: 用户加入自己的信任锚点，显式地告诉系统这个证书是值得信任的
                This value may be returned by the SecTrustEvaluate function or stored as part of the user trust settings. In the Keychain Access utility, this value is called "Always Trust."
             
             CA 证书链的验证
             上面说的是没经过 CA 认证的自签证书的验证，而 CA 的证书链的验证方式也是一样，不同点在不可信锚点的证书类型不一样而已：前者的锚点是自签的需要被打包进 App 用于验证，后者的锚点可能本来就存在系统之中了。
             */
            
            // 设置锚点证书
            SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);

            if (!AFServerTrustIsValid(serverTrust)) {
                return NO;
            }

            // obtain the chain after being validated, which *should* contain the pinned certificate in the last position (if it's the Root CA)
            //注意，这个方法和我们之前的锚点证书没关系了，是去从我们需要被验证的服务端证书，去拿证书链。
            // 服务器端的证书链，注意此处返回的证书链顺序是从叶节点到根节点
            NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
            
            for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
                //如果我们的证书中，有一个和它证书链中的证书匹配的，就返回YES
                if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
                    return YES;
                }
            }
            
            return NO;
        }
        // 采用预埋证书【pinnedCertificates】校验服务器返回的证书公约
        //公钥验证 AFSSLPinningModePublicKey模式同样是用证书绑定(SSL Pinning)方式验证，客户端要有服务端的证书拷贝，只是验证时只验证证书里的公钥，不验证证书的有效期等信息。只要公钥是正确的，就能保证通信不会被窃听，因为中间人没有私钥，无法解开通过公钥加密的数据。
        case AFSSLPinningModePublicKey: {
            NSUInteger trustedPublicKeyCount = 0;
            // 从serverTrust中取出服务器端传过来的所有可用的证书，并依次得到相应的公钥
            NSArray *publicKeys = AFPublicKeyTrustChainForServerTrust(serverTrust);
            //遍历服务端公钥
            for (id trustChainPublicKey in publicKeys) {
                //遍历本地公钥
                for (id pinnedPublicKey in self.pinnedPublicKeys) {
                    if (AFSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
                        trustedPublicKeyCount += 1;
                    }
                }
            }
            return trustedPublicKeyCount > 0;
        }
    }
    
    return NO;
}

#pragma mark - NSKeyValueObserving

+ (NSSet *)keyPathsForValuesAffectingPinnedPublicKeys {
    return [NSSet setWithObject:@"pinnedCertificates"];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {

    self = [self init];
    if (!self) {
        return nil;
    }

    self.SSLPinningMode = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(SSLPinningMode))] unsignedIntegerValue];
    self.allowInvalidCertificates = [decoder decodeBoolForKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    self.validatesDomainName = [decoder decodeBoolForKey:NSStringFromSelector(@selector(validatesDomainName))];
    self.pinnedCertificates = [decoder decodeObjectOfClass:[NSArray class] forKey:NSStringFromSelector(@selector(pinnedCertificates))];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[NSNumber numberWithUnsignedInteger:self.SSLPinningMode] forKey:NSStringFromSelector(@selector(SSLPinningMode))];
    [coder encodeBool:self.allowInvalidCertificates forKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    [coder encodeBool:self.validatesDomainName forKey:NSStringFromSelector(@selector(validatesDomainName))];
    [coder encodeObject:self.pinnedCertificates forKey:NSStringFromSelector(@selector(pinnedCertificates))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFSecurityPolicy *securityPolicy = [[[self class] allocWithZone:zone] init];
    securityPolicy.SSLPinningMode = self.SSLPinningMode;
    securityPolicy.allowInvalidCertificates = self.allowInvalidCertificates;
    securityPolicy.validatesDomainName = self.validatesDomainName;
    securityPolicy.pinnedCertificates = [self.pinnedCertificates copyWithZone:zone];

    return securityPolicy;
}

@end
