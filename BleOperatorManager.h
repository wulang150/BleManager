/*
	@haeder BleOperatorManager.h

	@abstract 关于这个源代码文件的一些基本描述
*/


#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

/*
 @abstract 接收数据的代理方法
 */
@protocol BleDataAdaptDelegate<NSObject>

/*
 接收数据的代理方法
 
 @param data 已经接收到的数据
 @param serviceUUID 接受到的数据对应的UUID
 */
-(void)didReceiveDataFromBand:(NSData *)data WithServiceUUID:(NSString *)serviceUUID;

/*
 发送数据的代理方法
 
 @param data 已经接收到的数据
 @param serviceUUID 接受到的数据对应的UUID
 */
-(void)didWriteDataFromBand:(NSData *)data WithServiceUUID:(NSString *)serviceUUID;
@end

/**
 蓝牙连接以及数据收发基类
 */
@interface BleOperatorManager : NSObject
{

}

/**
 接收数据的代理
 */
@property (nonatomic,strong)id<BleDataAdaptDelegate>delegate;

/*!
 *  实时连接的peripheral对象，连接上的那个外设，不需要设置
 */
@property (nonatomic, strong)CBPeripheral *m_peripheral;

/*
 *  正常模式下传入以service为key-character数组为Value的字典
 */
//@property (nonatomic, strong)NSDictionary *bleServiceAndCharater;


/*
 是否需要自动重连，默认是开启自动连接的（非主动调用断连接口，都会自动重新连接）
 */
@property (nonatomic)BOOL isAutoConnected;      //默认为YES

/*
 * 需要搜搜的对应的设备的名字,若需要搜索所有设备，可不进行赋值
 */
@property (nonatomic, copy)NSString *bandAdvertisName;

/*
 实时的反馈搜索到的周边的BLE外设
 modify by aney 17/6/18
 */
@property (nonatomic, strong) void (^realTimeUpdateDeviceListBlock)(NSArray *listArray,NSDictionary *rssiDic,NSDictionary *macDic);

//对于地址的解析，每个蓝牙外设可能都不一样，让使用者解析返回给我们
@property (nonatomic, strong) NSString *(^gainMacAddress)(NSDictionary *advertisementData);
/*
 创建单例
 
 @return 返回创建的对象
 */
+ (BleOperatorManager *)sharedInstance;


/*!
 开始搜索外围设备，首先会检索系统蓝牙有没有该UUID对应的蓝牙外设正在连接，若有则直接连接，如果没有才会进行搜索设备
 
 @param adverUUIDArray 需要搜索的广播包中包含的UUID，传nil就是搜索所有
 */
-(void)startScanDevice:(NSArray *)adverUUIDArray;
/*
 *  停止搜索外围设备
 */
-(void)stopScanDevice;
/*
 *  连接选择的外围设备
 *  @param peripheral 指定的外围设备
 */
-(void)connectSelectPeripheral:(CBPeripheral *)peripheral;

/*
 *  手动(人为的)断开当前连接的设备
 *  hasRecord：是否保存连接记录，关于是否可以自动重连的
 *
 */
-(void)disconnectCurrentPeripheral:(BOOL)hasRecord;

/*
 * 重新连接，如果有连接记录，会重新连接上
 */
-(void)restoreConnectBandByHand;


/****************************数据层处理************************************/


/*
 *  发送数据
 * modify by aney 16/8/18
 *  @param data               需要发送的数据
 *  @param serviceUUID        对应的serviceUUID
 *  @param characteristicUUID 对应特性的UUID
 *  @param writeType          发送数据是否带响应
 */
-(void)sendDataToBand:(NSData *)data WithServiceUUID:(NSString *)serviceUUID WithCharacteristicUUID:(NSString *)characteristicUUID withWriteType:(CBCharacteristicWriteType)writeType;
/*
 *  设置通知使能
 * modify by aney 16/8/18
 *  @param isEnable           使能开关
 *  @param serviceUUID        服务的UUID
 *  @param characteristicUUID 特性的UUID
 */
- (void)setNotifyEnableWith:(BOOL)isEnable WithServiceUUID:(NSString *)serviceUUID WithCharacteristicUUID:(NSString *)characteristicUUID;
/*
 *  APP主动读取数据
 * modify by aney 16/8/18
 *  @param serviceUUID        服务的UUID
 *  @param characteristicUUID 特性的UUID
 */
- (void)readDataFromBand:(NSString *)serviceUUID WithCharacteristicUUID:(NSString *)characteristicUUID;

@end

