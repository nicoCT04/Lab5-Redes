"""Crea la ISO 'CIDATA' (NoCloud) con user-data y meta-data para autoinstall.

En macOS se usa xorriso; en Windows no viene, así que se usa pycdlib (Python puro).
Uso: python -I hacer-seed.py <carpeta-con-user-data> <salida.iso>
"""
import io
import os
import sys

import pycdlib

carpeta, salida = sys.argv[1], sys.argv[2]
iso = pycdlib.PyCdlib()
iso.new(interchange_level=3, joliet=3, rock_ridge="1.09", vol_ident="CIDATA")
for nombre, iso9660 in (("user-data", "/USERDATA.;1"), ("meta-data", "/METADATA.;1")):
    with open(os.path.join(carpeta, nombre), "rb") as f:
        datos = f.read().replace(b"\r\n", b"\n")
    iso.add_fp(io.BytesIO(datos), len(datos), iso9660,
               rr_name=nombre, joliet_path="/" + nombre)
iso.write(salida)
iso.close()
print("seed:", salida)
