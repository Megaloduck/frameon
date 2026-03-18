// web/serial_interop.js
// Provides Web Serial API access to Flutter via dart:js_interop.
// Loaded by index.html before the Flutter app boots.
// Exposes window.serialBridge for Dart to call.

(function () {
  let port = null;
  let reader = null;
  let writer = null;
  let lineBuffer = '';
  const lineListeners = [];

  window.serialBridge = {
    isAvailable: () => 'serial' in navigator,

    requestPort: async () => {
      try {
        port = await navigator.serial.requestPort({
          filters: [
            { usbVendorId: 0x10C4 }, // Silicon Labs CP2102 (most ESP32 devboards)
            { usbVendorId: 0x1A86 }, // CH340 / CH341
            { usbVendorId: 0x0403 }, // FTDI
            { usbVendorId: 0x2341 }, // Arduino
          ],
        });
        return true;
      } catch {
        return false;
      }
    },

    openPort: async (baudRate) => {
      if (!port) throw new Error('No port selected');
      await port.open({ baudRate: baudRate || 115200 });
      writer = port.writable.getWriter();
      _startReading();
    },

    write: async (text) => {
      if (!writer) throw new Error('Port not open');
      const encoded = new TextEncoder().encode(text);
      await writer.write(encoded);
    },

    addLineListener: (cb) => {
      lineListeners.push(cb);
    },

    removeLineListener: (cb) => {
      const i = lineListeners.indexOf(cb);
      if (i >= 0) lineListeners.splice(i, 1);
    },

    close: async () => {
      try {
        if (reader) { await reader.cancel(); reader = null; }
        if (writer) { await writer.close(); writer = null; }
        if (port) { await port.close(); port = null; }
      } catch (e) {
        console.warn('Serial close error:', e);
      }
    },
  };

  async function _startReading() {
    const decoder = new TextDecoder();
    reader = port.readable.getReader();
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        lineBuffer += decoder.decode(value);
        let nl;
        while ((nl = lineBuffer.indexOf('\n')) !== -1) {
          const line = lineBuffer.slice(0, nl).replace(/\r$/, '');
          lineBuffer = lineBuffer.slice(nl + 1);
          lineListeners.forEach(cb => {
            try { cb(line); } catch (e) { console.error('lineListener error', e); }
          });
        }
      }
    } catch (e) {
      console.warn('Serial read ended:', e);
    } finally {
      reader = null;
    }
  }
})();
