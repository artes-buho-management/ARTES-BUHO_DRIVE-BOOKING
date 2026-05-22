var DRIVE_BOOKING_CONFIG = {
  MAX_REINTENTOS: 5,
  ESPERA_BASE_MS: 600,
  LOCK_TIMEOUT_MS: 30000,
  ROOT_FOLDER_PROPERTY: 'BOOKING_ROOT_FOLDER_ID'
};

function testConexionDrive() {
  return estadoConexionDriveRobusta();
}

function estadoConexionDriveRobusta() {
  return ejecutarConReintento_(function () {
    var root = obtenerCarpetaRaizBooking_();
    var iter = root.getFiles();
    var muestra = [];
    var max = 10;
    var i = 0;

    while (iter.hasNext() && i < max) {
      var f = iter.next();
      muestra.push({
        id: f.getId(),
        nombre: f.getName(),
        url: f.getUrl(),
        tipo: f.getMimeType(),
        actualizado: f.getLastUpdated()
      });
      i++;
    }

    var estado = {
      ok: true,
      carpetaRaizId: root.getId(),
      carpetaRaizNombre: root.getName(),
      muestraArchivos: muestra
    };

    Logger.log(JSON.stringify(estado, null, 2));
    return estado;
  }, 'estadoConexionDriveRobusta');
}

function configurarCarpetaRaizBooking(folderId) {
  return ejecutarConLockYReintento_(function () {
    if (!folderId) {
      throw new Error('Debes enviar folderId.');
    }

    var folder = DriveApp.getFolderById(folderId);
    PropertiesService.getScriptProperties().setProperty(
      DRIVE_BOOKING_CONFIG.ROOT_FOLDER_PROPERTY,
      folder.getId()
    );

    return {
      ok: true,
      carpetaRaizId: folder.getId(),
      carpetaRaizNombre: folder.getName()
    };
  }, 'configurarCarpetaRaizBooking');
}

function asegurarRutaCarpetas(subcarpetas, folderIdOpcional) {
  return ejecutarConLockYReintento_(function () {
    if (!subcarpetas || !subcarpetas.length) {
      throw new Error('Debes enviar un array con nombres de subcarpetas.');
    }

    var actual = folderIdOpcional
      ? DriveApp.getFolderById(folderIdOpcional)
      : obtenerCarpetaRaizBooking_();

    for (var i = 0; i < subcarpetas.length; i++) {
      var nombre = String(subcarpetas[i] || '').trim();
      if (!nombre) {
        throw new Error('Nombre de carpeta vacio en posicion ' + i + '.');
      }
      actual = obtenerOCrearSubcarpeta_(actual, nombre);
    }

    return {
      ok: true,
      carpetaFinalId: actual.getId(),
      carpetaFinalNombre: actual.getName(),
      url: actual.getUrl()
    };
  }, 'asegurarRutaCarpetas');
}

function crearArchivoTextoBooking(nombreArchivo, contenido, folderIdOpcional) {
  return ejecutarConLockYReintento_(function () {
    var nombre = String(nombreArchivo || '').trim();
    if (!nombre) {
      throw new Error('Debes indicar nombreArchivo.');
    }

    var folder = folderIdOpcional
      ? DriveApp.getFolderById(folderIdOpcional)
      : obtenerCarpetaRaizBooking_();

    var contenidoSeguro = contenido == null ? '' : String(contenido);
    var file = folder.createFile(nombre, contenidoSeguro, MimeType.PLAIN_TEXT);

    return {
      ok: true,
      accion: 'create',
      fileId: file.getId(),
      nombre: file.getName(),
      url: file.getUrl(),
      folderId: folder.getId()
    };
  }, 'crearArchivoTextoBooking');
}

function actualizarArchivoTextoBooking(fileId, nuevoContenido) {
  return ejecutarConLockYReintento_(function () {
    if (!fileId) {
      throw new Error('Debes indicar fileId.');
    }

    var file = DriveApp.getFileById(fileId);
    var contenidoSeguro = nuevoContenido == null ? '' : String(nuevoContenido);
    file.setContent(contenidoSeguro);

    return {
      ok: true,
      accion: 'update',
      fileId: file.getId(),
      nombre: file.getName(),
      url: file.getUrl()
    };
  }, 'actualizarArchivoTextoBooking');
}

function moverArchivoBooking(fileId, carpetaDestinoId) {
  return ejecutarConLockYReintento_(function () {
    if (!fileId || !carpetaDestinoId) {
      throw new Error('Debes indicar fileId y carpetaDestinoId.');
    }

    var file = DriveApp.getFileById(fileId);
    var destino = DriveApp.getFolderById(carpetaDestinoId);
    var padres = file.getParents();

    destino.addFile(file);
    while (padres.hasNext()) {
      var p = padres.next();
      if (p.getId() !== destino.getId()) {
        p.removeFile(file);
      }
    }

    return {
      ok: true,
      accion: 'move',
      fileId: file.getId(),
      nombre: file.getName(),
      destinoId: destino.getId(),
      destinoNombre: destino.getName()
    };
  }, 'moverArchivoBooking');
}

function eliminarArchivoBooking(fileId) {
  return ejecutarConLockYReintento_(function () {
    if (!fileId) {
      throw new Error('Debes indicar fileId.');
    }

    var file = DriveApp.getFileById(fileId);
    file.setTrashed(true);

    return {
      ok: true,
      accion: 'trash',
      fileId: file.getId(),
      nombre: file.getName()
    };
  }, 'eliminarArchivoBooking');
}

function leerMetadataArchivoBooking(fileId) {
  return ejecutarConReintento_(function () {
    if (!fileId) {
      throw new Error('Debes indicar fileId.');
    }

    var file = DriveApp.getFileById(fileId);
    return {
      ok: true,
      fileId: file.getId(),
      nombre: file.getName(),
      url: file.getUrl(),
      tipo: file.getMimeType(),
      tamanoBytes: file.getSize(),
      actualizado: file.getLastUpdated()
    };
  }, 'leerMetadataArchivoBooking');
}

function pruebaEscrituraDriveRobusta() {
  return ejecutarConLockYReintento_(function () {
    var nombre = 'probe_booking_' + Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyyMMdd_HHmmss') + '.txt';
    var creado = crearArchivoTextoBooking(nombre, 'OK create ' + new Date().toISOString());
    var actualizado = actualizarArchivoTextoBooking(
      creado.fileId,
      'OK update ' + new Date().toISOString()
    );
    var eliminado = eliminarArchivoBooking(creado.fileId);

    return {
      ok: true,
      create: creado,
      update: actualizado,
      delete: eliminado
    };
  }, 'pruebaEscrituraDriveRobusta');
}

function obtenerCarpetaRaizBooking_() {
  var folderId = PropertiesService.getScriptProperties().getProperty(
    DRIVE_BOOKING_CONFIG.ROOT_FOLDER_PROPERTY
  );

  if (!folderId) {
    return DriveApp.getRootFolder();
  }

  return DriveApp.getFolderById(folderId);
}

function obtenerOCrearSubcarpeta_(folderPadre, nombreSubcarpeta) {
  var iter = folderPadre.getFoldersByName(nombreSubcarpeta);
  if (iter.hasNext()) {
    return iter.next();
  }
  return folderPadre.createFolder(nombreSubcarpeta);
}

function ejecutarConLockYReintento_(fn, etiqueta) {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(DRIVE_BOOKING_CONFIG.LOCK_TIMEOUT_MS)) {
    throw new Error('No se pudo obtener lock de ejecucion. Intenta de nuevo.');
  }

  try {
    return ejecutarConReintento_(fn, etiqueta);
  } finally {
    lock.releaseLock();
  }
}

function ejecutarConReintento_(fn, etiqueta) {
  var intentos = DRIVE_BOOKING_CONFIG.MAX_REINTENTOS;
  var ultimoError = null;

  for (var intento = 1; intento <= intentos; intento++) {
    try {
      return fn();
    } catch (error) {
      ultimoError = error;
      var mensaje = (error && error.message ? error.message : String(error));
      var temporal = esErrorTemporal_(mensaje);
      var ultimoIntento = intento === intentos;

      Logger.log('[%s] intento %s/%s fallo: %s', etiqueta, intento, intentos, mensaje);

      if (!temporal || ultimoIntento) {
        throw error;
      }

      var espera = DRIVE_BOOKING_CONFIG.ESPERA_BASE_MS * Math.pow(2, intento - 1) + Math.floor(Math.random() * 300);
      Utilities.sleep(espera);
    }
  }

  throw ultimoError || new Error('Fallo sin detalle en ' + etiqueta);
}

function esErrorTemporal_(mensaje) {
  var m = String(mensaje || '').toLowerCase();
  var patrones = [
    'rate limit',
    'quota',
    'service invoked too many times',
    'internal error',
    'backend error',
    'timed out',
    'service unavailable',
    'try again later',
    '429',
    '500',
    '503'
  ];

  for (var i = 0; i < patrones.length; i++) {
    if (m.indexOf(patrones[i]) !== -1) {
      return true;
    }
  }

  return false;
}
