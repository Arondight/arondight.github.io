title: 为 LibVirt 添加新的 API
date: 2016-12-25 19:05:20
categories: [ 技术 ]
tags: [ C, LibVirt, Linux, QEMU ]

---

[LibVirt](http://libvirt.org) 是一套用于控制虚拟化的 API，除了提供了一套无关具体虚拟化细节的 API 之外，还提供了一个 daemon（`libvirtd`) 和一个控制台工具（`virsh`）。本文演示了如何在 LibVirt 中新加一个 API，并且在 `libvirtd` 和 `virsh` 中使用新的 API 完成新的功能。

为了方便说明，在文章的示例中只演示了添加一个 API，如果要看完整的示例，可以查看项目[Arondight/libvirt-add-new-api-demo](https://github.com/Arondight/libvirt-add-new-api-demo)，这是一个相对完整的示例，项目中新 API 的说明以及 Patch 的使用可以参见其中的 `README.txt`。

<div class="github-widget" data-repo="Arondight/libvirt-add-new-api-demo"></div>

<!-- more -->

## 构建开发环境

首先你需要有一套可以编译的 LibVirt 源码，在本文的示例中我们使用了 `v2.5.0` 版本的源码，你可以通过以下指令来得到它。

```bash
git clone https://github.com/libvirt/libvirt.git
pushd libvirt && git checkout v2.5.0 && popd
```

LibVirt 的编译需要[Gnulib](http://www.gnu.org/software/gnulib) 的源码，不过因为网络的原因在墙内其 Git 仓库很难获取，所以这里使用 GitHub 上的镜像仓库，并通过环境变量引入。你可以设置好这一切并编译一遍源码。在上面的指令执行成功后执行。

```bash
git clone https://github.com/coreutils/gnulib.git
export GNULIB_SRCDIR=$(readlink -f ./gnulib)
cd ./libvirt
./autogen.sh
make -j8
make check -j8
```

如果你的编译依赖完备的话，LibVirt 可以正确编译并通过测试。如果你没有得到预期的结果，请检查你的编译环境并安装缺失的软件包。

示例中我们添加的 API 为 `virConnectGetMagicFileContent`，功能为获取运行虚拟化的机器上某个文件内容的最多前 32 个字节。

## 添加公共 API

首先要做的是为 LibVirt 添加公共 API，这个 API 也是 LibVirt 为用户展现的 API。此后通过一连串调用，我们会在 `libvirtd` 和 `virsh` 中通过调用这个公共 API 来完成新功能。这里需要修改的文件有如下几个。

1. `include/libvirt/libvirt-*.h`: 这里需要完成公共 API 的声明，此后通过包含头文件 `include/libvirt/libvirt.h` 可调用此 API。
2. `src/libvirt_public.syms`: 这里需要将新 API 导出为全局符号，这样公共 API 得以允许被其他函数访问，如果你在步骤 `[1]` 中定义了一个需要被其他函数访问的数据结构，同样你也需要将它导出为全局符号。
3. `src/libvirt-*.c`: 这里需要实现步骤 `[1]` 中声明的 API，一般来说这里只调用驱动提供的 API 即可，具体功能需要在每个 hypervisor 的驱动中单独实现。

### API 的注释

首先要说明的是，公共 API 必须要有合乎规范的注释。在编译时，`docs/apibuild.py` 会检查宏和公共 API 的注释是否符合要求，如果发现不合格的注释，将中断整个编译过程。注释在声明和定义处皆可。

对于一个宏，注释的格式如下。

```c
/**
 * MACRO_NAME:
 *
 * macro's comment.
 */
#define MACRO_NAME (SOMETHING_HERE)
```

对于一个 API，注释的格式如下。

```c
/**
 * apiName:
 *
 * @arg: arg's comment
 *
 * synopsis for this api.
 *
 * Returns what.
 */
ret_type
apiName(arg_type arg) { }
```

> 注意：API 注释中的单词 `Returns` 标明了这是返回值的注释，不能随意修改。

### 声明公共 API

目录 `include/libvirt` 下有众多以 `libvirt-` 开头的头文件，公共 API 分散在其中。因为新的 API 返回在运行虚拟化的主机上某个文件的某段内容，所以我们在头文件 `include/libvirt/libvirt-host.h` 声明这个 API。

```patch
diff --git a/include/libvirt/libvirt-host.h b/include/libvirt/libvirt-host.h
index 07b5d1594..72db263d2 100644
--- a/include/libvirt/libvirt-host.h
+++ b/include/libvirt/libvirt-host.h
@@ -686,5 +686,27 @@ int virNodeAllocPages(virConnectPtr conn,
                       unsigned int cellCount,
                       unsigned int flags);

+/**
+ * VIR_CONNECT_MAGIC_FILE_PATH:
+ *
+ * This is the absolute path of file.
+ */
+#define VIR_CONNECT_MAGIC_FILE_PATH ("/var/run/libvirt/magic_file")
+
+/**
+ * VIR_CONNECT_MAGIC_FILE_FORBIDDEN_STR:
+ *
+ * If file's content match this, qemu driver will refused to boot VM
+ */
+#define VIR_CONNECT_MAGIC_FILE_FORBIDDEN_STR ("0xabadcafe")
+
+/**
+ * VIR_CONNECT_MAGIC_FILE_CONTENT_LEN:
+ *
+ * Max length of file.
+ */
+#define VIR_CONNECT_MAGIC_FILE_CONTENT_LEN (32)
+
+char *virConnectGetMagicFileContent(virConnectPtr conn);

 #endif /* __VIR_LIBVIRT_HOST_H__ */
```

这个 Patch 做的事情非常简单：定义了三个以后会用到的宏，并且声明了公共 API。因为这个功能需要访问远程主机上的文件，所以公共 API 需要一个参数 `virConnectPtr`，通过这个指针我们可以调用具体的 remote 或 hypervisor 驱动（前者用于远程调用，后者是真正操纵虚拟化的驱动，例如 QEMU 驱动）。

除了这个文件以外，还需要将公共 API 在 `src/libvirt_public.syms` 中导出。

```patch
diff --git a/src/libvirt_public.syms b/src/libvirt_public.syms
index e01604cad..4db27dc2b 100644
--- a/src/libvirt_public.syms
+++ b/src/libvirt_public.syms
@@ -746,4 +746,9 @@ LIBVIRT_2.2.0 {
         virConnectNodeDeviceEventDeregisterAny;
 } LIBVIRT_2.0.0;

+LIBVIRT_2.5.0 {
+    global:
+        virConnectGetMagicFileContent;
+} LIBVIRT_2.2.0;
+
 # .... define new API here using predicted next version number ....
```

完成这一步工作之后，新的公共 API 就可以被其他的函数所调用。

### 实现公共 API

对应头文件 `include/libvirt/libvirt-host.h`，我们需要在文件 `src/libvirt-host.c` 中实现新 API。

```patch
diff --git a/src/libvirt-host.c b/src/libvirt-host.c
index 335798abf..0b8b41ca9 100644
--- a/src/libvirt-host.c
+++ b/src/libvirt-host.c
@@ -1482,3 +1482,36 @@ virNodeAllocPages(virConnectPtr conn,
     virDispatchError(conn);
     return -1;
 }
+
+
+/**
+ * virConnectGetMagicFileContent:
+ *
+ * @conn: virConnect connection
+ *
+ * Get content of magic file, max length is VIR_CONNECT_MAGIC_FILE_CONTENT_LEN.
+ *
+ * Returns content of file if all succeed or NULL upon any failure.
+ */
+char *
+virConnectGetMagicFileContent(virConnectPtr conn)
+{
+    VIR_DEBUG("conn=%p", conn);
+
+    virResetLastError();
+
+    virCheckConnectReturn(conn, NULL);
+
+    if (conn->driver->connectGetMagicFileContent) {
+        char *ret = conn->driver->connectGetMagicFileContent(conn);
+        if (!ret)
+            goto error;
+        return ret;
+    }
+
+    virReportUnsupportedError();
+
+ error:
+    virDispatchError(conn);
+    return NULL;
+}
```

在这个 Patch 里我们虽然实现了公共 API，但是没有在其中做具体的操作，而是根据参数 `conn` 调用了驱动 `connectGetMagicFileContent`，具体的工作将由该驱动完成。现在我们无法直接判断该驱动是一个 reomte 驱动还是 hypervisor 驱动，通常来说如果你正在使用一个运行 `libvirtd` 的远程主机，那么此处将是一个 remote 驱动，否则将会直接调用 hypervisor 驱动。

> 到现在为止，假设我们使用 `virsh get-magic` 在标准输出上打印出文件的内容时，函数的调用链如下（假设直接调用 hypervisor 驱动）。以后每一部分的工作结束后，我们都将重新整理这个调用链以方便理清我们都做了什么。
>
> ??? -> `virConnectGetMagicFileContent`@LibVirt -> `connectGetMagicFileContent`@hypervisor -> ???

## 实现 hypervisor 驱动

LibVirt 可用的 hypervisor 有很多，这里我们只为最常用的 QEMU 编写驱动。

### 添加内部驱动 API

因为 LibVirt 在用户层面上提供了统一的 API，而这个公共 API 调用了一个确定的驱动 API。因此我们需要在 `src/driver-hypervisor.h` 中确定这个 API 以提供给公共 API 调用。后面我们会用到几个结构体变量将这个统一的驱动 API 和具体的 hypervisor 驱动函数关联起来，然后在 hypervisor 驱动中具体的实现它，从而提供无关虚拟化细节的 API。

```patch
diff --git a/src/driver-hypervisor.h b/src/driver-hypervisor.h
index 51af73200..78de6b04a 100644
--- a/src/driver-hypervisor.h
+++ b/src/driver-hypervisor.h
@@ -1251,6 +1251,9 @@ typedef int
                              int state,
                              unsigned int flags);

+typedef char *
+(*virDrvConnectGetMagicFileContent)(virConnectPtr conn);
+
 typedef struct _virHypervisorDriver virHypervisorDriver;
 typedef virHypervisorDriver *virHypervisorDriverPtr;

@@ -1489,6 +1492,7 @@ struct _virHypervisorDriver {
     virDrvDomainMigrateStartPostCopy domainMigrateStartPostCopy;
     virDrvDomainGetGuestVcpus domainGetGuestVcpus;
     virDrvDomainSetGuestVcpus domainSetGuestVcpus;
+    virDrvConnectGetMagicFileContent connectGetMagicFileContent;
 };


```

这里我们声明了一个 `virDrvConnectGetMagicFileContent` 类型的函数指针变量，并添加到了结构体类型 `_virHypervisorDriver` 的声明当中，下面在 QEMU 驱动中我们会将这个函数指针指向具体的驱动函数。从而完成 LibVirt API 到 QEMU 驱动函数的调用。

### 添加 hypervisor 公共 API

现在我们只需实现 QEMU 的驱动函数，并在结构体变量 `qemuHypervisorDriver` 中用新的驱动函数为上一节新加的函数指针赋值即可。这样虽然各个 hypervisor 的驱动细节各不相同，但是在 LibVirt 上却表现为一致的接口，从而为用于隐藏了具体的虚拟化细节。

注意通常来说驱动具体的功能并不在此实现，而是在 `qemu/qemu_capabilities.h` 中提供一个 QEMU 驱动内可见的 API，并在 `qemu/qemu_capabilities.c` 中通过一系列函数调用完成驱动的具体功能。

```patch
diff --git a/src/qemu/qemu_driver.c b/src/qemu/qemu_driver.c
index 3517aa2be..4e108e96a 100644
--- a/src/qemu/qemu_driver.c
+++ b/src/qemu/qemu_driver.c
@@ -20273,6 +20273,31 @@ qemuDomainSetGuestVcpus(virDomainPtr dom,
 }


+static char *
+qemuConnectGetMagicFileContent(virConnectPtr conn)
+{
+    virQEMUDriverPtr driver = conn->privateData;
+    char *ret = NULL;
+    virCapsPtr caps = NULL;
+
+    if (virConnectGetMagicFileContentEnsureACL (conn) < 0) {
+        return NULL;
+    }
+
+    if (!(caps = virQEMUDriverGetCapabilities(driver, false))) {
+        goto cleanup;
+    }
+
+    if (!(ret = virQEMUCapsGetMagicFileContent(caps))) {
+        goto cleanup;
+    }
+
+ cleanup:
+    virObjectUnref(caps);
+    return ret;
+}
+
+
 static virHypervisorDriver qemuHypervisorDriver = {
     .name = QEMU_DRIVER_NAME,
     .connectOpen = qemuConnectOpen, /* 0.2.0 */
@@ -20486,6 +20511,7 @@ static virHypervisorDriver qemuHypervisorDriver = {
     .domainMigrateStartPostCopy = qemuDomainMigrateStartPostCopy, /* 1.3.3 */
     .domainGetGuestVcpus = qemuDomainGetGuestVcpus, /* 2.0.0 */
     .domainSetGuestVcpus = qemuDomainSetGuestVcpus, /* 2.0.0 */
+    .connectGetMagicFileContent = qemuConnectGetMagicFileContent, /* 2.5.0 */
 };


```

这里用到一个权限检查函数 `virConnectGetMagicFileContentEnsureACL`，目前为止我们还没见过它，而它将在我们编写 remote 驱动时由 `src/rpc/gendispatch.pl` 生成。

### 完成 hypervisor 驱动的功能

现在我们可以在 `src/qemu/qemu_capabilities.c` 中实现 QEMU 驱动具体的功能并在 `src/qemu/qemu_capabilities.c` 中对内部提供一个接口了。这个接口要在 `src/qemu/qemu_capabilities.h` 中声明以便被 QEMU 驱动使用。

```patch
diff --git a/src/qemu/qemu_capabilities.c b/src/qemu/qemu_capabilities.c
index 45ab5bbb6..8bf4efc7b 100644
--- a/src/qemu/qemu_capabilities.c
+++ b/src/qemu/qemu_capabilities.c
@@ -5222,3 +5222,45 @@ virQEMUCapsFillDomainCaps(virCapsPtr caps,
         return -1;
     return 0;
 }
+
+
+char *
+virQEMUCapsGetMagicFileContent(virCapsPtr caps ATTRIBUTE_UNUSED)
+{
+    FILE *fh = NULL;
+    char *content = NULL;
+    char *ret = NULL;
+
+    if (-1 == access(VIR_CONNECT_MAGIC_FILE_PATH, R_OK)) {
+        return NULL;
+    }
+
+    if (!(fh = fopen(VIR_CONNECT_MAGIC_FILE_PATH, "r"))) {
+        virReportSystemError(errno, _("failed to open file %s"),
+                             VIR_CONNECT_MAGIC_FILE_PATH);
+        return NULL;
+    }
+
+    if (VIR_ALLOC_N(content, VIR_CONNECT_MAGIC_FILE_CONTENT_LEN) < 0) {
+        ret = NULL;
+        goto cleanup;
+    }
+
+    memset (content, 0, VIR_CONNECT_MAGIC_FILE_CONTENT_LEN);
+
+    if (!fgets(content, VIR_CONNECT_MAGIC_FILE_CONTENT_LEN, fh)) {
+        virReportSystemError(errno, _("failed to read file %s"),
+                             VIR_CONNECT_MAGIC_FILE_PATH);
+        ret = NULL;
+        goto cleanup;
+    }
+
+    ret = content;
+
+cleanup:
+    if (VIR_FCLOSE (fh) < 0) {
+        virReportSystemError(errno, _("failed to close file %d"), fileno (fh));
+    }
+
+    return ret;
+}
diff --git a/src/qemu/qemu_capabilities.h b/src/qemu/qemu_capabilities.h
index ee4bbb329..4efd31e38 100644
--- a/src/qemu/qemu_capabilities.h
+++ b/src/qemu/qemu_capabilities.h
@@ -525,4 +525,6 @@ int virQEMUCapsFillDomainCaps(virCapsPtr caps,
                               virFirmwarePtr *firmwares,
                               size_t nfirmwares);

+char *virQEMUCapsGetMagicFileContent(virCapsPtr caps);
+
 #endif /* __QEMU_CAPABILITIES_H__*/
```

这一部分结束后，直接实现功能的那一部分代码就已经完成了。

> 现在调用链如下。
>
> ??? -> `virConnectGetMagicFileContent`@LibVirt -> `remoteConnectGetMagicFileContent`@remote -> `qemuConnectGetMagicFileContent`@QEMU -> `virQEMUCapsGetMagicFileContent`@QEMU

## 实现 remote 驱动

remote 协议由两台主机的 LibVirt 交换信息所用，当 LibVirt 连接到远程主机时（例如 `virsh -c`），之前实现的公共 API 中通过 `conn->driver` 结构体变量调用的函数会由 remote 驱动处理。本机的 LibVirt 将会请求远程的 LibVirt 执行公共 API，进而执行远程主机具体的 hypervisor 驱动，然后得到返回的数据。既然有信息交换，就必须定义协议。

协议的定义涉及到几个文件，其中需要手动修改的文件如下。

1. `src/remote/remote_driver.c`: 定义了客户端的 remote 驱动处理函数。
2. `src/remote/remote_protocol.x`: 协议格式。
3. `src/remote_protocol-structs`: 协议格式。

以上文件的前两个会被脚本 `src/rpc/gendispatch.pl` 处理，进而生成以下四个文件。

1. `src/remote/remote_client_bodies.h`: 实现了 remote 驱动客户端 API。
2. `daemon/remote_dispatch.h`: 实现了 remote 驱动服务器端 API。
3. `src/access/viraccessapicheck.h`：声明了 API 权限检查函数。
4. `src/access/viraccessapicheck.c`：实现了 API 权限检查函数。

remote 驱动的函数体就实现在前两个头文件中，客户端的 API 经过一系列 API 调用，最终由函数 `virNetClientProgramCall` 完成信息的交互，其中两个类型为 `void *` 的参数保存了传递给服务器端 remote 驱动的参数和服务器端返回的数据，这两个参数的类型由两个类型为 `xdrproc_t` 的参数确定。

### 实现客户端驱动

在 `src/remote/remote_driver.c` 中，我们只要简单的修改结构体变量 `hypervisor_driver` 即可。

```patch
diff --git a/src/remote/remote_driver.c b/src/remote/remote_driver.c
index 888052045..65afda6fb 100644
--- a/src/remote/remote_driver.c
+++ b/src/remote/remote_driver.c
@@ -8205,6 +8205,7 @@ static virHypervisorDriver hypervisor_driver = {
     .domainMigrateStartPostCopy = remoteDomainMigrateStartPostCopy, /* 1.3.3 */
     .domainGetGuestVcpus = remoteDomainGetGuestVcpus, /* 2.0.0 */
     .domainSetGuestVcpus = remoteDomainSetGuestVcpus, /* 2.0.0 */
+    .connectGetMagicFileContent = remoteConnectGetMagicFileContent, /* 2.5.0 */
 };

 static virNetworkDriver network_driver = {
```

这里我们只是简单的为结构体变量增加了一个元素，这个元素的类型为函数指针 `virDrvConnectGetMagicFileContent`，在定义内部 API 时添加到了类型 `struct _virHypervisorDriver` 的声明当中，值为 `remoteConnectGetMagicFileContent`，这是 `src/rpc/gendispatch.pl` 输出到 `src/remote/remote_client_bodies.h` 中的函数名。

### 定义协议格式

根据之前说的数据交换方式，我们这里需要定义具体的类型给函数 `virNetClientProgramCall` 的两个 `xdrproc_t` 的参数使用。这里针对每个 API 需要定义两个结构体，其名字可以参考其他的结构体和对应的 API。后跟 `_args` 的结构体为 API 的参数，`_ret` 的则为返回值，`virNetClientProgramCall` 会将两个 `void *` 类型的参数分别解释为两个结构体类型，并通过这两个参数完成和远程主机的交互。如果 remote 驱动不需要参数，那么可以省略以 `_args` 结尾的结构体。

假设这里我们定义了如下两个结构体。

```c
struct remote_connect_abadcafe_args {
    remote_nonnull_string str;
};

struct remote_connect_abadcafe_ret {
    int need_results;
};
```

那么它会在文件 `src/remote/remote_client_bodies.h` 中生成类似下面的函数。

```c
static int
remoteConnectAbadcafe(virConnectPtr conn, const char *str) { }
```

除此之外，还需要阅读文件 `src/remote/remote_protocol.x` 第 403-426 行的注释，特别是 `insert@offset` 相关的说明，你可能会需要它们的。

文件 `src/remote/remote_protocol.x` 的 Patch 如下。

```patch
diff --git a/src/remote/remote_protocol.x b/src/remote/remote_protocol.x
index e8382dc51..e5c56220d 100644
--- a/src/remote/remote_protocol.x
+++ b/src/remote/remote_protocol.x
@@ -3341,6 +3341,9 @@ struct remote_domain_set_guest_vcpus_args {
     unsigned int flags;
 };

+struct remote_connect_get_magic_file_content_ret {
+    remote_nonnull_string content;
+};

 /*----- Protocol. -----*/

@@ -5934,5 +5937,12 @@ enum remote_procedure {
      * @generate: both
      * @acl: none
      */
-    REMOTE_PROC_NODE_DEVICE_EVENT_UPDATE = 377
+    REMOTE_PROC_NODE_DEVICE_EVENT_UPDATE = 377,
+
+    /**
+     * @generate: both
+     * @priority: high
+     * @acl: connect:read
+     */
+    REMOTE_PROC_CONNECT_GET_MAGIC_FILE_CONTENT = 378
 };
```

除了之前提到的结构体之外，我们还修改了枚举类型 `remote_procedure`，关于这个类型的具体修改请参阅文件 `src/remote/remote_protocol.x` 第 3355-3398 行的详尽注释。

根据设置的参数和返回值结构体，在编译过程中，以下函数会生成。

1. `remoteConnectGetMagicFileContent`: remote 驱动客户端 API，位于文件 `src/remote/remote_client_bodies.h`。
2. `spatchConnectGetMagicFileContent`: remote 驱动服务器端 API，位于文件 `daemon/remote_dispatch.h`。
3. `virConnectGetMagicFileContentEnsureACL`：API 权限检查函数，位于文件 `src/access/viraccessapicheck.c`（所以请仔细阅读关于 `@acl` 的注释）。

### 更新 remote_protocol-structs

在上面两个步骤做完之后，只需要更新一下 `src/remote_protocol-structs` 即可。

```patch
diff --git a/src/remote_protocol-structs b/src/remote_protocol-structs
index b71accc07..383a5361d 100644
--- a/src/remote_protocol-structs
+++ b/src/remote_protocol-structs
@@ -2791,6 +2791,9 @@ struct remote_domain_set_guest_vcpus_args {
         int                        state;
         u_int                      flags;
 };
+struct remote_connect_get_magic_file_content_ret {
+    remote_nonnull_string content;
+};
 enum remote_procedure {
         REMOTE_PROC_CONNECT_OPEN = 1,
         REMOTE_PROC_CONNECT_CLOSE = 2,
@@ -3169,4 +3172,5 @@ enum remote_procedure {
         REMOTE_PROC_CONNECT_NODE_DEVICE_EVENT_DEREGISTER_ANY = 375,
         REMOTE_PROC_NODE_DEVICE_EVENT_LIFECYCLE = 376,
         REMOTE_PROC_NODE_DEVICE_EVENT_UPDATE = 377,
+        REMOTE_PROC_CONNECT_GET_MAGIC_FILE_CONTENT = 378
 };
```

> 现在调用链如下，因为现在增加了客户端和服务端的概念，所以通过在其后增加 `@client` 或 `@server` 区分。
>
> ??? -> `virConnectGetMagicFileContent`@LibVirt@client -> `remoteConnectGetMagicFileContent`@remote@client -> `remoteDispatchConnectGetMagicFileContent`@remote@server -> `virConnectGetMagicFileContent`@LibVirt@server -> `qemuConnectGetMagicFileContent`@QEMU@server -> `virQEMUCapsGetMagicFileContent`@QEMU@server

## 在 virsh 中实现功能

最后要做的就是在 `virsh` 中添加一个命令行选项，完成之前实现的公共 API 的调用，并且将 API 返回的数据打印到屏幕上。

你需要修改 `tools/virsh-*.c` 以接受新的命令行选项。对于一个新的参数，你需要在 `hostAndHypervisorCmds` 结构体数组中添加新的元素，并根据这个结构体中元素的值来定义两个结构体数组，类型分别为 `vshCmdInfo` 和 `vshCmdOptDef`，分别用来确定新选项的说明和参数。

针对我们实现公共 API 的位置，这里我们在 `tools/virsh-host.c` 中添加新的选项。

```patch
diff --git a/tools/virsh-host.c b/tools/virsh-host.c
index 2fd368662..ed0c39f5d 100644
--- a/tools/virsh-host.c
+++ b/tools/virsh-host.c
@@ -1379,6 +1379,41 @@ cmdNodeMemoryTune(vshControl *ctl, const vshCmd *cmd)
     goto cleanup;
 }

+/*
+ * "get-magic" command
+ */
+static const vshCmdInfo info_getmagic[] = {
+    {.name = "help",
+     .data = N_("Get magic file's content")
+    },
+    {.name = "desc",
+     .data = N_("Get magic file's content")
+    },
+    {.name = NULL}
+};
+
+static const vshCmdOptDef opts_getmagic[] = {
+    {.name = NULL}
+};
+
+static bool
+cmdGetMagic(vshControl *ctl, const vshCmd *cmd ATTRIBUTE_UNUSED)
+{
+    char *ret = NULL;
+    virshControlPtr priv = ctl->privData;
+
+    ret = virConnectGetMagicFileContent(priv->conn);
+    if (!ret) {
+        vshError(ctl, "%s", _("failed to get magic file's content"));
+        return false;
+    }
+
+    vshPrint(ctl, _("Magic file's content: %s"), ret);
+    VIR_FREE (ret);
+
+    return true;
+}
+
 const vshCmdDef hostAndHypervisorCmds[] = {
     {.name = "allocpages",
      .handler = cmdAllocpages,
@@ -1482,5 +1517,11 @@ const vshCmdDef hostAndHypervisorCmds[] = {
      .info = info_version,
      .flags = 0
     },
+    {.name = "get-magic",
+     .handler = cmdGetMagic,
+     .opts = opts_getmagic,
+     .info = info_getmagic,
+     .flags = 0
+    },
     {.name = NULL}
 };
```

最后修改一下 `tools/virsh.pod`，这个文件将会被 `pod2man` 处理成 `virsh(1)` 的手册。POD 是源于[Perl](https://www.perl.org) 的简单易用的标记语言，可以通过 `perldoc perlpod` 来查看其语法的更多说明。

```patch
diff --git a/tools/virsh.pod b/tools/virsh.pod
index 247d2357b..2d19df86b 100644
--- a/tools/virsh.pod
+++ b/tools/virsh.pod
@@ -611,6 +611,18 @@ specified, then the output will be single-quoted where needed, so that
 it is suitable for reuse in a shell context.  If I<--xml> is
 specified, then the output will be escaped for use in XML.

+=item B<get-magic>
+
+Get magic file's content.
+
+=item B<set-magic> [I<content>]
+
+Set magic file's content.
+
+=item B<magic-status>
+
+Show if magic file can be read.
+
 =back

 =head1 DOMAIN COMMANDS
```

到现在已经完成了包括文档在内的所有工作，如果你要为 LibVirt 添加一个新的功能，所需要做的大约就是这么多。

> 最终的调用链如下。
>
> `cmdGetMagic`@virsh@client -> `virConnectGetMagicFileContent`@LibVirt@client -> `remoteConnectGetMagicFileContent`@remote@client -> `remoteDispatchConnectGetMagicFileContent`@remote@server -> `virConnectGetMagicFileContent`@LibVirt@server -> `qemuConnectGetMagicFileContent`@QEMU@server -> `virQEMUCapsGetMagicFileContent`@QEMU@server

## Hello World!

现在我们已经完成了最后一步，可以最后编译一次源码并测试一下功能。

```bash
make -j8
make test -j8
```

如果编译无误的话，在一个新的终端里运行 `daemon/libvirtd`。

```bash
sudo ./run ./daemon/libvirtd
```

然后看一看新添加的 API 是否工作正常。

```bash
echo 'Hello World!' | sudo tee /var/run/libvirt/magic_file
sudo ./run ./tools/virsh -c qemu:///system get-magic
```

如果一切顺利，现在你已经在终端里看到了刚才写入到文件的 `Hello World!` :)
