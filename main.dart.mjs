// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      AC: Function.prototype.call.bind(DataView.prototype.setUint16),
      AD: x0 => x0.width,
      AE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      AF: x0 => x0.wheelDeltaX,
      AG: x0 => x0.parentElement,
      AH: x0 => x0.readText(),
      AI: () => Date.now(),
      AJ: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      AK: (x0,x1) => x0.sqlite3_value_blob(x1),
      AL: x0 => x0.call(),
      AM: x0 => x0.length,
      AN: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      AO: (x0,x1) => { x0.disabled = x1 },
      AP: x0 => x0.size,
      B: s => printToConsole(s),
      BB: b => !!b,
      BC: Function.prototype.call.bind(DataView.prototype.setUint8),
      BD: x0 => x0.screen,
      BE: x0 => new ResizeObserver(x0),
      BF: x0 => x0.key,
      BG: (x0,x1) => x0.querySelectorAll(x1),
      BH: x0 => x0.clipboard,
      BI: x0 => new WeakRef(x0),
      BJ: () => globalThis.Promise.resolve(),
      BK: (x0,x1) => x0.sqlite3_value_bytes(x1),
      BL: x0 => x0.instance,
      BM: (x0,x1) => x0.get(x1),
      BN: (x0,x1) => globalThis.fetch(x0,x1),
      BO: (x0,x1) => { x0.scrollLeft = x1 },
      BP: x0 => x0.name,
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      CC: Function.prototype.call.bind(DataView.prototype.setInt8),
      CD: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      CE: (x0,x1) => x0.getPropertyValue(x1),
      CF: x0 => x0.identifier,
      CG: (x0,x1) => x0.requestAnimationFrame(x1),
      CH: (x0,x1) => x0.writeText(x1),
      CI: x0 => x0.deref(),
      CJ: (x0,x1) => x0.then(x1),
      CK: (x0,x1) => x0.sqlite3_value_text(x1),
      CL: (x0,x1,x2) => x0.instantiateStreaming(x1,x2),
      CM: (x0,x1) => x0.index(x1),
      CN: (x0,x1) => x0.get(x1),
      CO: (x0,x1) => { x0.spellcheck = x1 },
      CP: x0 => x0.type,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: (x0,x1) => x0.focus(x1),
      DC: Function.prototype.call.bind(DataView.prototype.getInt8),
      DD: x0 => x0.tabIndex,
      DE: x0 => globalThis.parseFloat(x0),
      DF: x0 => x0.touches,
      DG: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      DH: x0 => x0.unlock(),
      DI: () => globalThis.WeakRef,
      DJ: x0 => x0.abort(),
      DK: (x0,x1) => x0.sqlite3_value_double(x1),
      DL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      DM: x0 => x0.openKeyCursor(),
      DN: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      DO: (x0,x1) => { x0.disabled = x1 },
      DP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: () => ({}),
      EC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      ED: (x0,x1) => x0.contains(x1),
      EE: (x0,x1) => x0.getComputedStyle(x1),
      EF: x0 => x0.pressure,
      EG: x0 => x0.now(),
      EH: (x0,x1) => x0.lock(x1),
      EI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      EJ: x0 => x0.commit(),
      EK: (x0,x1) => x0.sqlite3_value_int64(x1),
      EL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      EM: x0 => x0.primaryKey,
      EN: (x0,x1) => x0.forEach(x1),
      EO: (x0,x1) => x0.transferFromImageBitmap(x1),
      EP: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      F: () => new Error().stack,
      FB: (o, p, v) => o[p] = v,
      FC: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      FD: x0 => x0.activeElement,
      FE: x0 => x0.documentElement,
      FF: x0 => x0.tiltY,
      FG: x0 => x0.performance,
      FH: x0 => x0.orientation,
      FI: (a, s, e) => a.slice(s, e),
      FJ: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      FK: (x0,x1) => x0.sqlite3_value_type(x1),
      FL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return wasmFunction(f,arguments.length,x0,x1,x2,x3,x4) }),
      FM: (x0,x1,x2) => x0.open(x1,x2),
      FN: x0 => x0.statusText,
      FO: (x0,x1) => x0.getContext(x1),
      FP: x0 => x0.files,
      G: s => JSON.stringify(s),
      GB: () => [],
      GC: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      GD: x0 => x0.parentNode,
      GE: x0 => x0.computedStyleMap(),
      GF: x0 => x0.tiltX,
      GG: (d, digits) => d.toFixed(digits),
      GH: (x0,x1) => x0.querySelector(x1),
      GI: () => new MessageChannel(),
      GJ: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      GK: (x0,x1,x2) => x0.sqlite3_extended_result_codes(x1,x2),
      GL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      GM: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      GN: x0 => x0.url,
      GO: (x0,x1) => { x0.height = x1 },
      GP: x0 => x0.target,
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: (a, i) => a.push(i),
      HC: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      HD: x0 => x0.tagName,
      HE: (x0,x1) => x0.get(x1),
      HF: x0 => x0.pointerType,
      HG: x0 => x0.maxHeight,
      HH: (x0,x1) => { x0.title = x1 },
      HI: x0 => new BroadcastChannel(x0),
      HJ: (x0,x1) => { x0.onerror = x1 },
      HK: (x0,x1,x2,x3,x4) => x0.sqlite3_open_v2(x1,x2,x3,x4),
      HL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return wasmFunction(f,arguments.length,x0,x1,x2,x3) }),
      HM: (x0,x1) => { x0.onupgradeneeded = x1 },
      HN: x0 => x0.status,
      HO: (x0,x1) => { x0.width = x1 },
      HP: (x0,x1) => { x0.display = x1 },
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: x0 => new Int8Array(x0),
      IC: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      ID: x0 => x0.target,
      IE: (o, p) => p in o,
      IF: x0 => x0.pointerId,
      IG: x0 => x0.maxWidth,
      IH: (x0,x1) => x0.vibrate(x1),
      II: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      IJ: x0 => new DOMException(x0),
      IK: x0 => x0.sqlite3_initialize(),
      IL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return wasmFunction(f,arguments.length,x0,x1,x2,x3) }),
      IM: x0 => ({autoIncrement: x0}),
      IN: x0 => x0.getReader(),
      IO: x0 => x0.height,
      IP: x0 => x0.style,
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      JC: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      JD: x0 => x0.clientY,
      JE: (x0,x1) => { x0.textContent = x1 },
      JF: x0 => x0.getCoalescedEvents(),
      JG: x0 => x0.minHeight,
      JH: x0 => x0.arrayBuffer(),
      JI: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      JJ: x0 => x0.error,
      JK: (x0,x1,x2,x3) => x0.dart_sqlite3_register_vfs(x1,x2,x3),
      JL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      JM: (x0,x1,x2) => x0.createObjectStore(x1,x2),
      JN: x0 => x0.read(),
      JO: x0 => x0.width,
      JP: (x0,x1) => { x0.accept = x1 },
      K: o => o,
      KB: x0 => new Uint8Array(x0),
      KC: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      KD: x0 => x0.clientX,
      KE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      KF: (x0,x1) => x0.getModifierState(x1),
      KG: x0 => x0.minWidth,
      KH: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      KI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      KJ: (x0,x1) => { x0.onabort = x1 },
      KK: (x0,x1) => globalThis.Atomics.load(x0,x1),
      KL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      KM: x0 => ({unique: x0}),
      KN: x0 => x0.value,
      KO: x0 => x0.rasterEndMilliseconds,
      KP: (x0,x1) => { x0.multiple = x1 },
      L: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      LB: x0 => new Uint8ClampedArray(x0),
      LC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      LD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      LE: x0 => x0.matches,
      LF: s => s.trimLeft(),
      LG: (x0,x1) => x0.removeProperty(x1),
      LH: x0 => x0.status,
      LI: x0 => globalThis.Array.isArray(x0),
      LJ: (x0,x1) => { x0.oncomplete = x1 },
      LK: (x0,x1,x2) => globalThis.Atomics.wait(x0,x1,x2),
      LL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      LM: (x0,x1,x2,x3) => x0.createIndex(x1,x2,x3),
      LN: x0 => x0.done,
      LO: x0 => x0.rasterStartMilliseconds,
      LP: (x0,x1) => { x0.draggable = x1 },
      M: x0 => x0.index,
      MB: x0 => new Int16Array(x0),
      MC: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      MD: x0 => x0.getBoundingClientRect(),
      ME: (x0,x1) => x0.matchMedia(x1),
      MF: s => s.toUpperCase(),
      MG: (x0,x1) => x0.add(x1),
      MH: (x0,x1) => x0.fetch(x1),
      MI: x0 => x0.table,
      MJ: (x0,x1) => x0.objectStore(x1),
      MK: (x0,x1,x2) => globalThis.Atomics.notify(x0,x1,x2),
      ML: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      MM: (x0,x1) => x0.createObjectStore(x1),
      MN: x0 => x0.cancel(),
      MO: x0 => x0.imageBitmaps,
      MP: (x0,x1) => { x0.type = x1 },
      N: o => String(o),
      NB: x0 => new Uint16Array(x0),
      NC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      ND: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      NE: x0 => x0.matches,
      NF: x0 => x0.pop(),
      NG: x0 => x0.data,
      NH: x0 => x0.content,
      NI: x0 => x0.kind,
      NJ: (x0,x1) => x0.sqlite3_get_autocommit(x1),
      NK: (x0,x1,x2) => globalThis.Atomics.store(x0,x1,x2),
      NL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return wasmFunction(f,arguments.length,x0,x1,x2,x3) }),
      NM: x0 => x0.oldVersion,
      NN: x0 => x0.body,
      NO: x0 => x0.canvasKitMaximumSurfaces,
      NP: x0 => x0.length,
      O: o => o === undefined,
      OB: x0 => new Int32Array(x0),
      OC: (x0,x1) => x0.querySelector(x1),
      OD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      OE: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      OF: x0 => x0.flags,
      OG: (x0,x1) => { x0.scrollTop = x1 },
      OH: x0 => x0.document,
      OI: x0 => x0.data,
      OJ: (x0,x1) => x0.sqlite3_finalize(x1),
      OK: (x0,x1,x2) => x0.setInt32(x1,x2),
      OL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return wasmFunction(f,arguments.length,x0,x1,x2,x3) }),
      OM: () => globalThis.indexedDB,
      ON: x0 => x0.headers,
      OO: x0 => x0.hostElement,
      OP: x0 => x0.getReader(),
      P: (x0,x1) => x0.exec(x1),
      PB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      PC: (x0,x1) => x0.item(x1),
      PD: Date.now,
      PE: f => f.dartFunction,
      PF: (a, s) => a.join(s),
      PG: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      PH: () => typeof dartUseDateNowForTicks !== "undefined",
      PI: x0 => x0.close(),
      PJ: (x0,x1) => x0.sqlite3_reset(x1),
      PK: (x0,x1,x2) => x0.setBigInt64(x1,x2),
      PL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      PM: (x0,x1) => ({name: x0,length: x1}),
      PN: x0 => x0.signal,
      PO: x0 => x0.location,
      PP: x0 => x0.value,
      Q: (x0,x1) => { x0.lastIndex = x1 },
      QB: x0 => new Uint32Array(x0),
      QC: x0 => x0.length,
      QD: (handle) => clearTimeout(handle),
      QE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      QF: (x0,x1) => x0.error(x1),
      QG: (x0,x1) => { x0.value = x1 },
      QH: () => Date.now(),
      QI: () => new AbortController(),
      QJ: x0 => x0.buffer,
      QK: x0 => new Worker(x0),
      QL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      QM: (x0,x1) => x0.update(x1),
      QN: (x0,x1) => x0.revokeObjectURL(x1),
      QO: (x0,x1) => x0.getModifierState(x1),
      QP: x0 => x0.done,
      R: o => o,
      RB: x0 => new Float32Array(x0),
      RC: (x0,x1) => x0.querySelectorAll(x1),
      RD: (a, l) => a.length = l,
      RE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      RF: () => globalThis.console,
      RG: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      RH: () => 1000 * performance.now(),
      RI: () => ({}),
      RJ: (x0,x1) => x0.sqlite3_errstr(x1),
      RK: (x0,x1,x2) => new DataView(x0,x1,x2),
      RL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      RM: x0 => x0.name,
      RN: (x0,x1) => { x0.src = x1 },
      RO: x0 => x0.metaKey,
      RP: x0 => x0.read(),
      S: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      SB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      SC: (x0,x1) => x0.getAttribute(x1),
      SD: (x0,x1) => x0.closest(x1),
      SE: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      SF: s => s.trimRight(),
      SG: (x0,x1) => { x0.value = x1 },
      SH: x0 => new Uint8Array(x0),
      SI: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      SJ: (x0,x1) => x0.sqlite3_errmsg(x1),
      SK: () => globalThis.Uint8Array,
      SL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SM: x0 => globalThis.IDBKeyRange.only(x0),
      SN: (x0,x1,x2,x3,x4) => globalThis.createImageBitmap(x0,x1,x2,x3,x4),
      SO: x0 => x0.altKey,
      SP: x0 => x0.body,
      T: o => o instanceof RegExp,
      TB: x0 => new Float64Array(x0),
      TC: x0 => x0.remove(),
      TD: x0 => x0.bottom,
      TE: (o, i) => o[i],
      TF: x0 => x0.blur(),
      TG: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      TH: (x0,x1,x2) => x0.slice(x1,x2),
      TI: (x0,x1,x2,x3) => x0.request(x1,x2,x3),
      TJ: (x0,x1) => x0.sqlite3_error_offset(x1),
      TK: x0 => x0.communicationBuffer,
      TL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      TM: (x0,x1,x2) => x0.put(x1,x2),
      TN: x0 => x0.naturalHeight,
      TO: x0 => x0.ctrlKey,
      TP: (x0,x1) => new OffscreenCanvas(x0,x1),
      U: (string, times) => string.repeat(times),
      UB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      UC: (x0,x1) => x0.appendChild(x1),
      UD: x0 => x0.top,
      UE: o => o.length,
      UF: x0 => x0.button,
      UG: x0 => x0.value,
      UH: (x0,x1) => x0.decode(x1),
      UI: x0 => x0.name,
      UJ: (x0,x1) => x0.sqlite3_extended_errcode(x1),
      UK: () => globalThis.Int32Array,
      UL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      UM: (x0,x1) => x0.getKey(x1),
      UN: x0 => x0.naturalWidth,
      UO: x0 => x0.isComposing,
      UP: x0 => x0.assetBase,
      V: o => o,
      VB: x0 => new ArrayBuffer(x0),
      VC: (x0,x1) => x0.append(x1),
      VD: x0 => x0.right,
      VE: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      VF: x0 => x0.innerHeight,
      VG: x0 => x0.selectionDirection,
      VH: (x0,x1) => x0.adoptText(x1),
      VI: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      VJ: (x0,x1) => x0.sqlite3_step(x1),
      VK: x0 => x0.byteLength,
      VL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      VM: (x0,x1) => x0.delete(x1),
      VN: x0 => x0.decode(),
      VO: x0 => x0.code,
      VP: x0 => x0.loader,
      W: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      WB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      WC: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      WD: x0 => x0.left,
      WE: x0 => x0.language,
      WF: x0 => x0.innerWidth,
      WG: x0 => x0.selectionStart,
      WH: x0 => x0.first(),
      WI: (o, p, v) => o[p] = v,
      WJ: (x0,x1,x2,x3,x4) => x0.dart_sqlite3_bind_blob(x1,x2,x3,x4),
      WK: x0 => x0.synchronizationBuffer,
      WL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      WM: (x0,x1) => x0.put(x1),
      WN: (x0,x1) => { x0.decoding = x1 },
      WO: x0 => x0.repeat,
      WP: () => globalThis._flutter,
      X: x0 => x0.dotAll,
      XB: (x0,x1,x2) => new DataView(x0,x1,x2),
      XC: x0 => x0.style,
      XD: x0 => x0.clientY,
      XE: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      XF: x0 => x0.height,
      XG: x0 => x0.selectionEnd,
      XH: x0 => x0.next(),
      XI: (o,s,v) => o[s] = v,
      XJ: (x0,x1) => x0.dart_sqlite3_malloc(x1),
      XK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      XL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      XM: (x0,x1,x2) => x0.postMessage(x1,x2),
      XN: (x0,x1) => { x0.crossOrigin = x1 },
      XO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      Y: x0 => x0.unicode,
      YB: (o, p) => o[p],
      YC: x0 => x0.debugShowSemanticsNodes,
      YD: x0 => x0.clientX,
      YE: () => globalThis.window.FinalizationRegistry,
      YF: x0 => x0.width,
      YG: x0 => x0.value,
      YH: x0 => x0.current(),
      YI: () => Symbol("jsBoxedDartObjectProperty"),
      YJ: (x0,x1,x2,x3,x4) => x0.dart_sqlite3_bind_text(x1,x2,x3,x4),
      YK: (x0,x1,x2) => x0.postMessage(x1,x2),
      YL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      YM: x0 => x0.randomUUID(),
      YN: (x0,x1) => x0.createObjectURL(x1),
      YO: (x0,x1,x2) => x0.setItem(x1,x2),
      Z: x0 => x0.ignoreCase,
      ZB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      ZC: (x0,x1) => x0.warn(x1),
      ZD: x0 => x0.changedTouches,
      ZE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      ZF: x0 => x0.clientHeight,
      ZG: x0 => x0.selectionDirection,
      ZH: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      ZI: (x0,x1) => x0.call(x1),
      ZJ: (x0,x1,x2,x3) => x0.sqlite3_bind_double(x1,x2,x3),
      ZK: x0 => new SharedArrayBuffer(x0),
      ZL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      ZM: () => globalThis.crypto,
      ZN: x0 => x0.URL,
      ZO: x0 => x0.localStorage,
      a: x0 => x0.multiline,
      aB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      aC: x0 => x0.console,
      aD: x0 => x0.offsetY,
      aE: x0 => new window.FinalizationRegistry(x0),
      aF: x0 => x0.clientWidth,
      aG: x0 => x0.selectionStart,
      aH: x0 => x0.v8BreakIterator,
      aI: x0 => x0.abort(),
      aJ: (x0,x1,x2,x3) => x0.sqlite3_bind_int64(x1,x2,x3),
      aK: (x0,x1,x2,x3) => ({clientVersion: x0,root: x1,synchronizationBuffer: x2,communicationBuffer: x3}),
      aL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return wasmFunction(f,arguments.length,x0,x1,x2,x3,x4) }),
      aM: x0 => x0.port2,
      aN: x0 => new Blob(x0),
      aO: (x0,x1) => x0.removeItem(x1),
      b: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      bB: o => o.byteOffset,
      bC: () => globalThis.window,
      bD: x0 => x0.offsetX,
      bE: (x0,x1) => x0.unregister(x1),
      bF: (x0,x1) => { x0.content = x1 },
      bG: x0 => x0.selectionEnd,
      bH: () => globalThis.Intl,
      bI: x0 => x0.locks,
      bJ: x0 => globalThis.BigInt(x0),
      bK: x0 => x0.close(),
      bL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return wasmFunction(f,arguments.length,x0,x1,x2,x3) }),
      bM: x0 => x0.terminate(),
      bN: (x0,x1,x2,x3,x4) => ({type: x0,data: x1,premultiplyAlpha: x2,colorSpaceConversion: x3,preferAnimation: x4}),
      bO: (x0,x1) => x0.getItem(x1),
      c: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      cB: o => o.buffer,
      cC: (o, c) => o instanceof c,
      cD: x0 => x0.type,
      cE: (x0,x1) => x0.contains(x1),
      cF: (x0,x1) => { x0.name = x1 },
      cG: x0 => x0.keyCode,
      cH: (x0,x1) => x0.segment(x1),
      cI: () => globalThis.navigator,
      cJ: (x0,x1,x2) => x0.sqlite3_bind_null(x1,x2),
      cK: x0 => x0.getSize(),
      cL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return wasmFunction(f,arguments.length,x0,x1,x2,x3) }),
      cM: (x0,x1) => new SharedWorker(x0,x1),
      cN: x0 => new window.ImageDecoder(x0),
      cO: (x0,x1) => x0.key(x1),
      d: (x0,x1) => x0.didCreateEngineInitializer(x1),
      dB: Function.prototype.call.bind(DataView.prototype.getUint8),
      dC: (x0,x1) => x0[x1],
      dD: x0 => x0.maxTouchPoints,
      dE: (s) => +s,
      dF: x0 => x0.head,
      dG: (x0,x1) => x0.scrollIntoView(x1),
      dH: x0 => x0.index,
      dI: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      dJ: (x0,x1) => x0.sqlite3_bind_parameter_count(x1),
      dK: (x0,x1) => x0.truncate(x1),
      dL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3) { return wasmFunction(f,arguments.length,x0,x1,x2,x3) }),
      dM: x0 => x0.start(),
      dN: x0 => x0.name,
      dO: x0 => x0.length,
      e: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      eB: (b, o) => new DataView(b, o),
      eC: x0 => x0.length,
      eD: x0 => x0.platform,
      eE: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      eF: (x0,x1) => x0.removeChild(x1),
      eG: x0 => x0.multiViewEnabled,
      eH: x0 => x0.next(),
      eI: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      eJ: (x0,x1) => x0.sqlite3_stmt_isexplain(x1),
      eK: x0 => ({at: x0}),
      eL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      eM: x0 => x0.port,
      eN: x0 => x0.repetitionCount,
      eO: (x0,x1) => x0.querySelector(x1),
      f: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      fB: (b, o, l) => new DataView(b, o, l),
      fC: (string, token) => string.split(token),
      fD: x0 => x0.body,
      fE: s => s.trim(),
      fF: x0 => x0.firstChild,
      fG: (x0,x1) => x0.replaceWith(x1),
      fH: x0 => x0.value,
      fI: (o, p) => p in o,
      fJ: (x0,x1) => x0.dart_sqlite3_free(x1),
      fK: (x0,x1) => x0.write(x1),
      fL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      fM: (x0,x1) => x0.postMessage(x1),
      fN: x0 => x0.frameCount,
      fO: (x0,x1) => x0.createElement(x1),
      g: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      gB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      gC: o => o instanceof Array,
      gD: () => globalThis.document,
      gE: x0 => x0.classList,
      gF: x0 => x0.viewConstraints,
      gG: (x0,x1) => { x0.type = x1 },
      gH: x0 => x0.done,
      gI: x0 => x0.groups,
      gJ: (x0,x1,x2,x3,x4,x5,x6) => x0.sqlite3_prepare_v3(x1,x2,x3,x4,x5,x6),
      gK: (x0,x1,x2) => x0.write(x1,x2),
      gL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2,x3,x4) { return wasmFunction(f,arguments.length,x0,x1,x2,x3,x4) }),
      gM: (x0,x1) => ({kind: x0,table: x1}),
      gN: x0 => x0.selectedTrack,
      gO: (o, a) => o + a,
      h: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      hB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      hC: (a, i) => a[i],
      hD: (x0,x1,x2) => x0.addEventListener(x1,x2),
      hE: x0 => x0.preventDefault(),
      hF: x0 => x0.hostElement,
      hG: (x0,x1) => { x0.className = x1 },
      hH: (o, m, a) => o[m].apply(o, a),
      hI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      hJ: (x0,x1,x2,x3,x4,x5) => x0.sqlite3_exec(x1,x2,x3,x4,x5),
      hK: x0 => x0.createSyncAccessHandle(),
      hL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      hM: (x0,x1) => x0.sqlite3_changes(x1),
      hN: x0 => x0.completed,
      hO: x0 => x0.children,
      i: x0 => new Promise(x0),
      iB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      iC: a => a.length,
      iD: x0 => x0.hasFocus(),
      iE: x0 => x0.parent,
      iF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      iG: (x0,x1) => { x0.tabIndex = x1 },
      iH: x0 => x0.iterator,
      iI: (x0,x1) => x0.postMessage(x1),
      iJ: (x0,x1,x2) => x0.sqlite3_column_name(x1,x2),
      iK: x0 => ({create: x0}),
      iL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      iM: (x0,x1) => x0.sqlite3_last_insert_rowid(x1),
      iN: x0 => x0.ready,
      iO: (x0,x1) => { x0.id = x1 },
      j: (x0,x1,x2) => x0.call(x1,x2),
      jB: (t, s) => t.set(s),
      jC: (x0,x1) => x0.test(x1),
      jD: x0 => x0.relatedTarget,
      jE: x0 => x0.timeStamp,
      jF: x0 => ({runApp: x0}),
      jG: (x0,x1) => { x0.name = x1 },
      jH: () => globalThis.Symbol,
      jI: x0 => x0.close(),
      jJ: (x0,x1,x2) => x0.sqlite3_column_blob(x1,x2),
      jK: (x0,x1,x2) => x0.getFileHandle(x1,x2),
      jL: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      jM: (a, s, e) => a.splice(s, e),
      jN: x0 => x0.tracks,
      jO: () => globalThis.document,
      k: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      kB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      kC: x0 => x0.userAgent,
      kD: x0 => x0.shiftKey,
      kE: (x0,x1) => x0.hasAttribute(x1),
      kF: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      kG: (x0,x1) => { x0.placeholder = x1 },
      kH: (x0,x1) => new Intl.Segmenter(x0,x1),
      kI: (x0,x1) => ({i: x0,p: x1}),
      kJ: (x0,x1,x2) => x0.sqlite3_column_bytes(x1,x2),
      kK: x0 => ({create: x0}),
      kL: (x0,x1) => x0.getBigInt64(x1),
      kM: (a, l) => a.length = l,
      kN: x0 => x0.close(),
      kO: x0 => ({type: x0}),
      l: x0 => new Array(x0),
      lB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      lC: x0 => x0.navigator,
      lD: (decoder, codeUnits) => decoder.decode(codeUnits),
      lE: x0 => x0.buttons,
      lF: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      lG: (x0,x1) => { x0.autocomplete = x1 },
      lH: x0 => x0.Segmenter,
      lI: () => new Array(),
      lJ: (x0,x1,x2) => x0.sqlite3_column_text(x1,x2),
      lK: (x0,x1,x2) => x0.getDirectoryHandle(x1,x2),
      lL: (x0,x1) => x0.getInt32(x1),
      lM: () => new FileReader(),
      lN: (x0,x1) => ({frameIndex: x0,completeFramesOnly: x1}),
      lO: (x0,x1) => new Blob(x0,x1),
      m: o => [o],
      mB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      mC: Function.prototype.call.bind(String.prototype.toLowerCase),
      mD: () => new TextDecoder("utf-8", {fatal: true}),
      mE: x0 => x0.ctrlKey,
      mF: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      mG: (x0,x1) => { x0.name = x1 },
      mH: x0 => x0.buffer,
      mI: (x0,x1) => ({c: x0,r: x1}),
      mJ: (x0,x1,x2) => x0.sqlite3_column_double(x1,x2),
      mK: (x0,x1) => new URL(x0,x1),
      mL: (x0,x1) => x0.read(x1),
      mM: (x0,x1) => x0.readAsArrayBuffer(x1),
      mN: (x0,x1) => x0.decode(x1),
      mO: x0 => globalThis.URL.createObjectURL(x0),
      n: (o0, o1) => [o0, o1],
      nB: Function.prototype.call.bind(DataView.prototype.getUint32),
      nC: Object.is,
      nD: () => new TextDecoder("utf-8", {fatal: false}),
      nE: x0 => x0.y,
      nF: o => o.byteLength,
      nG: (x0,x1) => { x0.placeholder = x1 },
      nH: x0 => x0.wasmMemory,
      nI: (x0,x1) => { x0.onmessage = x1 },
      nJ: x0 => globalThis.Number(x0),
      nK: x0 => x0.pathname,
      nL: (x0,x1,x2) => x0.read(x1,x2),
      nM: x0 => x0.result,
      nN: x0 => x0.displayHeight,
      nO: x0 => x0.click(),
      o: (o0, o1, o2) => [o0, o1, o2],
      oB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      oC: x0 => x0.vendor,
      oD: (a, i, v) => a[i] = v,
      oE: x0 => x0.x,
      oF: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      oG: (x0,x1) => { x0.action = x1 },
      oH: () => globalThis.window._flutter_skwasmInstance,
      oI: (o, a) => o == a,
      oJ: (x0,x1,x2) => x0.sqlite3_column_int64(x1,x2),
      oK: x0 => x0.getDirectory(),
      oL: x0 => x0.flush(),
      oM: () => new XMLHttpRequest(),
      oN: x0 => x0.displayWidth,
      oO: x0 => globalThis.URL.revokeObjectURL(x0),
      p: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      pB: Function.prototype.call.bind(DataView.prototype.getInt32),
      pC: (x0,x1) => x0.createTextNode(x1),
      pD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      pE: x0 => x0.scrollTop,
      pF: x0 => x0.history,
      pG: (x0,x1) => { x0.method = x1 },
      pH: () => new TextDecoder(),
      pI: (o, t) => typeof o === t,
      pJ: (x0,x1,x2) => x0.sqlite3_column_type(x1,x2),
      pK: x0 => x0.storage,
      pL: () => globalThis.WebAssembly,
      pM: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      pN: x0 => x0.duration,
      pO: (x0,x1) => { x0.download = x1 },
      q: (x0,x1,x2) => { x0[x1] = x2 },
      qB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      qC: (x0,x1) => { x0.id = x1 },
      qD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      qE: x0 => x0.offsetTop,
      qF: x0 => x0.search,
      qG: (x0,x1) => { x0.noValidate = x1 },
      qH: (a, i) => a.splice(i, 1),
      qI: x0 => x0.r,
      qJ: (x0,x1) => x0.sqlite3_column_count(x1),
      qK: () => globalThis.navigator,
      qL: x0 => x0.href,
      qM: x0 => x0.send(),
      qN: x0 => x0.image,
      qO: (x0,x1) => { x0.target = x1 },
      r: (o, p) => o[p],
      rB: o => o instanceof Uint16Array,
      rC: (x0,x1) => { x0.nonce = x1 },
      rD: x0 => x0.visibilityState,
      rE: x0 => x0.scrollLeft,
      rF: x0 => x0.location,
      rG: (x0,x1) => x0.removeAttribute(x1),
      rH: a => a.pop(),
      rI: x0 => x0.c,
      rJ: (x0,x1) => x0.sqlite3_close_v2(x1),
      rK: (x0,x1) => globalThis.fetch(x0,x1),
      rL: (x0,x1) => x0.openCursor(x1),
      rM: x0 => x0.type,
      rN: () => globalThis.window.ImageDecoder,
      rO: (x0,x1) => { x0.href = x1 },
      s: () => globalThis,
      sB: Function.prototype.call.bind(DataView.prototype.getUint16),
      sC: x0 => x0.nonce,
      sD: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      sE: x0 => x0.offsetLeft,
      sF: x0 => x0.pathname,
      sG: x0 => x0.isConnected,
      sH: (map, o, v) => map.set(o, v),
      sI: x0 => x0.p,
      sJ: (x0,x1,x2,x3,x4,x5,x6) => x0.dart_sqlite3_create_function_v2(x1,x2,x3,x4,x5,x6),
      sK: (x0,x1) => x0.sqlite3session_delete(x1),
      sL: x0 => x0.arrayBuffer(),
      sM: x0 => x0.response,
      sN: (x0,x1,x2) => x0.insertBefore(x1,x2),
      sO: (x0,x1,x2) => x0.addEventListener(x1,x2),
      t: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      tB: o => o instanceof Int16Array,
      tC: () => globalThis.window.flutterConfiguration,
      tD: x0 => x0.disconnect(),
      tE: x0 => x0.offsetParent,
      tF: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      tG: x0 => x0.click(),
      tH: (map, o) => map.get(o),
      tI: x0 => x0.i,
      tJ: (x0,x1,x2,x3) => x0.sqlite3_result_error(x1,x2,x3),
      tK: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      tL: () => globalThis.Blob,
      tM: (x0,x1) => { x0.responseType = x1 },
      tN: x0 => x0.id,
      tO: (x0,x1) => x0.removeChild(x1),
      u: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      uB: Function.prototype.call.bind(DataView.prototype.getInt16),
      uC: (x0,x1) => x0.attachShadow(x1),
      uD: x0 => new Intl.Locale(x0),
      uE: (o, p, r) => o.replace(p, () => r),
      uF: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      uG: (x0,x1) => x0.getElementsByClassName(x1),
      uH: () => new WeakMap(),
      uI: x0 => x0.port1,
      uJ: (x0,x1,x2) => x0.sqlite3_result_subtype(x1,x2),
      uK: (x0,x1) => x0.unregister(x1),
      uL: x0 => x0.value,
      uM: x0 => x0.vendor,
      uN: x0 => x0.offsetHeight,
      uO: x0 => x0.firstChild,
      v: (x0,x1) => ({addView: x0,removeView: x1}),
      vB: o => o instanceof Uint8ClampedArray,
      vC: (x0,x1) => x0.createElement(x1),
      vD: x0 => x0.region,
      vE: (o, p, r) => o.replaceAll(p, () => r),
      vF: o => Object.keys(o),
      vG: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      vH: x0 => x0.debugSkipFontRetryDelay,
      vI: (x0,x1) => x0.getRandomValues(x1),
      vJ: (x0,x1,x2,x3,x4) => x0.sqlite3_result_blob64(x1,x2,x3,x4),
      vK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      vL: x0 => x0.key,
      vM: x0 => x0.navigator,
      vN: x0 => x0.offsetWidth,
      vO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      w: (l, r) => l === r,
      wB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      wC: x0 => x0.scale,
      wD: x0 => x0.script,
      wE: x0 => x0.deltaMode,
      wF: x0 => x0.state,
      wG: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      wH: (x0,x1,x2) => x0.set(x1,x2),
      wI: () => globalThis.crypto,
      wJ: (x0,x1,x2,x3,x4) => x0.sqlite3_result_text(x1,x2,x3,x4),
      wK: x0 => new FinalizationRegistry(x0),
      wL: x0 => x0.continue(),
      wM: () => globalThis.window,
      wN: x0 => x0.stopPropagation(),
      wO: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      x: x0 => x0.random(),
      xB: Function.prototype.call.bind(DataView.prototype.setInt32),
      xC: x0 => x0.visualViewport,
      xD: x0 => x0.language,
      xE: x0 => x0.deltaY,
      xF: x0 => x0.hash,
      xG: (x0,x1) => x0.dispatchEvent(x1),
      xH: x0 => x0.fontFallbackBaseUrl,
      xI: l => new DataView(new ArrayBuffer(l)),
      xJ: (x0,x1,x2) => x0.sqlite3_result_double(x1,x2),
      xK: () => globalThis.FinalizationRegistry,
      xL: x0 => x0.error,
      xM: x0 => new Blob(x0),
      xN: x0 => x0.disabled,
      xO: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      y: () => globalThis.Math,
      yB: Function.prototype.call.bind(DataView.prototype.setUint32),
      yC: x0 => x0.devicePixelRatio,
      yD: x0 => x0.languages,
      yE: x0 => x0.deltaX,
      yF: x0 => x0.state,
      yG: (x0,x1) => x0.createEvent(x1),
      yH: (handle) => clearInterval(handle),
      yI: (x0,x1,x2) => x0.transaction(x1,x2),
      yJ: (x0,x1,x2) => x0.sqlite3_result_int64(x1,x2),
      yK: (x0,x1) => x0.sqlite3changeset_finalize(x1),
      yL: x0 => x0.result,
      yM: x0 => globalThis.fetch(x0),
      yN: (x0,x1) => { x0.min = x1 },
      yO: x0 => x0.length,
      z: (x0,x1) => x0.prepend(x1),
      zB: Function.prototype.call.bind(DataView.prototype.setInt16),
      zC: x0 => x0.height,
      zD: (x0,x1) => x0.observe(x1),
      zE: x0 => x0.wheelDeltaY,
      zF: (x0,x1) => x0.go(x1),
      zG: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      zH: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      zI: x0 => x0.close(),
      zJ: (x0,x1) => x0.sqlite3_result_null(x1),
      zK: x0 => x0.exports,
      zL: (x0,x1) => globalThis.IDBKeyRange.bound(x0,x1),
      zM: x0 => x0.arrayBuffer(),
      zN: (x0,x1) => { x0.max = x1 },
      zO: (x0,x1) => x0.item(x1),

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
