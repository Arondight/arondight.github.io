title: 使用GPG签名Git提交和标签
date: 2016-04-17 14:16:53
categories:
  - 技术
tags:
  - Git
  - GPG
  - GitHub
---

# GPG 是什么

提GPG 之前需要提一个软件叫PGP。PGP 是“Pretty Good Privacy” 的缩写，名字言简意赅，上来就把软件的用途拍用户脸上。然而PGP 不是自由软件，所以自由软件基金会决定开发一个替代PGP 的自由软件，于是有了GPG（GnuPG）。

GPG 可以提供对信息、文件的签名和验证，或者是加密和解密，主要用于不安全网络上的信息传输。为此GPG 需要一个密钥对，其中公钥单独可完成签名和验证，加密和解密则需要分别使用公钥和私钥来完成。

<!-- more -->

# 签名

## 生成公钥

首先需要生成一个GPG 公钥，GPG 在生成密钥的时候会使用一个根据你的操作生成的随机数，所以你可以在GPG 生成密钥的时候多做一些操作，例如点鼠标、敲键盘、复制文件等等。你可以利用`dd` 指令在生成密钥的期间做一些读写操作以让随机数字发生器获得足够的熵数。

```bash
sudo dd if=/dev/random of=/dev/null bs=4M
```

然后可以生成GPG 密钥，推荐使用`--full-gen-key` 选项来启用所有的功能。

```bash
gpg --full-gen-key
```

其中需要注意的事情有以下几项：

1. 密钥种类：形如`method1 and method2` 的选项是生成一个密钥对（公钥和私钥），可以用于签名/验证和加密/解密，如果你仅仅是为了签名而不想用于加密，可以使用一个形如`method` 的选项（只生成公钥）。
2. 密钥长度：越长越安全，同时加密解密的时间花费越多，选择一个你认为合理的长度。
3. 有效期限：你需要选择一个你认为合理的有效期限，公钥到期后，签名将失效，GPG 服务器也会删除该公钥，所以一般来说你需要使用一个永不过期的公钥。
4. 密钥密码：一定要为你的密钥设置一个足够强壮的密码！

## 上传公钥到服务器

现在你可以将你的公钥上传到任意GPG 服务器上了，通过交换机制，全球所有的GPG 服务器都会得到你的公钥。你可以列出你现在所拥有的公钥。

```bash
gpg --list-keys
```

根据用户名和邮箱，找到你之前生成的那个密钥。其中`pub` 代表公钥，`sub` 则是私钥。下面是一个样例输出。

```
pub   rsa4096/B66CC194 2016-04-15 [SC]
uid         [ 绝对 ] Arondight <shell_way@foxmail.com>
sub   rsa4096/F96E3CB7 2016-04-15 [E]
```

可以看到一个算法为RSA、长度为4096、钥匙号（key ID）为`B66CC194` 的公钥。找出公钥后，就可以上传这个公钥到GPG 服务器了。

```bash
gpg --keyserver subkeys.pgp.net --send-keys <key ID>
```

## 上传公钥到GitHub

GitHub 刚刚发布了支持GPG 签名的消息，所以你可以选择使用GitHub 托管你的仓库。首先你需要以文本形式导出你的公钥。

```bash
gpg -a -o gnupg.pub --export <key ID>
```

然后打开你的GitHub [密钥管理](https://github.com/settings/keys)界面，根据文件`gnupg.pub` 为你的GitHub 账户配置公钥。

> 注意：这一步不是必须的，你不一定要使用GitHub，或许你更喜欢使用其他的商业产品，或者自己搭建一个Git 服务器。Git 本身就是支持GPG 签名的，GitHub 对GPG 的支持仅是把验证结果在网页上显示出来（使用你上传的公钥）。

## 导出指纹

然而不幸的是，任何人都可以冒充你的名义上传公钥到GPG 服务器，所以对方搜到以你的名义发布的公钥，不一定真的是你发布的。为了避免这个问题，你需要公布一个该公钥的指纹。GPG 导入公钥后必须手动设置信任度。这时候对方就可以通过对比手中公钥的指纹和你提供的指纹，来确定得到的公钥是否是你发布的公钥。

```bash
LANG=en_US gpg --fingerprint <key ID> >fingerprint
```

然后将`fingerprint` 文件提交到你的项目仓库中，或者公布在网络的其他位置。

> 注意：其实你可以通过`--export-ownertrust` 和`--import-ownertrust` 来直接导出和导入信任度，但是不推荐这样做。

## 签名提交和标签

首先你需要为Git 设置一个用于签名的公钥，通常来说所有的个人项目都用一个公钥进行签名，所以建议设置为全局配置。

```bash
git config --global user.signingkey <key ID>
```

然后就可以使用这个公钥来签名提交。

```bash
git commit -S
```

或者签名标签了。

```bash
git tag -s <tag>
```

## 关于私钥

你可能注意到了，整个过程中我们都没有使用到私钥。之前也提到过，GPG 签名和验证的过程不需要私钥，私钥在解密过程中使用的。所以如果你生成了一个包含私钥的密钥对，任何情况向下都不要把私钥泄露给除了你之外的任何人。如果需要向对方发送加密信息，请让对方提供指纹，导入对方的公钥进行加密，而不要将自己的私钥发送过去。

# 验证

## 获得公钥

你可以根据你得到的信息在任何GPG 服务器上查找对应的公钥，典型的例如查看指纹，然后根据指纹到服务器上查找公钥。

```bash
gpg --keyserver subkeys.pgp.net --search-keys <key ID>
```

选择对应的编号，会自动下载并导入该公钥。

## 设置信任

导入后的公钥需要设置信任度才能使用该公钥进行验证，你可以通过类似下面的指令编辑该公钥的信息。

```bash
gpg --edit-key <key ID>
```

你所看到的应该是一个文本交互界面，下面是一个样例。

```
gpg (GnuPG) 2.1.11; Copyright (C) 2016 Free Software Foundation, Inc.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

私钥可用。

sec  rsa4096/B66CC194
     创建于：2016-04-15  有效至：永不过期  可用于：SC
     信任度：绝对        有效性：绝对
ssb  rsa4096/F96E3CB7
     创建于：2016-04-15  有效至：永不过期  可用于：E
[ 绝对 ] (1). Arondight <shell_way@foxmail.com>

gpg>
```

你可以键入`fpr` 来打印这个公钥的指纹，和你得到的指纹进行对比，如果一致的话，那么键入`trust` 来设置该密钥的信任度。最后键入`quit` 退出。

## 验证签名

现在你可以用导入的公钥来验证你`git clone` 下来的仓库的提交和标签了，同样你需要首先告诉Git 应该使用哪个公钥对这个仓库进行验证。一般来说不同作者的项目公钥都不同，建议不要将用于验证的公钥设置为全局。

```bash
git config user.signingkey <key ID>
```

然后可以像下面这样验证一个提交。

```bash
git verify-commit HEAD
```

或者验证一个标签。

```bash
git tag -v <tag>
```

# 扩展阅读

## 签名和验证

| 动作 | 指令 |
| --- | --- |
| 二进制方式签名文件 | `gpg -u <key ID> -s file` |
| 纯文本方式签名文件 | `gpg -u <key ID> --clearsign file` |
| 签名文件并独立存放签名 | `gpg -u <key ID> --detach-sign file` |
| 验证文件 | `gpg --verify-files file` |
| 通过独立的签名文件验证文件 | `gpg --verify-files file.sig file` |

## 加密和解密

| 动作 | 指令 |
| --- | --- |
| 二进制方式加密文件 | `gpg -r <key ID> -e file` |
| 纯文本方式加密文件 | `gpg -r <key ID> -a -e file` |
| 解密文件 | `gpg file` |

> 如果你想在加密的同时签名文件，在加密指令中额外指定一个`-s` 选项。

