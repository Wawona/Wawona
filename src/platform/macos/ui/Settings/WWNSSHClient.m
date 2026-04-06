#import "WWNSSHClient.h"
#import <unistd.h>

// Note: WWNSSHClient is deprecated - using OpenSSH binary instead
// This file is kept for compilation compatibility but all methods are stubbed out

@interface WWNSSHClient ()
{
  int _sock;
  BOOL _isConnected;
  BOOL _isAuthenticated;
}
@end

@implementation WWNSSHClient

- (instancetype)initWithHost:(NSString *)host username:(NSString *)username port:(NSInteger)port {
  self = [super init];
  if (self) {
    _host = [host copy];
    _username = [username copy];
    _port = port > 0 ? port : 22;
    _connectionTimeout = 30.0;
    _readTimeout = 10.0;
    _authMethod = WWNSSHAuthMethodPassword;
    _sock = -1;
    _isConnected = NO;
    _isAuthenticated = NO;
  }
  return self;
}

- (void)dealloc {
  [self disconnect];
}

- (BOOL)connect:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNSSHClient"
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey: @"WWNSSHClient is deprecated. Use OpenSSH binary instead."}];
  }
  return NO;
}

- (BOOL)authenticate:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNSSHClient"
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey: @"WWNSSHClient is deprecated. Use OpenSSH binary instead."}];
  }
  return NO;
}

- (void)disconnect {
  _isConnected = NO;
  _isAuthenticated = NO;
  if (_sock >= 0) {
    close(_sock);
    _sock = -1;
  }
}

- (BOOL)executeCommand:(NSString *)command output:(NSString *__autoreleasing _Nullable *)output error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNSSHClient"
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey: @"WWNSSHClient is deprecated. Use OpenSSH binary instead."}];
  }
  if (output) {
    *output = nil;
  }
  return NO;
}

- (BOOL)forwardLocalPort:(NSInteger)localPort toRemoteHost:(NSString *)remoteHost remotePort:(NSInteger)remotePort error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNSSHClient"
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey: @"WWNSSHClient is deprecated. Use OpenSSH binary instead."}];
  }
  return NO;
}

- (int)createShellChannel:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNSSHClient"
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey: @"WWNSSHClient is deprecated. Use OpenSSH binary instead."}];
  }
  return -1;
}

- (int)socketFileDescriptor {
  return _sock;
}

- (BOOL)createBidirectionalChannelWithLocalFD:(int *)localFd remoteFD:(int *)remoteFd error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNSSHClient"
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey: @"WWNSSHClient is deprecated. Use OpenSSH binary instead."}];
  }
  return NO;
}

- (BOOL)startTunnelForCommand:(nullable NSString *)command localSocket:(int *)localSocket error:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:@"WWNSSHClient"
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey: @"WWNSSHClient is deprecated. Use OpenSSH binary instead."}];
  }
  return NO;
}

@end
