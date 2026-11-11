import json
import sqlite3
from contextlib import closing
from decimal import Decimal, InvalidOperation
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

BANCO = Path(__file__).with_name("financas.sqlite3")
TIPOS = {"receitas": "receita", "despesas": "despesa"}


def conectar():
    db = sqlite3.connect(BANCO)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    return db


def iniciar_banco():
    with closing(conectar()) as db:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS categorias (
                id INTEGER PRIMARY KEY, nome TEXT NOT NULL UNIQUE COLLATE NOCASE
            );
            CREATE TABLE IF NOT EXISTS lancamentos (
                id INTEGER PRIMARY KEY, tipo TEXT NOT NULL,
                categoria_id INTEGER NOT NULL REFERENCES categorias(id),
                descricao TEXT NOT NULL, centavos INTEGER NOT NULL
            );
        """)


def centavos(valor):
    try:
        numero = Decimal(str(valor))
        if numero.is_finite() and 0 < numero <= 9999999999:
            total = numero * 100
            if total == int(total) and Decimal(int(total)).scaleb(-2) == numero:
                return int(total)
    except InvalidOperation:
        pass
    raise ValueError("Informe um valor positivo com no máximo duas casas decimais.")


def consultar(db, rota):
    if rota == "categorias":
        return [dict(r) for r in db.execute("SELECT * FROM categorias ORDER BY id")]
    if rota == "saldo":
        totais = dict(db.execute("SELECT tipo, SUM(centavos) FROM lancamentos GROUP BY tipo"))
        return {"saldo": (totais.get("receita", 0) - totais.get("despesa", 0)) / 100}
    linhas = db.execute("""
        SELECT id, descricao, categoria_id, centavos / 100.0 AS valor
        FROM lancamentos WHERE tipo = ? ORDER BY id
    """, (TIPOS[rota],))
    return [dict(r) for r in linhas]


def cadastrar(db, rota, dados):
    if rota == "categorias":
        nome = dados.get("nome")
        if not isinstance(nome, str) or not nome.strip():
            raise ValueError("Informe o nome da categoria.")
        try:
            cursor = db.execute("INSERT INTO categorias(nome) VALUES (?)", (nome.strip(),))
        except sqlite3.IntegrityError:
            raise ValueError("Categoria já cadastrada.")
    else:
        categoria = dados.get("categoria_id")
        if type(categoria) is not int or not 0 < categoria < 2**63 or not db.execute(
            "SELECT 1 FROM categorias WHERE id = ?", (categoria,)
        ).fetchone():
            raise ValueError("Informe uma categoria cadastrada.")
        descricao = dados.get("descricao", "")
        if not isinstance(descricao, str):
            raise ValueError("A descrição deve ser um texto.")
        cursor = db.execute("""
            INSERT INTO lancamentos(tipo, categoria_id, descricao, centavos)
            VALUES (?, ?, ?, ?)
        """, (TIPOS[rota], categoria, descricao.strip(), centavos(dados.get("valor"))))
    return {"id": cursor.lastrowid}


class API(BaseHTTPRequestHandler):
    def responder(self, status, dados):
        corpo = json.dumps(dados, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def atender(self):
        rota = urlsplit(self.path).path.rstrip("/").removeprefix("/")
        if rota not in {*TIPOS, "categorias", "saldo"}:
            return self.responder(404, {"erro": "Rota inexistente."})
        try:
            with closing(conectar()) as db, db:
                if self.command == "GET":
                    resultado = consultar(db, rota)
                elif rota == "saldo":
                    return self.responder(405, {"erro": "Use GET para consultar o saldo."})
                else:
                    tamanho = int(self.headers.get("Content-Length", 0))
                    if not 0 < tamanho <= 65536:
                        raise ValueError("Envie um objeto JSON de até 64 KB.")
                    dados = json.loads(self.rfile.read(tamanho), parse_float=Decimal)
                    if not isinstance(dados, dict):
                        raise ValueError("Envie um objeto JSON.")
                    resultado = cadastrar(db, rota, dados)
        except ValueError as erro:
            return self.responder(400, {"erro": str(erro)})
        self.responder(200 if self.command == "GET" else 201, resultado)

    do_GET = atender
    do_POST = atender


if __name__ == "__main__":
    iniciar_banco()
    print("API em http://127.0.0.1:8000", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8000), API).serve_forever()
