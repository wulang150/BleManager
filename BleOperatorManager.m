//
//  BleOperatorManager.m
//
#import <UIKit/UIKit.h>
#import "BleOperatorManager.h"
//#import "BleUUIDMecro.h"
#import "BleConnectMacro.h"

@interface BleOperatorManager()<CBPeripheralDelegate,CBCentralManagerDelegate>
{
    NSTimer *connectTimer;      //处理连接超时
}

/*!
   btle连接以及数据通信的队列
 */
@property (nonatomic, strong) dispatch_queue_t centralQueue;
/*!
   btle建立连接时的选项
 */
@property (nonatomic, strong) NSDictionary *options;

/*!
   搜索到的外设的容器 peripheral
 */
@property (nonatomic, strong)NSMutableArray *discoveredTargetsArray;
/*!
 *  discoveredTargetsArray容器中特定UUID对应的RSSI值 key:peripheral.identifier.UUIDString
 */
@property (nonatomic, strong)NSMutableDictionary *discoveredTargetsRSSI;
/*!
 *  discoveredTargetsArray容器中特定UUID对应的mac地址
 */
@property (nonatomic, strong)NSMutableDictionary *discoveredDevMacDic;

/*!
 *  实时连接的central对象
 */
@property (nonatomic, strong)CBCentralManager *centralManager;

/*!
 *  存放对应服务以及特性下对应的CBCharacteristic，由于后面的数据交互
 */
@property (nonatomic, strong)NSMutableDictionary *peripheralServiceCharaDic;

@end


@implementation BleOperatorManager


/*!
 重载单例重的初始化方法

 @return 返回对应的单例
 */
+ (BleOperatorManager *)sharedInstance
{
    static id shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,
                  ^{
                      shared = [[self alloc] init];
                  });
    return shared;
}

/*!
 重载单例重的初始化方法

 @return 返回单例本身
 */
-(id)init
{
    if (self = [super init])
    {
        [self initCentralDevice];
    }
    
    return self;
}

/*!
 *  初始化连接的条件
 */

-(void)initCentralDevice
{
    
    self.options = @{CBCentralManagerOptionRestoreIdentifierKey:@"myCentralManagerIdentifier",
                     CBCentralManagerOptionShowPowerAlertKey:@YES
                     };
    //这里设置了蓝牙不在主线程中执行，所以注意，蓝牙的所有代理都是子线程的
    _centralQueue = dispatch_queue_create("central", DISPATCH_QUEUE_SERIAL); ///<不在main thread中执行

    _centralManager = [[CBCentralManager alloc]initWithDelegate:self queue:_centralQueue options:self.options];
    
    _discoveredTargetsRSSI = [NSMutableDictionary new];
    _discoveredTargetsArray = [NSMutableArray new];
    _discoveredDevMacDic = [NSMutableDictionary new];
    
    _isAutoConnected = YES;
    
    
}

//把uuid字符串改为统一的格式
- (NSString *)UUIDString:(NSString *)str
{
    CBUUID *suid = [CBUUID UUIDWithString:str];
    
    return suid.UUIDString;
}

//- (void)setBleServiceAndCharater:(NSDictionary *)bleServiceAndCharater
//{
//    NSMutableDictionary *mulDic = [NSMutableDictionary new];
//
//    for(NSString *server in [bleServiceAndCharater allKeys])
//    {
//        //特征
//        NSArray *cArr = [bleServiceAndCharater objectForKey:server];
//        if(![cArr isKindOfClass:[NSArray class]])
//            continue;
//        NSMutableArray *mulArr = [NSMutableArray new];
//        for(NSString *chid in cArr)
//        {
//            if(![chid isKindOfClass:[NSString class]])
//                continue;
//            CBUUID *cb = [CBUUID UUIDWithString:chid];
//            [mulArr addObject:cb];
//        }
//        [mulDic setObject:mulArr forKey:[self UUIDString:server]];
//    }
//
//    _bleServiceAndCharater = [mulDic copy];
//}

/*!
 开始搜索外围设备，首先会检索系统蓝牙有没有该UUID对应的蓝牙外设正在连接，若有则直接连接，如果没有才会进行搜索设备
 
 @param adverUUIDArray 需要搜索的广播包中包含的UUID
 */
-(void)startScanDevice:(NSArray *)adverUUIDArray
{
    if(!adverUUIDArray)
        adverUUIDArray = @[];
    
    [_discoveredTargetsArray removeAllObjects];
    [_discoveredTargetsRSSI removeAllObjects];
    [_discoveredDevMacDic removeAllObjects];
    
    dispatch_async(_centralQueue
                   , ^{
                       
                       if (self.centralManager.state == CBManagerStatePoweredOn)
                       {
                           //如果没有主动调用断连，这里还是可以获取到，有连接记录的，就直接重连
                           NSArray *deviceArray = [self.centralManager retrieveConnectedPeripheralsWithServices:adverUUIDArray];
                           if ([deviceArray count]>0)
                           {
                               self.m_peripheral = deviceArray[0];
                               [self connectSelectPeripheral:self.m_peripheral];
                               
                               NSLog(@"%@",[NSString stringWithFormat:@"%@",self.m_peripheral.name]);
                               
                           }
                           else
                           {
                               
                               [self.centralManager scanForPeripheralsWithServices:adverUUIDArray options:@{CBCentralManagerScanOptionAllowDuplicatesKey:[NSNumber numberWithBool:NO]}];
                           }
                       }
                   });
}


/*!
 *  停止搜索外围设备
 */
-(void)stopScanDevice
{
    //@停止扫描
    [self.centralManager stopScan];
    NSLog(@"Stopped Scan.");
    
}


/*!
 *  连接选择的外围设备
 *
 *  @param peripheral 指定的外围设备
 */
-(void)connectSelectPeripheral:(CBPeripheral *)peripheral
{
    if (peripheral != nil)
    {
        self.m_peripheral = peripheral;
        self.m_peripheral.delegate = self;
        [self.centralManager connectPeripheral:peripheral options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey:[NSNumber numberWithBool:YES]}];
        
        //连接的时候，保存mac地址
        NSString *mac = [_discoveredDevMacDic objectForKey:peripheral.identifier.UUIDString];
        if(mac)
            [[NSUserDefaults standardUserDefaults] setObject:mac forKey:BLEBANDMACADDRESSTEMP];
        
        //通知
        [[NSNotificationCenter defaultCenter] postNotificationName:BLE_CURRENT_STATE object:@(BLE_CONNECTING)];
        
        //加入连接超时处理
        if(connectTimer)
        {
            [connectTimer invalidate];
            connectTimer = nil;
        }
        
        connectTimer = [NSTimer scheduledTimerWithTimeInterval:26 target:self selector:@selector(connectTimeOutOpt) userInfo:nil repeats:NO];
    }
}

//连接超时的处理
- (void)connectTimeOutOpt
{
    if(connectTimer)
    {
        [connectTimer invalidate];
        connectTimer = nil;
    }
    
    [self cancelConnectPeripheral:self.m_peripheral];
    //没连接上，是不会调用连接失败的代理的，所以这里我主动调用了失败后的处理
    [self performSelectorOnMainThread:@selector(setStateNotConnected:) withObject:nil waitUntilDone:NO];
}
/*!
 *  取消连接指定的外围设备
 *
 *  @param peripheral 指定的外围设备
 */
-(void)cancelConnectPeripheral:(CBPeripheral *)peripheral
{
    
    if (peripheral != nil)
    {
        NSLog(@"cancelPeripheralConnection");
        [self.centralManager cancelPeripheralConnection:peripheral];
    }
}


/*!
 *  若有连接记录则重新连接指定BLEConnectedPeripheralUUID的设备
 */
- (void)connectedBand
{
    
    if (!_isAutoConnected)
    {
        return;
    }
    
    NSString *uuidStr = [[NSUserDefaults standardUserDefaults] objectForKey:BLEConnectedPeripheralUUID];
    //有连接记录
    if (uuidStr != nil)
    {
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidStr];
        //如果只是主动调用断连接口，这里还是可以获取到重连信息的
        NSArray *array = [self.centralManager retrievePeripheralsWithIdentifiers:@[uuid]];
        for (int i = 0; i<[array count]; i++)
        {
            CBPeripheral *reconnectPeriPheral = array[i];
            
            NSLog(@"+>>>>>>%ld",(long)reconnectPeriPheral.state);
            switch (reconnectPeriPheral.state)
            {
                case CBPeripheralStateDisconnected:
                case CBPeripheralStateConnecting:
                {
                    [self connectSelectPeripheral:reconnectPeriPheral];
                }
                break;
                case CBPeripheralStateConnected:
                {
                    
                }
                break;
                case CBPeripheralStateDisconnecting:
                {
                    [self cancelConnectPeripheral:reconnectPeriPheral];
                    [self connectSelectPeripheral:reconnectPeriPheral];
                }
                break;
                
                default:
                break;
            }
            
        }
    }
    else
    {
        ///从来未连接过
        [[NSNotificationCenter defaultCenter] postNotificationName:BLE_CURRENT_STATE object:@(BLE_NEVER_CONNECT)];
    }
}

/*!
 *  手动(人为的)断开当前连接的设备
 */

- (void)disconnectCurrentPeripheral:(BOOL)hasRecord
{
    NSLog(@"+>>>>>>APP主动断开蓝牙");
    
    if (self.m_peripheral != nil)
    {
        [self cancelConnectPeripheral:self.m_peripheral];
        _m_peripheral = nil;
        if(!hasRecord)
        {
            //删除连接记录
            [self saveandRemoveReconnectIdentifier:NO];
        }
        
    }
    
}
/*!
 * 手动(人为建立连接)重新连接
 */
-(void)restoreConnectBandByHand
{
    
    [self connectedBand];
}

/*!
 *  持久化保存或者清除连接标志以及手环对应的MAC地址
 *
 *
 */

- (void)saveandRemoveReconnectIdentifier:(BOOL)isSave
{
    if(isSave)
    {
        //保存连接记录
        [[NSUserDefaults standardUserDefaults] setObject:[self.m_peripheral.identifier UUIDString] forKey:BLEConnectedPeripheralUUID];
        //保存mac点赞
        NSString *tmpMac = [[NSUserDefaults standardUserDefaults] objectForKey:BLEBANDMACADDRESSTEMP];
        if ([tmpMac length]>0)
        {
            
            NSLog(@"%@",tmpMac);
            
            [[NSUserDefaults standardUserDefaults] setObject:[tmpMac uppercaseString] forKey:BLEBANDMACADDRESS];
        }
    }
    else
    {
        
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:BLEConnectedPeripheralUUID];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:BLEBANDMACADDRESS];
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
    
}

#pragma mark - CBCentralManager delegate

/*!
 *  判断当前central设备当前蓝牙的状态，你关闭或开启系统蓝牙时候调用
 *  仅仅在CBCentralManagerStatePoweredOn的时候可用当central的状态是OFF的时候所有与中心连接的peripheral都将无效并且都要重新连接，central的初始状态时是Unknown
 *  @param central 当前的设备
 */
- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    
    switch (central.state)
    {
        case CBManagerStatePoweredOff:
        {
            NSLog(@"系统蓝牙关闭CBCentralManagerStatePoweredOff");
            
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:SYSTERM_BLUETOOTH_STATE];
            [[NSUserDefaults standardUserDefaults] synchronize];

            //断开连接的操作
            [self performSelectorOnMainThread:@selector(setStateNotConnected:) withObject:self.m_peripheral waitUntilDone:NO];
            
            ///蓝牙关闭，通知蓝牙状态
            [[NSNotificationCenter defaultCenter] postNotificationName:BLE_CURRENT_STATE object:@(BLE_SYSTEM_CLOSE)];
            
            [self cancelConnectPeripheral:self.m_peripheral];
            
        }
        break;
        case CBManagerStatePoweredOn:
        {
            
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SYSTERM_BLUETOOTH_STATE];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            ///蓝牙开启，通知蓝牙状态
            [[NSNotificationCenter defaultCenter] postNotificationName:BLE_CURRENT_STATE object:@(BLE_SYSTEM_OPEN)];
            
            //重连
            [self connectedBand];
            
        }
        
        break;
        case CBManagerStateResetting:
        break;
        case CBManagerStateUnknown:
        break;
        case CBManagerStateUnsupported:
        break;
        default:
        break;
    }
    NSLog(@"Central manager did update state: %d", (int) central.state);
}

/*!
 *  连接过的设备，将要恢复连接
 *  app状态的保存或者恢复，这是第一个被调用的方法；当APP进入后台去完成一些蓝牙有关的工作设置时，使用这个方法通过蓝牙系统同步app状态
 *
 *  @param central 当前设备管理器，提供信息
 *  @param dict    外设当前的状态信息，包含了应用程序关闭时系统保存的central的信息，用dic去恢复central
 */
- (void)centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary *)dict;
{
    if (self.m_peripheral.state != CBPeripheralStateConnected)
    {
        [self connectSelectPeripheral:self.m_peripheral];
        NSLog(@"didConnectedPeripheral:%@",dict);
    }
    else
    {
        [self cancelConnectPeripheral:self.m_peripheral];
        NSLog(@"didDisConnectedPeripheral:%@",dict);
    }
    
    NSLog(@"willRestoreState:%@",dict);
}


/*!
 *  已经恢复连接后的peripherals集合
 *
 *  @param central     当前设备管理器
 *  @param peripherals 连接的外设的集合，表示当前连接central的所有peripherals
 */
- (void) centralManager:(CBCentralManager *)central didRetrieveConnectedPeripherals:(NSArray *)peripherals
{
    for (CBPeripheral *peripheral in peripherals)
    {
        NSLog(@"didRetrieveConnectedPeripheralsNAMe:%@",peripheral.name);
        
        if (![_discoveredTargetsArray containsObject:peripheral])
        {
            [_discoveredTargetsArray addObject:peripheral];
            NSLog(@"didRetrieveConnectedPeripheral:%@",peripheral.name);
        }
    }
}

/*!
 *  搜索周边的BTLE外设
 *
 *  @param central           当前设备管理器
 *  @param peripheral        正在处于广播状态的外设
 *  @param advertisementData 外设广播的内容
 *  @param RSSI              外设的RSSI值及信号值
 */
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    NSLog(@"+>------>>>>>>>>%@",advertisementData);
    
    NSString *deviceName = peripheral.name;///设备名称
    
    NSString *address = @"";
    
    //如果设置了名字过滤，并且名字不匹配，直接返回
    if(self.bandAdvertisName.length>0&&![deviceName isEqualToString:self.bandAdvertisName])
        return;
    
    if (![_discoveredTargetsArray containsObject:peripheral])///已搜索到的的设备没有在数组中，则添加
    {
        [_discoveredTargetsArray addObject:peripheral];
        
        NSString *key = [NSString stringWithFormat:@"%@", peripheral.identifier.UUIDString];
        NSNumber *newRSSI = [NSNumber numberWithFloat:RSSI.intValue];
        if (![[self.discoveredTargetsRSSI allKeys] containsObject:key])
        {
            [self.discoveredTargetsRSSI setValue:newRSSI forKey:key];
        }
        
        if (![[self.discoveredDevMacDic allKeys] containsObject:key])
        {
            
            if(self.gainMacAddress)
            {
                address = self.gainMacAddress(advertisementData);
                NSLog(@"%@'s address = %@",deviceName,address);
                
                [self.discoveredDevMacDic setObject:address forKey:key];
            }
            
        }
        
    }
    
    ///实时的反馈搜索到的BLE外设以及对应的rssi字典
    if (self.realTimeUpdateDeviceListBlock)
    {
        
        self.realTimeUpdateDeviceListBlock(
                                           [self rankArray:_discoveredTargetsArray WithRssiDic:_discoveredTargetsRSSI],
                                           _discoveredTargetsRSSI,
                                           _discoveredDevMacDic);
        
    }
    
    
}



/*!
 *  连接成功Peripheral后回调,这儿知识代表蓝牙链路打通了，但是私有通道没有打通
 *
 *  @param central    当前的设备管理器
 *  @param peripheral 需要连接的外设
 */
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    
    self.m_peripheral = peripheral;
    
    [self stopScanDevice];
    
    ///开始搜索对应的服务
    [self startDiscoveryPeripheral:self.m_peripheral];
    
}


/*!
 *  发起连接失败之后回调，连接失败后，不知道系统是配置多久没连接上才是失败(我没发现这个方法有调用)，我在上面加上了连接超时，超时后，我主动调用失败的处理
 *
 *  @param central    发起连接的设备管理器
 *  @param peripheral 连接失败的外设
 *  @param error      失败的原因
 */
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    [self performSelectorOnMainThread:@selector(setStateNotConnected:) withObject:peripheral waitUntilDone:NO];
    
    NSString *tip = [NSString stringWithFormat:@"APP向外设发起连接失败%s error = %@",__FUNCTION__,error];
    NSLog(@"BleOperatorManager--%@", tip);
}
/*!
 *  断开连接回调，手动断开连接也是调用这里
 *
 *  @param central    断开连接的设备管理器
 *  @param peripheral 断开连接的外设
 *  @param error      断开连接的原因
 */
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSString *tip = [NSString stringWithFormat:@"APP与外设失去连接%s error = %@",__FUNCTION__,error];
    NSLog(@"BleOperatorManager--%@", tip);
    if (error)
    {
        NSLog(@"didDisconnectPeripheral %@: %@", peripheral.name, error);
    }
    
    [self performSelectorOnMainThread:@selector(setStateNotConnected:) withObject:self.m_peripheral waitUntilDone:NO];
    
    if (peripheral.state != CBPeripheralStateConnected)
    {
        [self connectedBand]; //重连接
    }
    
    
}



/*!
 *  断开连接之后做的处理
 */
-(void)setStateNotConnected:(CBPeripheral *)peripheral
{
    
    //持久化连接状态
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:BLECONNECTSTATE];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    ///连接断开，通知
    [[NSNotificationCenter defaultCenter] postNotificationName:BLE_CURRENT_STATE object:@(BLE_CONNECT_FAIL)];
    
    NSString *tip = [NSString stringWithFormat:@"断开连接之后做的处理%s",__FUNCTION__];
    NSLog(@"%@",tip);
    
    //连接超时取消
    if(connectTimer)
    {
        [connectTimer invalidate];
        connectTimer = nil;
    }
}

/*!
 *  连接成功之后做的处理
 *
 *  @param peripheral 连接设备的名称
 */
-(void)setStateInMainThreadOperate:(CBPeripheral *)peripheral
{
    
    //持久化连接状态
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:BLECONNECTSTATE];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    //持久化mac地址
    [self saveandRemoveReconnectIdentifier:YES];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:BLE_CURRENT_STATE object:@(BLE_CONNECT_SUCCESS)];
    
    NSLog(@"+>>>>>>>蓝牙连接成功");
    
    if(connectTimer)
    {
        [connectTimer invalidate];
        connectTimer = nil;
    }
    
}


/*!
 *  对于要连接的外设进行二次握手
 *
 *  @param peripheral 需要二次握手的外设
 */
-(void)startDiscoveryPeripheral:(CBPeripheral *)peripheral
{
    
    _peripheralServiceCharaDic = [NSMutableDictionary new];
    self.m_peripheral.delegate = self;
    //发现外设的所有服务
    [self.m_peripheral discoverServices:nil];
}

/*!
 *  发送数据
 *
 *  @param data               需要发送的数据
 *  @param serviceUUID        对应的serviceUUID
 *  @param characteristicUUID 对应特性的UUID
 *  @param writeType          发送数据是否带响应
 */
-(void)sendDataToBand:(NSData *)data WithServiceUUID:(NSString *)serviceUUID WithCharacteristicUUID:(NSString *)characteristicUUID withWriteType:(CBCharacteristicWriteType)writeType
{
    serviceUUID = [self UUIDString:serviceUUID];
    characteristicUUID = [self UUIDString:characteristicUUID];
    
    if ([[_peripheralServiceCharaDic allKeys] containsObject:serviceUUID])
    {
        NSDictionary *charaDic = [_peripheralServiceCharaDic objectForKey:serviceUUID];
        if ([[charaDic allKeys] containsObject:characteristicUUID])
        {
            
            CBCharacteristic *character = [charaDic objectForKey:characteristicUUID];
            
            [ self.m_peripheral writeValue:data forCharacteristic:character type:writeType];
            
            NSLog(@"write data = %@",data);
        }
    }
}

/*!
 *  设置通知使能
 *
 *  @param isEnable           使能开关
 *  @param serviceUUID        服务的UUID
 *  @param characteristicUUID 特性的UUID
 */
- (void)setNotifyEnableWith:(BOOL)isEnable WithServiceUUID:(NSString *)serviceUUID WithCharacteristicUUID:(NSString *)characteristicUUID
{
    serviceUUID = [self UUIDString:serviceUUID];
    characteristicUUID = [self UUIDString:characteristicUUID];
    if ([[_peripheralServiceCharaDic allKeys] containsObject:serviceUUID])
    {
        NSDictionary *charaDic = [_peripheralServiceCharaDic objectForKey:serviceUUID];
        
        if ([[charaDic allKeys] containsObject:characteristicUUID])
        {

            CBCharacteristic *character = [charaDic objectForKey:characteristicUUID];
            
            [self.m_peripheral setNotifyValue:isEnable forCharacteristic:character];
        }
    }
}

/*!
 *  APP主动读取数据
 *
 *  @param serviceUUID        服务的UUID
 *  @param characteristicUUID 特性的UUID
 */
- (void)readDataFromBand:(NSString *)serviceUUID WithCharacteristicUUID:(NSString *)characteristicUUID
{
    serviceUUID = [self UUIDString:serviceUUID];
    characteristicUUID = [self UUIDString:characteristicUUID];
    if ([[_peripheralServiceCharaDic allKeys] containsObject:serviceUUID])
    {
        NSDictionary *charaDic = [_peripheralServiceCharaDic objectForKey:serviceUUID];
        if ([[charaDic allKeys] containsObject:characteristicUUID])
        {
            CBCharacteristic *character = [charaDic objectForKey:characteristicUUID];
            
            [self.m_peripheral readValueForCharacteristic:character];
        }
    }
    
    
}

/*!
 *  握手回调，判定是不是当前蓝牙管理器需要的服务，从这里开始最关键
 *
 *  @param peripheral 已经连接的外设
 *  @param error      错误描述
 */
-(void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    
    if (error)
    {
        NSLog(@"didDiscoverServices failed: %@", error);
        return;
    }
    for (CBService *service in peripheral.services)
    {
        NSLog(@"发现设备的服务--%@", service.UUID.UUIDString);
//        if ([[_bleServiceAndCharater allKeys] containsObject:service.UUID.UUIDString])
//        {
//            [self.m_peripheral discoverCharacteristics:[_bleServiceAndCharater objectForKey:service.UUID.UUIDString] forService:service];
//        }
        //找服务对应的所有特质
        [self.m_peripheral discoverCharacteristics:nil forService:service];
        
    }
    
    //连接成功后的处理
    dispatch_async(dispatch_get_main_queue(), ^{
        
        //保证短时间内不会重复调用
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(setStateInMainThreadOperate:) object:self.m_peripheral];
        
        [self performSelector:@selector(setStateInMainThreadOperate:) withObject:self.m_peripheral afterDelay:1];
    });
    
}

/*!
 *  握手回调，判定当前连接的设备，读写特性是否符合
 *
 *  @param peripheral 连接的外设
 *  @param service    符合当前连接的外设的服务
 *  @param error      错误描述
 */
-(void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    if (error)
    {
        NSLog(@"didDiscoverCharacteristics failed: %@", error);
        return;
    }
    
    NSLog(@"didDiscoverCharacteristics succeeded.");
    
    NSMutableDictionary *characterDic = [NSMutableDictionary new];
    
    for (CBCharacteristic *characteristic in service.characteristics)
    {
        NSLog(@"~~characteristic.UUID~~~%@",characteristic.UUID);
        //如果是notify的特质，就设置使能
        if (characteristic.properties == CBCharacteristicPropertyNotify)
        {
//            NSLog(@"read characteristic.UUID~~~%@",characteristic.UUID);
            [self.m_peripheral setNotifyValue:YES forCharacteristic:characteristic];
        }
        [characterDic setObject:characteristic forKey:characteristic.UUID.UUIDString];
        
    }
    
    [_peripheralServiceCharaDic setValue:characterDic forKey:service.UUID.UUIDString];
    
}
/*!
 *  当前设备发送数据到蓝牙设备后回调，前提是发送是带回应的
 *
 *  @param peripheral     当前连接的设备
 *  @param characteristic 发送数据的特性参数
 *  @param error          错误描述
 */
- (void) peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    
    if (error)
    {
        
        NSString *tip = [NSString stringWithFormat:@"error in writing characteristic %@ and error %@",characteristic.UUID,[error localizedDescription]];
        NSLog(@"发送数据错误后回调--%@", tip);
        
    }
    else
    {
        
        NSString *tip = [NSString stringWithFormat:@"didWriteValueForCharacteristic %@ and value %@",characteristic.UUID,characteristic.value];
        NSLog(@"发送数据成功后回调--%@", tip);
    }
    
    if (self.delegate != nil &&[(NSObject *)self.delegate respondsToSelector:@selector(didWriteDataFromBand:WithServiceUUID:)])
    {
        
        [self.delegate didWriteDataFromBand:characteristic.value WithServiceUUID:characteristic.service.UUID.UUIDString];
    }
}

/*!
 *  当前设备接收到蓝牙设备的数据后回调
 *
 *  @param peripheral     连接的外设
 *  @param characteristic 接收数据的特性参数
 *  @param error          错误描述
 */
- (void) peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    
    NSLog(@"didUpdateValueForCharacteristic");
    
    if (self.delegate != nil &&[(NSObject *)self.delegate respondsToSelector:@selector(didReceiveDataFromBand:WithServiceUUID:)])
    {
        [self.delegate didReceiveDataFromBand:characteristic.value WithServiceUUID:characteristic.service.UUID.UUIDString];
    }
    
}

#pragma mark  -- private method -- 私有方法

/*!
 *  对搜索到的BLE设备进行升序排列。
 *
 *  @param array   需要升序排列的数组
 *  @param rssiDic 升序数组对应的RSSI的字典
 *
 *  @return 返回排序好的设备数组
 */
- (NSArray *)rankArray:(NSArray *)array WithRssiDic:(NSDictionary *)rssiDic
{
    NSMutableArray *mutableArray = [[NSMutableArray alloc]initWithCapacity:100];
    if (array.count>0 && array.count<100)
    {
        [mutableArray addObjectsFromArray:array];
        
        for (int i=0; i<[mutableArray count]; i++) {
            CBPeripheral *p = [mutableArray objectAtIndex:i];
            
            for (int j =i+1; j<[mutableArray count]; j++)
            {
                CBPeripheral *nextP = [mutableArray objectAtIndex:j];
                if ([[rssiDic objectForKey:[NSString stringWithFormat:@"%@", p.identifier.UUIDString]] intValue] < [[rssiDic objectForKey:[NSString stringWithFormat:@"%@", nextP.identifier.UUIDString]] intValue])
                {
                    [mutableArray exchangeObjectAtIndex:i withObjectAtIndex:j];
                    p = nextP;
                }
                
            }
        }
    }
    return mutableArray;
}

@end
