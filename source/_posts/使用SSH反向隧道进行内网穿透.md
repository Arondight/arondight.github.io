title: 使用SSH反向隧道进行内网穿透
date: 2016-02-17 18:09:57
toc: true
tags:
  - 技术
  - 运维
  - 内网穿透
  - SSH
  - 隧道
---

# 对应的情况

这篇文章主要介绍了如何利用SSH 反向隧道穿透NAT，并演示了如何维持一条稳定的SSH 隧道。

假设有机器A 和B，A 有公网IP，B 位于NAT 之后并无可用的端口转发，现在想由A 主动向B 发起SSH 连接。由于B 在NAT 后端，无可用**公网IP + 端口** 这样一个组合，所以A 无法穿透NAT，这篇文章应对的就是这种情况。

首先有如下约定，因为很重要所以放在前面：

| 机器代号 | 机器位置 | 地址 | 账户 | ssh/sshd 端口 | 是否需要运行sshd |
| --- | --- | --- | --- | --- | --- |
| A | 位于公网 | a.site | usera | 22 | 是 |
| B | 位于NAT 之后 | b.localhost | userb | 22 | 是 |
| C | 位于NAT 之后 | c.localhost | userc | 22 | 否 |

1. 这里默认你的系统init 程序为`systemd`，如果你使用其他的init 程序，如果没有特殊理由还是换到一个现代化的GNU/Linux 系统吧……
2. 如果**B** 关闭了所有端口，请按组合键`Ctrl+W`，因为这篇文章是建立在B 上正常运行着`sshd` 的前提上的。

<!-- more -->

# SSH 反向隧道

这种手段实质上是由B 向A 主动地建立一个SSH 隧道，将A 的6766 端口转发到B 的22 端口上，只要这条隧道不关闭，这个转发就是有效的。有了这个端口转发，只需要访问A 的6766 端口反向连接B 即可。

首先在**B** 上建立一个SSH 隧道，将A 的6766 端口转发到B 的22 端口上：

```bash
B $ ssh -p 22 -qngfNTR 6766:b.localhost:22 usera@a.site
```

然后在**A** 上利用6766 端口反向SSH 到B：

```bash
A $ ssh -p 6766 userb@b.localhost
```

要做的事情其实就是这么简单。

# 隧道的维持

## 稳定性维持

然而不幸的是SSH 连接是会超时关闭的，如果连接关闭，隧道无法维持，那么A 就无法利用反向隧道穿透B 所在的NAT 了，为此我们需要一种方案来提供一条稳定的SSH 反向隧道。

一个最简单的方法就是`autossh`，这个软件会在超时之后自动重新建立SSH 隧道，这样就解决了隧道的稳定性问题，如果你使用[Arch Linux](https://www.archlinux.org)，你可以这样获得它：

```bash
$ sudo pacman -S autossh
```

下面在**B** 上做之前类似的事情，不同的是该隧道会由`autossh` 来维持：

```bash
B $ autossh -p 22 -fM 6777 -NR 6766:b.localhost:22 usera@a.site
```

`-M` 参数指定的端口用来监听隧道的状态，与端口转发无关。

之后你可以在A 上通过6766 端口访问B 了：

```bash
A $ ssh -p 6766 userb@a.site
```

## 隧道的自动建立

然而这又有了另外一个问题，如果B 重启隧道就会消失。那么需要有一种手段在B 每次启动时使用`autossh` 来建立SSH 隧道。很自然的一个想法就是做成服务，之后会给出在`systemd` 下的一种解决方案。

# “打洞”

之所以标题这么起，是因为自己觉得这件事情有点类似于UDP 打洞，即通过一台在公网的机器，让两台分别位于各自NAT 之后的机器可以建立SSH 连接。

下面演示如何使用SSH 反向隧道，让C 使用反向隧道连接到B。

首先在**A** 上编辑`sshd` 的配置文件`/etc/ssh/sshd_config`，将`GatewayPorts` 开关打开：

```
GatewayPorts yes
```

然后重启`sshd`：

```bash
A $ sudo systemctl restart sshd
```

然后在**B** 上对之前用到的`autossh` 指令略加修改：

```bash
B $ autossh -p 22 -fM 6777 -NR '*:6766:b.localhost:22' usera@a.site
```

之后在**C** 上利用**A** 的6766 端口SSH 连接到**B**：

```bash
C $ ssh -p 6766 userb@a.site
```

至此你已经轻而易举的穿透了两层NAT。

# 最终的解决方案

整合一下前面提到的，最终的解决方案如下：

首先打开**A** 上`sshd` 的`GatewayPorts` 开关，并重启`sshd`（如有需要）。

然后在**B** 上新建一个用户*autossh*，根据权限最小化思想，B 上的`autossh` 服务将以*autossh* 用户的身份运行，以尽大可能避免出现安全问题：

```bash
B $ sudo useradd -m autossh
B $ sudo passwd autossh
```

紧接着在**B** 上为*autossh* 用户创建SSH 密钥，并上传到A：

```bash
B $ su - autossh
B $ ssh-keygen -t 'rsa' -C 'autossh@b.localhost'
B $ ssh-copy-id usera@a.site
```

注意该**密钥不要设置密码**，也就是运行`ssh-keygen` 指令时尽管一路回车，不要输入额外的字符。

然后在**B** 上创建以*autossh* 用户权限调用`autossh` 的service 文件。将下面文本写入到文件`/lib/systemd/system/autossh.service`，并设置权限为644：

```
[Unit]
Description=Auto SSH Tunnel
After=network.target

[Service]
User=autossh
Type=simple
ExecStart=/bin/autossh -p 22 -fM 6777 -NR '*:6766:b.localhost:22' usera@a.site -i /home/autossh/.ssh/id_rsa
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=always

[Install]
WantedBy=multi-user.target
```

在**B** 上设置该服务自动启动：

```bash
B $ sudo systemctl enable autossh
```

如果你愿意，在这之后可以立刻启动它：

```bash
B $ sudo systemctl start autossh
```

然后你可以在**A** 上使用这条反向隧道穿透B 所在的NAT SSH 连接到B：

```bash
A $ ssh -p 6766 userb@127.0.0.1
```

或者是在**C** 上直接穿透两层NAT SSH 连接到B：

```bash
C $ ssh -p 6766 userb@a.site
```


