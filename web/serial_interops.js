// web/serial_interop.js  (note: no trailing 's' — matches index.html src)
// Provides Web Serial API access to Flutter via dart:js_interop.
// Loaded by index.html BEFORE flutter_bootstrap.js boots.
// Exposes window.serialBridge for Dart @JS bindings to call.

(function () {
  'use strict';

  let port = null;
  let reader = null;
  let writer = null;
  let lineBuffer = '';
  const lineListeners = [];

  window.serialBridge = {

    isAvailable: () => !!(navigator && navigator.serial),

    // Opens browser port picker. Returns true if user selected a port.
    requestPort: async () => {
      try {
        port = await navigator.serial.requestPort({
          filters: [
            { usbVendorId: 0x10C4 }, // Silicon Labs CP2102 — most ESP32 devboards
            { usbVendorId: 0x1A86 }, // CH340 / CH341
            { usbVendorId: 0x0403 }, // FTDI FT232
            { usbVendorId: 0x2341 }, // Arduino
            { usbVendorId: 0x239A }, // Adafruit
          ],
        });
        return true;
      } catch (e) {
        // User cancelled or permission denied — not an error worth logging
        console.info('Serial port not selected:', e.message);
        return false;
      }
    },

    // Opens the selected port at the given baud rate.
    openPort: async (baudRate) => {
      if (!port) throw new Error('No port selected — call requestPort first');
      await port.open({ baudRate: baudRate || 115200 });
      writer = port.writable.getWriter();
      _startReading(); // fire-and-forget background loop
    },

    // Writes a UTF-8 string to the serial port.
    write: async (text) => {
      if (!writer) throw new Error('Port not open');
      const encoded = new TextEncoder().encode(text);
      await writer.write(encoded);
    },

    // Registers a callback(line: string) for each complete newline-terminated line.
    addLineListener: (cb) => {
      if (typeof cb === 'function' && !lineListeners.includes(cb)) {
        lineListeners.push(cb);
      }
    },

    // Unregisters a previously added line listener.
    removeLineListener: (cb) => {
      const i = lineListeners.indexOf(cb);
      if (i >= 0) lineListeners.splice(i, 1);
    },

    // Closes reader, writer, and port cleanly.
    close: async () => {
      try {
        if (reader) {
          await reader.cancel();
          reader.releaseLock();
          reader = null;
        }
      } catch (e) {
        console.warn('Error cancelling reader:', e);
      }
      try {
        if (writer) {
          await writer.close();
          writer = null;
        }
      } catch (e) {
        console.warn('Error closing writer:', e);
      }
      try {
        if (port) {
          await port.close();
          port = null;
        }
      } catch (e) {
        console.warn('Error closing port:', e);
      }
      lineBuffer = '';
    },
  };

  // Background loop: reads bytes from port, splits on newlines, fires listeners.
  async function _startReading() {
    if (!port || !port.readable) return;
    const decoder = new TextDecoder();
    reader = port.readable.getReader();
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        lineBuffer += decoder.decode(value, { stream: true });

        let nl;
        while ((nl = lineBuffer.indexOf('\n')) !== -1) {
          const line = lineBuffer.slice(0, nl).replace(/\r$/, '');
          lineBuffer = lineBuffer.slice(nl + 1);
          if (line.length > 0) {
            lineListeners.forEach(cb => {
              try { cb(line); } catch (e) {
                console.error('lineListener threw:', e);
              }
            });
          }
        }
      }
    } catch (e) {
      if (e.name !== 'NetworkError') {
        // NetworkError is expected on port.close() — don't spam console
        console.warn('Serial read loop ended:', e);
      }
    } finally {
      try { reader.releaseLock(); } catch (_) {}
      reader = null;
    }
  }

})();
