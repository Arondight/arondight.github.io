title: GTK事件及信号机制
date: 2016-07-19 20:37:56
categories:
  - 技术
tags:
  - C
  - GDK
  - CTK
  - Callback
  - Event
  - Singal
---

最近在给公司重写一版用Qt3 写的软件，界面比较老，功能也年久失修，商量了一下决定用GTK 重写界面和功能。之前接触的都是Qt，对GTK 了解不多。个人觉得跟Qt 的信号-槽机制相比，GTK 的的信号回调机制稍显不同。然后这篇文章就是自己理解的GTK 信号回调机制。

## 事件和信号

GTK 是一个基于**事件**驱动的框架，就是说GTK 程序会一直循环在`gtk_main` 函数中，直至一个事件发生，然后跳转到对应的事件处理函数中，执行完毕后再次回到`gtk_main` 的循环。这听起来很符合逻辑，但是GTK 中除了事件外，还有一个概念是**信号**，特别是当你写几个GTK 程序后就会发现你处理的几乎都是信号。

典型的例如。

```c
g_signal_connect (G_OBJECT (mainWindow), "delete_event", G_CALLBACK (gtk_main_quit), NULL);
```

那么`"delete_event"` 到底是事件还是信号——它被用于`g_signal_connect` 中，但是名字带有`event` 字样。

<!-- more -->

在GTK 中，事件是X11 中发生的，GTK 通过GDK 将X11 中的`XEvent` 转化为`GdkEvent`，其类型`GdkEventType` 定义在头文件`gdk/gdkevents.h` 中。

> GDK 是Xlib 的一个封装。

而信号与事件不同，是GTK 本身的概念。在GTK 中，一个事件发生之后，会通过函数`gtk_widget_event` 将事件转化为信号，并通过函数`g_signal_emit` 将信号发射出去，如果有回调和该信号绑定，那么这个回调**有可能**被执行。

举例来说，当`GtkButton` 上发生了鼠标点击的动作时，默认地事件和信号的顺序如下。

1. `GDK_BUTTON_PRESS` 事件产生 -> 调用GDK 中针对该事件的回调
2. `"button_press_event"` 信号发射 -> 调用GTK 中针对该信号的回调
3. `"clicked"` 信号发射 -> 调用GTK 中针对该信号的回调

那么`"delete_event"` 到底是事件还是信号？它是一个信号，但是只有在事件`GDK_DELETE` 发生后才会被发射出去，所以它也代表一个事件。

这也是GTK 一个稍微有点混乱的地方——**事件的发生是通过信号的发射反应的**。所以你如果想在GTK 中处理事件，你需要处理信号。

## 回调机制

### 回调的绑定

和Qt 的信号-槽机制不同，GTK 中采用回调机制来处理信号。GTK 中为信号绑定回调的方式都通过同一个函数`g_signal_connect_data` 完成，其原形定义在头文件`gobject/gsignal.h`。

```c
gulong g_signal_connect_data (gpointer instance, const gchar *detailed_signal,
                              GCallback c_handler, gpointer data,
                              GClosureNotify destroy_data, GConnectFlags connect_flags);
```

> 因为信号处理在Glib 而非GTK 中，所以函数名以`g_` 而非`gtk_` 开头。

但是更加常用的是在其上封装的三个宏，与`g_signal_connect_data` 定义在同一个头文件中。

```c
#define g_signal_connect(instance, detailed_signal, c_handler, data) \
  g_signal_connect_data ((instance), (detailed_signal), (c_handler), (data), NULL, (GConnectFlags) 0)
#define g_signal_connect_after(instance, detailed_signal, c_handler, data) \
  g_signal_connect_data ((instance), (detailed_signal), (c_handler), (data), NULL, G_CONNECT_AFTER)
#define g_signal_connect_swapped(instance, detailed_signal, c_handler, data) \
  g_signal_connect_data ((instance), (detailed_signal), (c_handler), (data), NULL, G_CONNECT_SWAPPED)
```

其中。

+ `g_signal_connect`： 为信号绑定一个回调函数，该回调将先于默认回调执行。
+ `g_signal_connect_after`： 和`g_singal_connect` 类似，但是该回调将在默认回调之后执行。
+ `g_signal_connect_swapped`：回调先于默认回调执行，但是回调的参数位置应该和前两个绑定函数的回调参数位置交换。

`g_signal_connect_swapped` 中`swapped` 的效果如下。

```c
void handler (GtkWidget *widget, gpointer data);
void handlerSwapped (gpointer data, GtkWidget *widget);
```

> 个人觉得`g_signal_connect_swapped` 最好少用，它只会把水搅浑。

### 回调的形式

在Gtk 中，回调的形式有两种，在反应事件的信号回调中，handler 需要额外增加一个`GdkEvent *` 参数，用来传入发生的事件。

这两种回调之间的区别如下（假设使用`g_signal_connect` 绑定）。

```c
void buttonClickedHandler (GtkWidget *button, gpointer data);
gboolean keyPressEventHandler (GtkWidget *button, GdkEvent *event, gpointer data);
```

### 回调的流程

#### 相较默认回调

信号可以绑定多个回调，至于自定义回调是否先于默认回调执行，参见上节关于`g_signal_connect_after` 的说明。

#### 终止处理过程

除了增加了`GdkEvent *` 作为参数外，处理事件的回调函数还有`gboolean` 类型的返回值，这个返回值用于控制该事件处理过程是否继续。

返回值的情况如下。

| 返回值 | 含义 |
| --- | --- |
| `TRUE` | 该事件已经处理完毕，不再继续调用其他和该事件绑定的回调 |
| `FALSE` | 需要继续执行其他与该事件绑定的回调函数 |

#### 信号发射顺序

因为GTK 先捕获事件再转化为信号，所以直接反应事件的信号在其他信号之前被发射，所以同一个`GtkWidget` 上处理事件的回调总在其他信号回调之前被执行。

所以上一节的最后一段代码片中，假设`buttonClickedHandler` 和`keyPressEventHandler`  分别被绑定到一个`GtkButton` 的`"event"` 和`"clicked"` 信号上，如果`keyPressEventHandler` 返回`TRUE`，那么`buttonClickedHandler` 将不会被执行。

