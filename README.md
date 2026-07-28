# airlife-wallpaper
Fondo de pantalla corporativo de Airlife para despliegue automatizado.

## Scripts de Pulseway

La carpeta `scripts/` contiene despliegues validados para:

- MPLAB X IDE 6.35.
- MPLAB XC8 C Compiler 4.00.
- FreeCAD 1.1.2.
- Acceso directo público a AutoCAD Web.

Ejecutar `scripts/Install-Airlife-Engineering-Software.ps1` como administrador
o `LocalSystem`. El lanzador descarga los scripts individuales desde este
repositorio, comprueba su SHA-256 y propaga los códigos de salida para Pulseway.

2B Technology V43.3.7 no está incluido hasta contar con su instalador oficial
y parámetros de instalación silenciosa.
