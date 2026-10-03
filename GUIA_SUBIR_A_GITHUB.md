# Guía: subir MANUAL IA (Pro) a GitHub desde cero

Repositorio: **https://github.com/alfredjose400/manual-ia-pro** (créalo vacío y privado).

## 1. Crear el repositorio (una sola vez)
1. En GitHub: **+ → New repository**.
2. **Repository name:** `manual-ia-pro` · marca **Private**.
3. **No** marques README, .gitignore ni licencia (ya vienen aquí).
4. **Create repository**.

## 2. Subir el código
Requisito una sola vez: tener **Git** instalado (https://git-scm.com/download/win).

1. Descomprime este zip, por ejemplo en `C:\Proyectos\manual-ia-pro`.
2. Doble clic en **`actualizar_github.bat`**.
3. Si se abre una ventana de GitHub: inicia sesión con **alfredjose400** y pulsa **Authorize**.
4. Si pregunta tu nombre y correo, escríbelos (solo la primera vez).
5. Al final debe decir **«Listo: cambios subidos»**.

**Sin instalar nada (alternativa):** en el repositorio vacío pulsa **uploading an existing file** y arrastra **todo el contenido** de esta carpeta (no la carpeta en sí).
La carpeta oculta `.github` no se ve por defecto: en el Explorador activa *Vista → Mostrar → Elementos ocultos* y arrástrala también.

## 3. El APK
1. Pestaña **Actions** → «Compilar APK» (círculo amarillo = en marcha).
2. En unos 10 minutos, con el check verde, entra a **Releases** → descarga **`manual_ia_pro.apk`**.
3. En el teléfono, ábrelo e instálalo (permite apps de origen desconocido).

**Si sale una ✗ roja:** entra a la ejecución → paso en rojo → copia las últimas líneas y envíaselas a Claude.

## 4. Cambios futuros
Descomprime la versión nueva y vuelve a hacer doble clic en `actualizar_github.bat`. Solo se sube lo que cambió.

## Si dice «Repository not found»
El script borra el acceso viejo y pide iniciar sesión otra vez. Si sigue fallando: menú Inicio → **Administrador de credenciales** → **Credenciales de Windows** → elimina las entradas `git:https://github.com` y vuelve a ejecutar.

## Importante
La clave de firma para Google Play (`.jks`, `key.properties`) nunca se sube: el `.gitignore` ya la excluye. Guarda una copia fuera del repositorio.
