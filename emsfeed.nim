
import libusb, cbor, bytesequtils, tables
import threading/channels

const ep_in_addr: uint8 = 0x81

type 
  MessageReceivedCallback = proc(value: CborNode) {.closure.}

  TransferWrapper = object
    transfer: ptr LibusbTransfer
    buffer: array[16385, byte]
  
  ViaemsConnector = object
    transfer1: TransferWrapper
    dev_handle: ptr LibusbDeviceHandle
    messageReceived: MessageReceivedCallback


proc read_cb(transfer: ptr LibusbTransfer) {.fastcall.} =
  let buffer = cast[ptr array[16385, byte]](transfer.buffer)
  let conn = cast[ptr ViaemsConnector](transfer.userData)
  var inc = @(buffer[])
  var node = parseCbor(inc.toStrBuf)
  if node.kind == cborMap and node.map.hasKey(%"type"):
    conn.messageReceived(node)
  discard libusbSubmitTransfer(transfer)

proc submit(conn: var ViaemsConnector, wrp: var TransferWrapper) =
  wrp.transfer = libusbAllocTransfer(0)
  wrp.transfer.devHandle = conn.dev_handle
  libusbFillBulkTransfer(wrp.transfer, conn.dev_handle, (char)ep_in_addr, cast[ptr char](
        addr wrp.buffer[0]), (cint)sizeof(wrp.buffer), read_cb, addr conn, 0)
  discard libusbSubmitTransfer(wrp.transfer)

proc connect(conn: var ViaemsConnector) =
  let r = libusbInit(nil)
  if r < 0:
    quit()
  else:
    echo "Success: Initialized libusb"

  let devh = libusbOpenDeviceWithVidPid(nil, 0x1209, 0x2041)
  if devh.isNil:
    echo "Could not open"
    quit()
  conn.dev_handle = devh

  for i in 0..2:
    if libusbKernelDriverActive(devh, (cint)i) > 0:
      discard libusbDetachKernelDriver(devh, (cint)i)
    discard libusbClaimInterface(devh, (cint)i)

  discard libusbControlTransfer(devh, 0x21, (LibusbStandardRequest)0x22, 0x1 or 0x2, 0, nil, 0, 0)

  var encoding = [0x80.uint8, 0x25, 0x00, 0x00, 0x00, 0x00, 0x08]
  discard libusbControlTransfer(devh, 0x21, (LibusbStandardRequest)0x20, 0, 0, cast[
      ptr cuchar](addr encoding[0]), (uint16)sizeof(encoding), 0)


proc loop(conn: var ViaemsConnector, cb: MessageReceivedCallback) =
  conn.messageReceived = cb
  conn.submit(conn.transfer1)

  while true:
    discard libusbHandleEvents(nil)


var ch = newChan[CborNode]()

proc getter() =
  var conn : ViaemsConnector
  conn.connect()
  conn.loop(proc (n: CborNode) = ch.send(n))

var gthread : system.Thread[void]
createThread(gthread, getter)

proc receiver() = 
  var counter = -50
  while true:
    var msg : CborNode
    ch.recv(msg)
    if counter mod 10000 == 0:
      echo msg
    if counter == 100000:
      quit QuitSuccess
    counter += 1

receiver()

# shut down library
libusbExit(nil)

echo "Exiting."
