
import libusb, strutils, cbor, bytesequtils, tables

let ep_in_addr: uint8 = 0x82

proc read_cb(transfer: ptr LibusbTransfer) {.fastcall.} =
  let buffer = cast[ptr array[16385, byte]](transfer.buffer)
  var inc = @(buffer[])
  var node = parseCbor(inc.toStrBuf)
  let count = cast[ptr int](transfer.userData)
  if node.kind == cborMap and node.map.hasKey(%"type"):
    let t = node.map[%"type"].text
    count[] = count[] + 1
    if count[] %% 10000 == 0:
      echo count[]
  discard libusbSubmitTransfer(transfer)


type TransferWrapper = object
  transfer: ptr LibusbTransfer
  buffer: array[16385, byte]

proc submit(wrp: var TransferWrapper, devh: ptr LibusbDeviceHandle, count: ptr int) =
  wrp.transfer = libusbAllocTransfer(0)
  wrp.transfer.devHandle = devh
  libusbFillBulkTransfer(wrp.transfer, devh, (char)ep_in_addr, cast[ptr char](
        addr wrp.buffer[0]), (cint)sizeof(wrp.buffer), read_cb, count, 0)
  discard libusbSubmitTransfer(wrp.transfer)

type ViaemsConnector = object
  transfer1: TransferWrapper
  transfer2: TransferWrapper
  transfer3: TransferWrapper
  transfer4: TransferWrapper

  dev_handle: ptr LibusbDeviceHandle
  count: int

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


proc loop(conn: var ViaemsConnector) = 
  conn.transfer1.submit(conn.dev_handle, conn.count.addr)
  conn.transfer2.submit(conn.dev_handle, conn.count.addr)
  conn.transfer3.submit(conn.dev_handle, conn.count.addr)
  conn.transfer4.submit(conn.dev_handle, conn.count.addr)

  while true:
    discard libusbHandleEvents(nil)

var conn : ViaemsConnector
conn.connect()
conn.loop()

# shut down library
libusbExit(nil)

echo "Exiting."
