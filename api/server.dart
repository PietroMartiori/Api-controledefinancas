import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

const tipos = {'receitas': 'receita', 'despesas': 'despesa'};

int centavos(Object? valor) {
  final partes = RegExp(r'^(\d+)(?:\.(\d{1,2})0*)?$').firstMatch('$valor');
  if (partes != null) {
    final total = int.tryParse(partes[1]! + (partes[2] ?? '').padRight(2, '0'));
    if (total != null && total > 0 && total <= 999999999900) return total;
  }
  throw FormatException(
    'Informe um valor positivo com até duas casas decimais.',
  );
}

Object consultar(Database db, String rota) {
  if (rota == 'categorias')
    return db.select('SELECT * FROM categorias ORDER BY id');
  if (rota == 'saldo') {
    final linha = db
        .select(
          "SELECT COALESCE(SUM(CASE WHEN tipo = 'receita' THEN centavos ELSE -centavos END), 0) AS total FROM lancamentos",
        )
        .single;
    return {'saldo': (linha['total'] as int) / 100};
  }
  return db.select(
    'SELECT id, descricao, categoria_id, centavos / 100.0 AS valor FROM lancamentos WHERE tipo = ? ORDER BY id',
    [tipos[rota]],
  );
}

int cadastrar(Database db, String rota, Map<String, dynamic> dados) {
  if (rota == 'categorias') {
    final nome = dados['nome'];
    if (nome is! String || nome.trim().isEmpty)
      throw FormatException('Informe o nome da categoria.');
    db.execute('INSERT OR IGNORE INTO categorias(nome) VALUES (?)', [
      nome.trim(),
    ]);
    if (db.updatedRows == 0) throw FormatException('Categoria já cadastrada.');
  } else {
    final categoria = dados['categoria_id'];
    if (categoria is! int ||
        db.select('SELECT id FROM categorias WHERE id = ?', [
          categoria,
        ]).isEmpty) {
      throw FormatException('Informe uma categoria cadastrada.');
    }
    final descricao = dados['descricao'] ?? '';
    if (descricao is! String)
      throw FormatException('A descrição deve ser um texto.');
    db.execute(
      'INSERT INTO lancamentos(tipo, categoria_id, descricao, centavos) VALUES (?, ?, ?, ?)',
      [tipos[rota], categoria, descricao.trim(), centavos(dados['valor'])],
    );
  }
  return db.lastInsertRowId;
}

Future<void> atender(Database db, HttpRequest req) async {
  final rota = req.uri.path
      .replaceFirst(RegExp(r'^/'), '')
      .replaceFirst(RegExp(r'/+$'), '');
  final res = req.response;
  res.headers.contentType = ContentType.json;
  try {
    Object resultado;
    if (rota != 'categorias' && rota != 'saldo' && !tipos.containsKey(rota)) {
      res.statusCode = 404;
      resultado = {'erro': 'Rota inexistente.'};
    } else if (req.method == 'GET') {
      resultado = consultar(db, rota);
    } else if (req.method == 'POST' && rota != 'saldo') {
      final bytes = <int>[];
      await for (final bloco in req) {
        if (bytes.length + bloco.length > 65536)
          throw FormatException('Limite de 64 KB por cadastro.');
        bytes.addAll(bloco);
      }
      final dados = jsonDecode(utf8.decode(bytes));
      if (dados is! Map<String, dynamic>)
        throw FormatException('Envie um objeto JSON.');
      resultado = {'id': cadastrar(db, rota, dados)};
      res.statusCode = 201;
    } else {
      res.statusCode = 405;
      resultado = {'erro': 'Método não permitido.'};
    }
    res.write(jsonEncode(resultado));
  } on FormatException catch (erro) {
    res.statusCode = 400;
    res.write(jsonEncode({'erro': erro.message}));
  } catch (erro) {
    stderr.writeln(erro);
    res.statusCode = 500;
    res.write(jsonEncode({'erro': 'Falha interna na API.'}));
  } finally {
    await res.close();
  }
}

Future<void> main() async {
  final db = sqlite3.open(
    Platform.script.resolve('financas.sqlite3').toFilePath(),
  );
  try {
    db.execute('''
      PRAGMA foreign_keys = ON;
      CREATE TABLE IF NOT EXISTS categorias (
        id INTEGER PRIMARY KEY, nome TEXT NOT NULL UNIQUE COLLATE NOCASE
      );
      CREATE TABLE IF NOT EXISTS lancamentos (
        id INTEGER PRIMARY KEY, tipo TEXT NOT NULL,
        categoria_id INTEGER NOT NULL REFERENCES categorias(id),
        descricao TEXT NOT NULL, centavos INTEGER NOT NULL
      );
    ''');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8000);
    print('API em http://127.0.0.1:8000');
    await for (final req in server) {
      atender(db, req);
    }
  } finally {
    db.close();
  }
}
