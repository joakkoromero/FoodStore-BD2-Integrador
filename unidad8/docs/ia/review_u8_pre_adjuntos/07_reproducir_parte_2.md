# tools/reproducir.py - parte 2/2

Fuente íntegra en dos adjuntos. Líneas 521-1039 de 1039; SHA256 completo 9da9103ea3c939f001bca52799d909266f8e2f53109d53c5993aca2905aa7b4c. No falta ninguna línea entre ambas partes.

`````python
            WHERE p.categoria_id = c.id
              AND c.nombre = '{CATEGORY}'
              AND p.nombre = '{name}';
            GET DIAGNOSTICS afectados = ROW_COUNT;
            IF afectados <> 1 THEN
                RAISE EXCEPTION 'Se esperaba modificar un producto fixture';
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM public.producto p
                JOIN public.categoria c ON c.id = p.categoria_id
                WHERE c.nombre = '{CATEGORY}'
                  AND p.nombre = '{name}'
                  AND {expected}
            ) THEN
                RAISE EXCEPTION 'Preparacion administrativa incorrecta';
            END IF;
        END
        $admin$;
        COMMIT;
        """
        pg(COPY, sql, "preparacion administrativa explicita " + kind)
        evidence.setdefault("preparaciones_administrativas", []).append({
            "caso": kind,
            "sql": sql.strip(),
            "origen": "runner administrativo, nunca semaforo.sql",
        })

    def save_evidence():
        evidence["fin_utc"] = datetime.now(timezone.utc).isoformat()
        encoded = json.dumps(evidence, ensure_ascii=True, indent=2)
        json_path.write_text(encoded + "\n", encoding="utf-8")
        # El TXT conserva tambien comandos SQL, estados y motivos completos.
        text_path.write_text(
            "U8 - Evidencia real de reproduccion\n"
            "SIMULADO_APROBADO NO ES UNA VENTA\n"
            "No contiene credenciales ni filas de usuarios.\n\n"
            + encoded + "\n",
            encoding="utf-8",
        )

    try:
        versions = {}
        for tool in executables:
            output = command(tool, ["--version"], "version " + tool).strip()
            match = re.search(r"\b(\d+)\.(\d+)", output)
            require(match is not None and int(match.group(1)) == 17,
                    "Se requieren herramientas cliente PostgreSQL 17")
            versions[tool] = output
        server_version = int(pg(
            SOURCE, "SHOW server_version_num;", "version servidor"
        ).strip())
        require(server_version == 170011, "Se requiere PostgreSQL 17.11")
        versions["server_version_num"] = server_version
        versions["python"] = sys.version.split()[0]
        versions["sqlite"] = sqlite3.sqlite_version
        evidence["versiones"] = versions

        exists = pg(
            SOURCE,
            f"SELECT count(*) FROM pg_database WHERE datname = '{COPY}';",
            "verificar ausencia de destino",
        ).strip()
        require(exists == "0",
                "La base destino ya existe; se aborta sin reemplazarla")

        evidence["fuente_antes"] = fingerprints()

        command(
            "createdb",
            ["-w", "--maintenance-db", SOURCE, "--template", SOURCE, COPY],
            "crear copia nueva desde template foodstore",
        )
        evidence["copia_creada"] = COPY

        dump_path = private / "copia_antes_fixture.dump"
        command(
            "pg_dump",
            ["-w", "--format=custom", "--file", str(dump_path),
             "--dbname", COPY],
            "respaldo privado custom antes de preparar fixture",
        )
        require(dump_path.is_file() and dump_path.stat().st_size > 0,
                "Respaldo vacio o inexistente")
        evidence["respaldo_privado"] = {
            "formato": "custom",
            "bytes": dump_path.stat().st_size,
            "sha256": sha256_file(dump_path),
            "incluido_en_entregables": False,
        }

        # La copia anterior al fixture debe tener las mismas cardinalidades.
        copy_counts = {}
        for table in TABLES:
            copy_counts[table] = int(pg(
                COPY, f"SELECT count(*) FROM public.{table};",
                "conteo copia previa: " + table,
            ).strip())
            require(
                copy_counts[table] == evidence["fuente_antes"][table]["filas"],
                "La copia previa no coincide en cantidad de filas con la fuente",
            )
        evidence["conteos_copia_previa"] = copy_counts

        pg_file(COPY, paths["fixture"], "preparar fixture y vista limitada")
        baseline = validate_copy("baseline copia despues del fixture")
        evidence["copia_baseline"] = baseline
        initial_csv = export_snapshot("snapshot_inicial.csv")

        # Reserva exclusiva: sqlite3.connect no debe reutilizar otra base.
        with database_path.open("xb"):
            pass
        connection = connect_local(database_path)
        run_local_script(connection, paths["schema"], evidence["local"])

        schema_check = {
            "foreign_keys": connection.execute(
                "PRAGMA foreign_keys"
            ).fetchone()[0],
            "integrity_check": connection.execute(
                "PRAGMA integrity_check"
            ).fetchone()[0],
            "tablas": connection.execute(
                """
                SELECT name FROM sqlite_schema
                WHERE type='table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
                """
            ).fetchall(),
            "indice": connection.execute(
                "SELECT sql FROM sqlite_schema WHERE name='uq_cola_sync_pendiente'"
            ).fetchone()[0],
        }
        require(schema_check["integrity_check"] == "ok", "Esquema corrupto")
        require(len(schema_check["tablas"]) == 5, "Se esperaban cinco tablas")
        evidence["esquema"] = schema_check

        import_snapshot(connection, initial_csv, evidence["local"])
        for name, (price, stock) in INITIAL.items():
            row = connection.execute(
                """
                SELECT precio_centavos,stock_visto,eliminado
                FROM producto_cache WHERE nombre=?
                """,
                (name,),
            ).fetchone()
            require(row == (price, stock, 0), "Fixture inicial inesperado")

        # C1 y C7: se ejecutan las sentencias literales del archivo entregado.
        command_count = len(evidence["comandos"])
        run_local_script(
            connection, paths["tests"], evidence["local"], expected_errors=True
        )
        require(len(evidence["comandos"]) == command_count,
                "C1/C7 no deben invocar PostgreSQL")
        evidence["casos"]["C1_C7"] = {
            "archivo_ejecutado": "movil/pruebas_sqlite.sql",
            "comandos_postgresql_durante_prueba": 0,
            "resultado": "aserciones SQL verificadas y errores CHECK/FK reales",
        }

        # Preparar todos estos borradores con el snapshot inicial.
        c2_local, c2_request = create_draft(
            connection, [(NAMES["muzzarella"], 1)]
        )
        _, c3_request = create_draft(
            connection, [(NAMES["empanadas"], 5)]
        )
        _, c4_request = create_draft(
            connection, [(NAMES["agua"], 1)]
        )
        _, c5_request = create_draft(
            connection, [(NAMES["fugazzeta"], 1)]
        )
        _, mixed_request = create_draft(
            connection,
            [(NAMES["agua"], 1), (NAMES["muzzarella"], 1)],
        )
        _, empty_request = create_draft(connection, [])

        # Administracion PostgreSQL separada de la evaluacion SQLite.
        administrative_change("C2")
        c2_csv = export_snapshot("snapshot_c2.csv")
        administrative_change("C4")
        c4_csv = export_snapshot("snapshot_c4.csv")

        # Se conserva y prueba tambien la instantanea intermedia C2.
        import_snapshot(connection, c2_csv, evidence["local"])
        require(connection.execute(
            "SELECT precio_centavos FROM producto_cache WHERE nombre=?",
            (NAMES["muzzarella"],),
        ).fetchone()[0] == 910000, "No se importo el precio C2")
        import_snapshot(connection, c4_csv, evidence["local"])
        with final_csv.open("xb") as stream:
            stream.write(c4_csv.read_bytes())

        # Desde aqui hasta finalizar los casos no se invoca herramienta PG.
        local_phase_commands = len(evidence["comandos"])
        cases = evidence["casos"]
        for label in ("C2", "C3", "C4", "C5", "C6", "bordes"):
            cases[label] = []

        simulate(
            connection, paths["semaforo"], c3_request, "RECHAZADO",
            ["stock insuficiente", "solicitado=5", "disponible=4"], cases["C3"]
        )
        simulate(
            connection, paths["semaforo"], c4_request, "RECHAZADO",
            ["dado de baja"], cases["C4"]
        )
        water_id = connection.execute(
            "SELECT producto_id FROM producto_cache WHERE nombre=?",
            (NAMES["agua"],),
        ).fetchone()[0]
        require(connection.execute(
            "SELECT eliminado FROM producto_cache WHERE producto_id=?",
            (water_id,),
        ).fetchone()[0] == 1, "La lapida no permanece en cache")
        require(connection.execute(
            "SELECT count(*) FROM v_catalogo_disponible WHERE producto_id=?",
            (water_id,),
        ).fetchone()[0] == 0, "La vista no oculta la lapida")
        cases["C4"].append({
            "producto_id": water_id,
            "lapida_en_cache": True,
            "visible_en_catalogo": False,
        })

        simulate(
            connection, paths["semaforo"], c5_request, "SIMULADO_APROBADO",
            ["no es una venta"], cases["C5"]
        )
        c2_original = simulate(
            connection, paths["semaforo"], c2_request, "CONFLICTO",
            ["visto=900000", "servidor=910000"], cases["C2"]
        )

        # Aceptacion sintetica de laboratorio: no declara consentimiento humano.
        accepted_request = str(uuid.uuid4())
        try:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                """
                UPDATE item_borrador
                SET precio_centavos_visto = (
                    SELECT s.precio_centavos FROM snapshot_servidor s
                    WHERE s.producto_id = item_borrador.producto_id
                )
                WHERE id_local = ?
                """,
                (c2_local,),
            )
            connection.execute(
                """
                INSERT INTO cola_sync
                    (solicitud_uuid,id_local,estado,motivo,creada_en)
                VALUES (?,?,'PENDIENTE','',?)
                """,
                (accepted_request, c2_local, FIXED_TIME),
            )
            connection.execute("COMMIT")
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

        simulate(
            connection, paths["semaforo"], accepted_request,
            "SIMULADO_APROBADO", ["no es una venta"], cases["C2"]
        )
        require(request_row(connection, c2_request) == c2_original,
                "Se altero el conflicto historico C2")
        cases["C2"].append({
            "aceptacion": "sintetica de laboratorio, no aprobacion humana",
            "precio_centavos_visto": connection.execute(
                "SELECT precio_centavos_visto FROM item_borrador WHERE id_local=?",
                (c2_local,),
            ).fetchone()[0],
            "uuid_anterior": c2_request,
            "uuid_nuevo": accepted_request,
        })
        require(connection.execute(
            "SELECT count(*) FROM cola_sync WHERE id_local=?", (c2_local,)
        ).fetchone()[0] == 2, "No se conservaron dos solicitudes historicas")

        # C6-PK: el mismo UUID falla por la PRIMARY KEY real.
        expect_integrity(
            connection,
            """
            INSERT INTO cola_sync
                (solicitud_uuid,id_local,estado,motivo,creada_en)
            VALUES (?,?,'PENDIENTE','duplicado',?)
            """,
            (c2_request, c2_local, FIXED_TIME),
            "SQLITE_CONSTRAINT_PRIMARYKEY", cases["C6"],
        )
        require(request_row(connection, c2_request) == c2_original,
                "INSERT duplicado altero C2")

        # C6-semaforo: ninguna fila historica debe cambiar, ni su timestamp.
        historical_before = connection.execute(
            "SELECT * FROM cola_sync ORDER BY solicitud_uuid"
        ).fetchall()
        run_local_script(connection, paths["semaforo"], evidence["local"])
        historical_after = connection.execute(
            "SELECT * FROM cola_sync ORDER BY solicitud_uuid"
        ).fetchall()
        require(historical_before == historical_after,
                "La repeticion reevaluo filas historicas")
        cases["C6"].append({
            "reejecucion_historica_identica": True,
            "incluye_estado_motivo_y_evaluado_en": True,
        })

        # C6-historico: otro CONFLICTO del mismo borrador es legal.
        historical_request = str(uuid.uuid4())
        connection.execute(
            """
            INSERT INTO cola_sync
                (solicitud_uuid,id_local,estado,motivo,creada_en)
            VALUES (?,?,'CONFLICTO','Entrada historica sintetica C6',?)
            """,
            (historical_request, c2_local, FIXED_TIME),
        )
        require(connection.execute(
            "SELECT count(*) FROM cola_sync WHERE id_local=? AND estado='CONFLICTO'",
            (c2_local,),
        ).fetchone()[0] == 2, "Se impuso unicidad global de id_local")
        cases["C6"].append({
            "historico_adicional": request_row(connection, historical_request)
        })

        # Una segunda PENDIENTE falla por el indice parcial.
        pending_local, pending_request = create_draft(
            connection, [(NAMES["fugazzeta"], 1)]
        )
        pending_before = request_row(connection, pending_request)
        expect_integrity(
            connection,
            """
            INSERT INTO cola_sync
                (solicitud_uuid,id_local,estado,motivo,creada_en)
            VALUES (?,?,'PENDIENTE','',?)
            """,
            (str(uuid.uuid4()), pending_local, FIXED_TIME),
            "SQLITE_CONSTRAINT_UNIQUE", cases["bordes"],
        )
        require(request_row(connection, pending_request) == pending_before,
                "Se altero la primera PENDIENTE")

        simulate(
            connection, paths["semaforo"], mixed_request, "RECHAZADO",
            ["dado de baja"], cases["bordes"]
        )
        require(connection.execute(
            """
            SELECT count(*)
            FROM item_borrador i
            JOIN snapshot_servidor s ON s.producto_id=i.producto_id
            WHERE i.id_local=(SELECT id_local FROM cola_sync WHERE solicitud_uuid=?)
              AND i.precio_centavos_visto <> s.precio_centavos
            """,
            (mixed_request,),
        ).fetchone()[0] > 0, "El caso mixto no tenia amarillo")
        simulate(
            connection, paths["semaforo"], empty_request, "RECHAZADO",
            ["borrador vacio"], cases["bordes"]
        )

        # Bordes con alteracion auxiliar local y ROLLBACK: no falsifican un CSV.
        # Permiten probar las ramas no producibles con stock>0 del servidor.
        edge_cases = [
            ("ausente", "DELETE FROM snapshot_servidor WHERE producto_id=?",
             ["ausente de snapshot_servidor"]),
            ("no_disponible",
             "UPDATE snapshot_servidor SET disponible=0 WHERE producto_id=?",
             ["no disponible"]),
            ("sin_stock",
             "UPDATE snapshot_servidor SET stock=0,disponible=0 WHERE producto_id=?",
             ["sin stock"]),
            ("rojo_y_precio_mismo_item",
             "UPDATE snapshot_servidor SET stock=0,disponible=0,"
             "precio_centavos=precio_centavos+1 WHERE producto_id=?",
             ["sin stock"]),
        ]
        # Se usa SAVEPOINT para deshacer el snapshot modificado despues de evaluar.
        # semaforo.sql tiene BEGIN propio: para estos casos se prueba una copia
        # SQLite efimera, sin modificar la base final ni conectar PostgreSQL.
        for label, change_sql, fragments in edge_cases:
            probe = sqlite3.connect(":memory:", isolation_level=None)
            try:
                connection.backup(probe)
                probe.execute("PRAGMA foreign_keys=ON")
                require(probe.execute("PRAGMA foreign_keys").fetchone()[0] == 1,
                        "FK desactivada en conexion de borde")
                _, probe_request = create_draft(
                    probe, [(NAMES["fugazzeta"], 1)]
                )
                probe_id = probe.execute(
                    "SELECT producto_id FROM producto_cache WHERE nombre=?",
                    (NAMES["fugazzeta"],),
                ).fetchone()[0]
                probe.execute(change_sql, (probe_id,))
                record = {"borde": label, "base": "copia efimera en memoria",
                          "alteracion_auxiliar_local": change_sql, "resultado": []}
                simulate(
                    probe, paths["semaforo"], probe_request,
                    "RECHAZADO", fragments, record["resultado"]
                )
                cases["bordes"].append(record)
            finally:
                probe.close()

        require(len(evidence["comandos"]) == local_phase_commands,
                "La fase de semaforo invoco PostgreSQL")
        evidence["fase_semaforo"] = {
            "comandos_postgresql": 0,
            "solo_sqlite": True,
            "snapshot_final": final_csv.name,
        }

        integrity = [row[0] for row in connection.execute("PRAGMA integrity_check")]
        foreign_keys = connection.execute("PRAGMA foreign_key_check").fetchall()
        require(integrity == ["ok"], "integrity_check fallo")
        require(foreign_keys == [], "foreign_key_check encontro violaciones")
        require(connection.execute("PRAGMA foreign_keys").fetchone()[0] == 1,
                "FK desactivadas al final")
        evidence["verificacion_sqlite_final"] = {
            "integrity_check": integrity,
            "foreign_key_check": foreign_keys,
            "foreign_keys": 1,
        }

        cursor = connection.execute(
            "SELECT * FROM cola_sync ORDER BY id_local,solicitud_uuid"
        )
        columns = [d[0] for d in cursor.description]
        evidence["cola_sync_final"] = [
            dict(zip(columns, row)) for row in cursor.fetchall()
        ]
        connection.close()
        connection = None
        evidence["sqlite_final"] = {
            "archivo": str(database_path.relative_to(root)),
            "bytes": database_path.stat().st_size,
            "sha256": sha256_file(database_path),
        }

        # La conexion PostgreSQL se retoma solo para validacion administrativa.
        after = validate_copy("validacion final copia")
        evidence["copia_despues"] = after
        stable_keys = (
            "pedidos", "productos_fixture", "suma_stock", "vector_stock",
            "huella_producto_sin_precio_ni_baja",
        )
        for key in stable_keys:
            require(after[key] == baseline[key],
                    "Cambio prohibido en copia: " + key)

        initial_admin = {
            row["producto_id"]: row for row in baseline["estado_administrativo"]
        }
        final_admin = {
            row["producto_id"]: row for row in after["estado_administrativo"]
        }
        expected_admin = {key: dict(value) for key, value in initial_admin.items()}
        with final_csv.open("r", encoding="utf-8", newline="") as stream:
            exported = list(csv.DictReader(stream))
        by_name = {row["nombre"]: int(row["producto_id"]) for row in exported}
        expected_admin[by_name[NAMES["muzzarella"]]]["precio_centavos"] += 10000
        expected_admin[by_name[NAMES["agua"]]]["eliminado"] = True
        require(final_admin == expected_admin,
                "Precio o baja difiere de la preparacion administrativa prevista")

        evidence["fuente_despues"] = fingerprints()
        require(evidence["fuente_despues"] == evidence["fuente_antes"],
                "La fuente cambio: revisar concurrencia o escrituras externas")
        evidence["conservacion"] = {
            "cinco_tablas_fuente_filas_bytes_sha256_identicos": True,
            "pedidos_copia_identicos": True,
            "vector_stock_copia_identico": True,
            "cambios_administrativos_solo_C2_C4": True,
            "ventas_creadas_por_simulacion": 0,
        }
        evidence["estado"] = "COMPLETADO_CON_VERIFICACIONES"
        save_evidence()
        print("Reproduccion completada; revise docs/evidencias.")
        print("SIMULADO_APROBADO no es una venta.")
        return 0

    except Exception as exc:
        # No se publican mensajes arbitrarios de subprocess ni variables PG.
        evidence["estado"] = "FALLO"
        evidence["fallo"] = {
            "tipo": type(exc).__name__,
            "diagnostico": "Revisar diagnosticos privados y evidencia parcial.",
        }
        (private / "fallo_python.txt").write_text(
            type(exc).__name__ + ": " + str(exc) + "\n", encoding="utf-8"
        )
        if connection is not None:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            connection.close()
        save_evidence()
        print(
            "Reproduccion detenida. No se borraron bases ni salidas parciales. "
            "Revise la evidencia y el directorio privado.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError) as exc:
        # Las comprobaciones previas no incluyen credenciales ni respuestas PG.
        print("No se inicio la reproduccion: " + str(exc), file=sys.stderr)
        raise SystemExit(1)

`````
