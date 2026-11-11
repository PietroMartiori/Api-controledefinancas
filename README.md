# Controle de finanças pessoais

API local em Python 3.10+ com SQLite. Para iniciar a partir da raiz do projeto:

```powershell
python api/server.py
```

O banco é criado automaticamente em `api/financas.sqlite3`. Abra http://127.0.0.1:8000/saldo para consultar o saldo em reais.

| Rota | Método | Corpo JSON para cadastro |
| --- | --- | --- |
| /categorias | GET ou POST | {"nome":"Alimentação"} |
| /receitas | GET ou POST | {"valor":100,"categoria_id":1,"descricao":"Venda"} |
| /despesas | GET ou POST | {"valor":25.99,"categoria_id":1,"descricao":"Almoço"} |
| /saldo | GET | — |

Cadastre uma categoria primeiro e use o id retornado nos lançamentos. GET lista os registros de cada rota. O campo descricao é opcional.

O aplicativo Android fica em `flutter_app/`. Para executá-lo com um emulador aberto ou um celular conectado:

```powershell
cd flutter_app
.\.flutter-sdk\bin\flutter.bat run
```

O SDK local fica fora do Git. Em outro computador com Flutter instalado, use `flutter run` dentro de `flutter_app/`.

No emulador padrão do Android, o endereço da API no computador é http://10.0.2.2:8000.
