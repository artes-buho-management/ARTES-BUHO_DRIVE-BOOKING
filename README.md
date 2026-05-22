# DRIVE booking@artesbuhomanagement.com

Sistema de organizacion automatica de Google Drive con IA local (sin coste de APIs externas).

## QUE HACE

- Ordena archivos sueltos de `Mi unidad`.
- Usa IA local en tu PC para clasificar.
- Si la IA local no esta disponible, espera y reintenta.
- Evita fallos repetidos en archivos protegidos.
- Guarda logs locales de todo lo que hace.

## MODELO IA RECOMENDADO (NO SATURA PC)

- Modelo por defecto: `qwen3:4b`
- Motivo: buen equilibrio entre consumo y calidad de clasificacion.
- Hardware detectado: 32 GB RAM + RTX 4070 (suficiente para este modelo sin bloquear trabajo normal).

## ESTRUCTURA CREADA EN DRIVE

Carpeta raiz en `Mi unidad`:

- `DRIVE_IA_ORGANIZADOR_BOOKING`

Subcarpetas:

- `01_CLASIFICADOS`
- `02_REVISION_MANUAL`
- `03_ERRORES`
- `99_LOGS`

Categorias:

- `CONTRATOS`
- `FACTURAS`
- `CORREO`
- `AUDIO`
- `VIDEO`
- `IMAGEN`
- `HOJAS`
- `PRESENTACIONES`
- `SCRIPTS`
- `DOCUMENTOS`
- `COMPRIMIDOS`
- `OTROS`

## SCRIPTS PRINCIPALES

- `scripts/drive_ai_organizer.ps1`
  - `bootstrap`: crea estructura.
  - `run-once`: procesa un ciclo.
  - `daemon`: ejecucion continua.

- `scripts/install_drive_ai_startup.ps1`
  - instala arranque automatico en inicio de sesion de Windows.

- `scripts/remove_drive_ai_startup.ps1`
  - quita el arranque automatico.

- `scripts/drive_remote.ps1`
  - utilidades remotas directas para Drive.

## USO RAPIDO

Bootstrap:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\drive_ai_organizer.ps1 -Mode bootstrap -Model "qwen3:4b"
```

Un ciclo manual:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\drive_ai_organizer.ps1 -Mode run-once -Model "qwen3:4b" -MaxFilesPerCycle 25
```

Daemon continuo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\drive_ai_organizer.ps1 -Mode daemon -Model "qwen3:4b" -MaxFilesPerCycle 25 -SleepSeconds 120 -AiRetrySeconds 30
```

Instalar inicio automatico:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_drive_ai_startup.ps1 -Model "qwen3:4b" -MaxFilesPerCycle 25 -SleepSeconds 120 -AiRetrySeconds 30
```

Quitar inicio automatico:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\remove_drive_ai_startup.ps1
```

## MODO ESPERA (PC APAGADO / IA CAIDA)

- Si `Ollama` no responde, el daemon no rompe el flujo.
- Se queda esperando y reintenta cada `AiRetrySeconds`.
- Cuando el PC vuelve y la IA local esta activa, sigue automaticamente.

## LOGS Y ESTADO

- Estado: `config/drive_ai_organizer.state.json`
- Bloqueados por permisos: `config/drive_ai_organizer.blocklist.json`
- Acciones: `logs/drive_ai_actions_YYYYMMDD.jsonl`

## REPOSITORIO

- https://github.com/rubencoton/drive-booking-artesbuhomanagement-com

## BACKUPS SEMANALES CRM (LUNES 14:00)

Regla comun:

- Frecuencia: lunes.
- Hora: 14:00 (hora local).
- Formato nombre: `COPIA SEGURIDAD YYMMDD - 🚀 <NOMBRE_CRM>`.

Backup 1:

- Origen: `https://docs.google.com/spreadsheets/d/REPLACE_WITH_SHEET_ID/edit`
- Destino: `https://drive.google.com/drive/folders/REPLACE_WITH_ID`
- Nombre: `COPIA SEGURIDAD YYMMDD - 🚀 CRM: MARKETING Y PROMOCION`
- Launcher: `CRM_Backup_Marketing.cmd`

Backup 2:

- Origen: `https://docs.google.com/spreadsheets/d/REPLACE_WITH_SHEET_ID/edit`
- Destino: `https://drive.google.com/drive/folders/REPLACE_WITH_ID`
- Nombre: `COPIA SEGURIDAD YYMMDD - 🚀 CRM: OTROS`
- Launcher: `CRM_Backup_Otros.cmd`

Backup 3:

- Origen: `https://docs.google.com/spreadsheets/d/REPLACE_WITH_SHEET_ID/edit`
- Destino: `https://drive.google.com/drive/folders/REPLACE_WITH_ID`
- Nombre: `COPIA SEGURIDAD YYMMDD - 🚀 CRM: FESTIVALES`
- Launcher: `CRM_Backup_Festivales.cmd`

Backup 4:

- Origen: `https://docs.google.com/spreadsheets/d/REPLACE_WITH_SHEET_ID/edit`
- Destino: `https://drive.google.com/drive/folders/REPLACE_WITH_ID`
- Nombre: `COPIA SEGURIDAD YYMMDD - 🚀 CRM: AYUDAS Y SUBVENCIONES`
- Launcher: `CRM_Backup_Ayudas_Subvenciones.cmd`

Backup 5:

- Origen: `https://docs.google.com/spreadsheets/d/REPLACE_WITH_SHEET_ID/edit`
- Destino: `https://drive.google.com/drive/folders/REPLACE_WITH_ID`
- Nombre: `COPIA SEGURIDAD YYMMDD - 🚀 CRM: MUNDO DISCOGRAFICO`
- Launcher: `CRM_Backup_Mundo_Discografico.cmd`

Backup 6:

- Origen: `https://docs.google.com/spreadsheets/d/REPLACE_WITH_SHEET_ID/edit`
- Destino: `https://drive.google.com/drive/folders/REPLACE_WITH_ID`
- Nombre: `COPIA SEGURIDAD YYMMDD - 🚀 CRM: BELLA BESTIA`
- Launcher: `CRM_Backup_Bella_Bestia.cmd`

Backup 7:

- Origen: `https://docs.google.com/spreadsheets/d/REPLACE_WITH_SHEET_ID/edit`
- Destino: `https://drive.google.com/drive/folders/REPLACE_WITH_ID`
- Nombre: `COPIA SEGURIDAD YYMMDD - 🚀 CRM: VENTA-BOOKING`
- Launcher: `CRM_Backup_Venta_Booking.cmd`

Scripts:

- `scripts/crm_backup_scheduler.ps1`
- `scripts/install_crm_backup_startup.ps1`
- `scripts/remove_crm_backup_startup.ps1`

Instalar autoarranque (MARKETING):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_crm_backup_startup.ps1 -SourceFileId "REPLACE_WITH_SHEET_ID" -TargetFolderId "1DPjw4q9YYGgqlxIDvJUEaAdXl4pxEyOY" -SourceDisplayName "CRM: MARKETING Y PROMOCION" -BackupKey "crm_marketing_promocion" -LauncherFileName "CRM_Backup_Marketing.cmd" -RunHour 14 -RunMinute 0
```

Instalar autoarranque (OTROS):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_crm_backup_startup.ps1 -SourceFileId "REPLACE_WITH_SHEET_ID" -TargetFolderId "1_D-6r-fMd3HeQj0cYwrmwyBQBOsct2eh" -SourceDisplayName "CRM: OTROS" -BackupKey "crm_otros" -LauncherFileName "CRM_Backup_Otros.cmd" -RunHour 14 -RunMinute 0
```

Instalar autoarranque (FESTIVALES):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_crm_backup_startup.ps1 -SourceFileId "REPLACE_WITH_SHEET_ID" -TargetFolderId "1PM5IMGYhPgIBBSbvIW_M3R5vNy5_g844" -SourceDisplayName "CRM: FESTIVALES" -BackupKey "crm_festivales" -LauncherFileName "CRM_Backup_Festivales.cmd" -RunHour 14 -RunMinute 0
```

Instalar autoarranque (AYUDAS Y SUBVENCIONES):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_crm_backup_startup.ps1 -SourceFileId "REPLACE_WITH_SHEET_ID" -TargetFolderId "1Eig2NaPWUxmAcji_Rv2pz76maSaCH2cB" -SourceDisplayName "CRM: AYUDAS Y SUBVENCIONES" -BackupKey "crm_ayudas_subvenciones" -LauncherFileName "CRM_Backup_Ayudas_Subvenciones.cmd" -RunHour 14 -RunMinute 0
```

Instalar autoarranque (MUNDO DISCOGRAFICO):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_crm_backup_startup.ps1 -SourceFileId "REPLACE_WITH_SHEET_ID" -TargetFolderId "1QPV0ePkS6uQWYAAN63EjBCSnevT1wBuK" -SourceDisplayName "CRM: MUNDO DISCOGRAFICO" -BackupKey "crm_mundo_discografico" -LauncherFileName "CRM_Backup_Mundo_Discografico.cmd" -RunHour 14 -RunMinute 0
```

Instalar autoarranque (BELLA BESTIA):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_crm_backup_startup.ps1 -SourceFileId "REPLACE_WITH_SHEET_ID" -TargetFolderId "1iggWmRpPhnJslYERSAGVdy5M9TuB0DHb" -SourceDisplayName "CRM: BELLA BESTIA" -BackupKey "crm_bella_bestia" -LauncherFileName "CRM_Backup_Bella_Bestia.cmd" -RunHour 14 -RunMinute 0
```

Instalar autoarranque (VENTA-BOOKING):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_crm_backup_startup.ps1 -SourceFileId "REPLACE_WITH_SHEET_ID" -TargetFolderId "14lLKdArBywo_g5_2GFeSB2GegndEx3uD" -SourceDisplayName "CRM: VENTA-BOOKING" -BackupKey "crm_venta_booking" -LauncherFileName "CRM_Backup_Venta_Booking.cmd" -RunHour 14 -RunMinute 0
```

---

## CIERRE DE ENTORNO LOCAL (MIGRACION)

- Fecha de cierre: 2026-04-08 15:24:45
- Estado: preparado para migrar a nuevo PC/sistema cloud.
- Repositorio: sincronizado con GitHub en la rama activa.
- Nota: este proyecto queda listo para retomar desde otro equipo clonando el repo.

### CHECKLIST RAPIDA

- [x] Codigo versionado en GitHub.
- [x] README actualizado para traspaso.
- [x] Trabajo local preparado para cierre.


<!-- CIERRE_MIGRACION_2026_04_08 -->
## Cierre de migracion (2026-04-08)
- Estado: preparado para mover a nuevo PC/sistema cloud.
- Fecha de cierre: 
2026-04-08 15:25:38 +02:00
- Rama activa: 
main
- Nota: cambios subidos a GitHub para reanudar desde otro entorno.



## CIERRE CLOUD (2026-04-08)

- Estado: repositorio preparado para migracion a nuevo sistema.
- Ultimo cierre tecnico: 2026-04-08 (Europe/Madrid).
- Siguiente uso recomendado: clonar desde GitHub y continuar en la rama actual.


## CIERRE CLOUD 2026-04-08
- Estado: sincronizado para migracion a nuevo PC/sistema.
- Preparado para retomar desde GitHub.
- Ultima revision: 2026-04-08 15:26:05 +02:00

## CIERRE MIGRACION CLOUD

- Fecha: 2026-04-08
- Estado: preparado para retomar desde nuevo sistema


<!-- MIGRACION_CLOUD_START -->
## ESTADO MIGRACION CLOUD
- Revisado: 2026-04-08
- Repo listo para continuar en otro sistema.
- Estado Git al cerrar: sincronizado en GitHub.
<!-- MIGRACION_CLOUD_END -->
