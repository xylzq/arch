## v2ray教程



### - linux 版本

#### 1.安装qv2ray
```
pacman -S qv2ray
```

#### 2.下载v2ray核心（github）
```
https://github.com/v2fly/v2ray-core
```

#### 3.将核心解压并复制到指定文件夹
```
~/qv2ray/3384/.config/qv2ray/vcore/
```

#### 4.配置qv2ray
```
打开qv2ray - 点击preference（首选项）- 点击kernel setting（内核设置）
V2Ray Core Executable Path(V2Ray 核心可执行文件路径): /home/primary/qv2ray/3384/.config/qv2ray/vcore/v2ray
V2Ray Assets Directory    (V2Ray 资源目录)         : /home/primary/qv2ray/3384/.config/qv2ray/vcore/
Check V2Ray Core Setting(检查v2ray核心设置) - Check System Date and Time from the internet(联网对时)
```

#### 5.添加订阅
```
点击 Group（分组）- 更改Group name（分组名称） - 点击 subscription  Setting（订阅设置）- 
复制订阅地址，订阅类型改为 Builtin Subscription Support:Basic Base64 - 点击Update Subscription（更新订阅）
```


### - windowns 版本

#### 1.下载V2RayN（github）
```
https://github.com/2dust/v2rayN（新版本不好用，最好下载3.27版本）
```

#### 2.使用V2RayN
```
解压 - 右键单击v2rayN.exe文件名，选择《以管理员身份运行》- 点击桌面右下任务栏托盘找到V2RayN 图标 - 点击订阅，选择订阅设置 - 
复制的订阅链接，然后点击确定 - 点击更新订阅，获得服务器地址 - 点击Http代理模式，选择代理模式，选择【开启PAC，并自动配置PAC（PAC模式）】
```

#### 3.注意事项
```
1、如果提示 “PAC启动失败,请使用管理员模式打开” 错误提示 ，则说明你没有安装依赖 Microsoft .NET Framework 4.6或者更高的版本。
2、如果连接后，无法成功访问Google,请先检查电脑时间是否与网络自动同步，时间误差30秒以上，就无法成功连接 V2ray - V2rayN 并不会主动更新订阅服务器，所以要经常更新订阅。
3、如果要将V2rayN 的图标放到桌面快捷方式，一定要右键点击V2rayN 的图标，选择《发送到桌面快捷方式》，而不能直接拷贝V2rayN.exe到桌面，这样会导致V2rayN无法正常工作
```

### - android 版本

#### 1.下载V2RayNG（github）
```
https://github.com/2dust/v2rayNG
```

#### 2.使用V2RayNG
```
手机安装后打开V2RayNG，点击右上角菜单按钮 - 点击订阅设置 - 
订阅设置界面，点击右上角“ +”号 - 填写注释名称，插入第三步复制的订阅地址，然后依次右上角“勾号”保存 - 
返回首页，点击右上角“ …”图标 - 选择更新订阅 - 选择服务器后，点击右下角图标，启动连接
```
