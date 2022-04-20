
import libusb, cbor, bytesequtils, tables

const ep_in_addr: uint8 = 0x82

type 
  MessageReceivedCallback = proc(value: CborNode) {.closure.}

  TransferWrapper = object
    transfer: ptr LibusbTransfer
    buffer: array[16385, byte]
  
  ViaemsConnector = object
    transfer1: TransferWrapper
    transfer2: TransferWrapper
    transfer3: TransferWrapper
    transfer4: TransferWrapper
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

  let devh = libusbOpenDeviceWithVidPid(nil, 0x0483, 0x5740)
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
  conn.submit(conn.transfer2)
  conn.submit(conn.transfer3)
  conn.submit(conn.transfer4)

  while true:
    discard libusbHandleEvents(nil)



proc cb(n: CborNode) =
  echo "received: ", n

var conn : ViaemsConnector
conn.connect()
conn.loop(cb)

# shut down library
libusbExit(nil)

echo "Exiting."
