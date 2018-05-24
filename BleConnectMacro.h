//
//  BleConnectMacro.h
//  FDCes
//

#ifndef BleConnectMacro_h
#define BleConnectMacro_h

//通知的标志位
typedef NS_ENUM(NSUInteger, BLE_STATE_TYPE) {
    BLE_SYSTEM_OPEN = 100,  //系统蓝牙打开
    BLE_SYSTEM_CLOSE,       //系统蓝牙关闭
    BLE_CONNECT_SUCCESS,    //连接成功
    BLE_CONNECT_FAIL,       //连接断开
    BLE_CONNECTING,         //正在连接中
    BLE_NEVER_CONNECT,      //从未连接过
};

/**
 *  蓝牙当前的状态,配合BLE_STATE_TYPE使用,这样可以避免建立太多的通知（通知）
 */
#define BLE_CURRENT_STATE               @"BLE_CURRENT_STATE"

/**
 *  持久化蓝牙系统开关状态
 */
#define SYSTERM_BLUETOOTH_STATE          @"bluetoothOpenState"


/**
 *  用于持久化已连接设备生成的UUID，是唯一的
 */
#define BLEConnectedPeripheralUUID       @"BLEConnectedPeripheralUUID"

/**
 *  连接状态
 */
#define BLECONNECTSTATE                  @"BLECONNECTSTATE"

/**
 * 持久化BLE外设的MAC地址
 */
#define BLEBANDMACADDRESS                @"BleBandMacAddress"

/**
 * 临时持久化BLE外设的MAC地址
 */
#define BLEBANDMACADDRESSTEMP           @"BleBandMacAddressTemp"

/**
 * 持久化连接的外设的名字以此来区分功能
 */
#define PERIPHERALNAME                   @"PeripheralName"

#define TEMP_PERIPHERALNAME              @"Temp_PeripheralName"


#endif /* BleConnectMacro_h */
