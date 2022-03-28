title: 计算 IP、ICMP、TCP 和 UDP 包的校验和
date: 2016-03-22 20:06:40
toc: true
categories: [ 技术 ]
tags: [ ICMP, IP, TCP, UDP, 校验和, 网络协议 ]

---

## 校验和算法

校验和的计算方法在文档 [RFC 1071][id_ifc_1071] 中有如下说明：

> (1) Adjacent octets to be checksummed are paired to form 16-bit
> integers, and the 1's complement sum of these 16-bit integers is
> formed.
>
> (2) To generate a checksum, the checksum field itself is cleared,
> the 16-bit 1's complement sum is computed over the octets
> concerned, and the 1's complement of this sum is placed in the
> checksum field.

<!-- more -->

即首先将校验和字段清零，将待求和数据调整为偶数字节（如为奇数字节则最后一个字节扩展为字）。然后用反码相加法（进位加到低位上）、以字为单位累加待求和数据。最后将累加结果取反并截低 16 位作为校验和。

> 之所以使用反码相加法，是为了让计算结果和网络序或主机序无关。

根据这个规则，计算校验和的的 C 语言函数可以做如下实现。

```c
uint16_t
GetChecksum (const void * const addr, const size_t bytes)
{
  const uint16_t *word;
  uint32_t sum;
  uint16_t checksum;
  size_t nleft;

  assert (addr);
  assert (bytes > 8 - 1);

  word = (const uint16_t *)addr;
  nleft = bytes;

  /* 使用32 位累加器，顺序累加16 位数据，进位保存在高16 位 */
  for (sum = 0; nleft > 1; nleft -=2)
    {
      sum += *word;
      ++word;
    }

  /* 如果总字节为奇数则处理最后一个字节 */
  sum += nleft ? *(uint8_t *)word : 0;

  /* 将进位加到低16 位，并将本次计算产生的进位再次加到低16 位 */
  sum = (sum >> 16) + (sum & 0xffff);
  sum += (sum >> 16);

  /* 结果取反并截低16 位为校验和 */
  return checksum = ~sum;
}
```

下面会使用这个校验和计算函数分别计算 IP、ICMP、TCP 和 UDP 包的校验和。

[id_ifc_1071]: https://tools.ietf.org/html/rfc1071

## IP 包校验和的计算

IP 包校验和的计算范围在 [RFC 791][id_rfc_791] 中有如下说明：

> The checksum field is the 16 bit one's complement of the one's
> complement sum of all 16 bit words in the header. For purposes of
> computing the checksum, the value of the checksum field is zero.

即 IP 包的校验和只计算包头。

根据描述，IP 包的校验和可用 C 语言做如下计算。

```c
  struct iphdr *ipheader;

  ipheader = (struct iphdr *)packet;

  /* 填充ipheader... */

  /* 计算该IP 包校验和 */
  ipheader->check = 0;
  ipheader->check = GetChecksum (ipheader, sizeof (struct iphdr));
```

[id_rfc_791]: https://tools.ietf.org/html/rfc791

## ICMP 包校验和的计算

ICMP 包校验和的计算范围在 [RFC 792][id_rfc_792] 中有如下说明：

> The checksum is the 16-bit ones's complement of the one's
> complement sum of the ICMP message starting with the ICMP Type.
> For computing the checksum , the checksum field should be zero.
> This checksum may be replaced in the future.

即 ICMP 包的计算范围包括包头和数据。

根据描述，假设 IP 包校验和已经计算完毕，那么其中的 ICMP 包校验和可以用 C 语言做如下计算。

```c
  struct icmphdr *icmpheader;
  const size_t ipheaderSize = sizeof (struct iphdr);

  icmpheader = (struct icmphdr *)(packet + ipheaderSize);

  /* 填充icmpheader... */

  /* 计算该ICMP 包校验和 */
  icmpheader->checksum = 0;
  icmpheader->checksum = GetChecksum (icmpheader, packetSize - ipheaderSize);
```

[id_rfc_792]: https://tools.ietf.org/html/rfc792

## TCP 和 UDP 包校验和的计算

### 伪首部

TCP 和 UDP 校验和的计算要稍微麻烦一些，因为需要引入一个伪首部（pseudo header），伪首部的结构在 [RFC 768][id_rfc_768] 中有如下说明：

> The pseudo header conceptually prefixed to the UDP header contains the
> source address, the destination address, the protocol, and the UDP
> length. This information gives protection against misrouted datagrams.
> This checksum procedure is the same as is used in TCP.
>
>                    0      7 8     15 16    23 24    31
>                   +--------+--------+--------+--------+
>                   |          source address           |
>                   +--------+--------+--------+--------+
>                   |        destination address        |
>                   +--------+--------+--------+--------+
>                   |  zero  |protocol|   UDP length    |
>                   +--------+--------+--------+--------+

可见 TCP 和 UDP 的伪首部结构完全一致。

根据描述，伪首部的结构可以用 C 语言结构体做如下实现。

```c
typedef struct pseudohdr
{
  uint32_t src;
  uint32_t dst;
  uint8_t zero;
  uint8_t protocol;
  uint16_t len;
} pseudohdr_t;
```

### TCP 包校验和的计算

TCP 包校验和的计算方法在 [RFC 793][id_rfc_793] 中有如下说明：

> The checksum field is the 16 bit one's complement of the one's
> complement sum of all 16 bit words in the header and text. If a
> segment contains an odd number of header and text octets to be
> checksummed, the last octet is padded on the right with zeros to
> form a 16 bit word for checksum purposes. The pad is not
> transmitted as part of the segment. While computing the checksum,
> the checksum field itself is replaced with zeros.
>
> The checksum also covers a 96 bit pseudo header conceptually

可见，算法和之前提到的校验和算法完全一致，根据描述校验和的计算需要包含伪首部和整个 TCP 包。

根据描述，假设 IP 包校验和已经计算完毕，那么其中的 TCP 包校验和可以用 C 语言做如下计算。

```c
  char *tcpsumblock;          /* 伪首部 + TCP 头 + 数据 */
  struct iphdr *ipheader;
  struct tcphdr *tcpheader;
  pseudohdr_t pseudoheader;
  const size_t ipheaderSize = (struct iphdr *)packet;

  ipheader = (struct iphdr *)packet;
  tcpheader = (struct tcphdr *)(packet + ipheaderSize);

  /* 填充tcpheader... */

  /* 填充pseudoheader */
  pseudoheader.src = ipheader->saddr;
  pseudoheader.dst = ipheader->daddr;
  pseudoheader.zero = 0;
  pseudoheader.protocol = ipheader->protocol;
  pseudoheader.len = htons (sizeof (struct tcphdr));

  /* 填充tcpsumblock */
  tcpheader->check = 0;
  tcpsumblock = (char *)malloc (packetSize);
  memcpy (tcpsumblock, &pseudoheader, sizeof (pseudohdr_t));
  memcpy (tcpsumblock + sizeof (pseudohdr_t), packet, packetSize);

  /* 计算TCP 包校验和 */
  tcpheader->check =
    GetChecksum (tcpsumblock, sizeof (pseudohdr_t) + packetSize - ipheaderSize);

  free (tcpsumblock);
  tcpsumblock = NULL;
```

### UDP 包校验和的计算

UDP 包校验和的计算方法在 [RFC 768][id_rfc_768] 中有如下说明：

> Checksum is the 16-bit one's complement of the one's complement sum of a
> pseudo header of information from the IP header, the UDP header, and the
> data, padded with zero octets at the end (if necessary) to make a
> multiple of two octets.
>
> The pseudo header conceptually prefixed to the UDP header contains the
> source address, the destination address, the protocol, and the UDP
> length. This information gives protection against misrouted datagrams.
> This checksum procedure is the same as is used in TCP.

所以 UDP 包校验和的计算方法和 TCP 包如出一辙，同样包含了一个伪首部。

具体的实现可以参考之前计算 TCP 包校验的 C 语言实现。

[id_rfc_793]: https://tools.ietf.org/html/rfc793
[id_rfc_768]: https://tools.ietf.org/html/rfc768
