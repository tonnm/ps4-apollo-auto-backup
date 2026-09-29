# AGENTS.md — PS4 Apollo Auto Backup

## 1. Objetivo

Este repositório contém um sistema de backup automático de saves de um PS4 com jailbreak utilizando Apollo Save Tool e um PC Windows.

A implementação atual (V4) já foi testada em uso real e funciona.

Sua tarefa é transformar o projeto atual em um projeto open source genérico, seguro, documentado e fácil de instalar, preservando o comportamento funcional da V4.

O resultado final deve estar pronto para ser publicado diretamente no GitHub.

Não reescreva partes funcionais apenas por preferência estética.

---

## 2. Antes de alterar qualquer arquivo

Primeiro:

1. Leia todos os arquivos existentes no projeto.
2. Entenda completamente o funcionamento atual.
3. Identifique:
   - script de monitoramento;
   - script de backup;
   - arquivos de estado;
   - logs;
   - integração com Apollo;
   - configuração do IP/porta;
   - Scheduled Task;
   - detecção de saves;
   - comparação por hash;
   - estrutura dos backups.
4. Identifique valores específicos do ambiente do desenvolvedor.
5. Identifique dados pessoais ou sensíveis que não devem ser publicados.

Somente depois disso comece a modificar o projeto.

A versão atual funcional deve ser tratada como referência de comportamento.

---

# 3. Comportamento que deve ser preservado

O fluxo atual é aproximadamente:

PS4
→ Apollo Save Tool disponível na rede
→ Monitor detecta Apollo
→ rotina de backup é disparada
→ saves são enumerados
→ saves são comparados com o estado anterior
→ somente saves novos ou modificados precisam gerar novo backup
→ histórico/estado é atualizado
→ logs são gravados.

Preserve esse comportamento.

Não introduza dependências desnecessárias.

O projeto deve continuar funcionando com PowerShell nativo do Windows sempre que possível.

---

# 4. Comparação dos saves

A V4 possui lógica já validada para determinar se um save realmente mudou.

Preserve essa lógica.

Não considere um arquivo diferente apenas porque:

- o ZIP foi recriado;
- timestamps mudaram;
- metadados do arquivo mudaram;
- caminhos temporários do Apollo mudaram;
- identificadores temporários de exportação mudaram.

A comparação deve continuar baseada no conteúdo relevante do save, utilizando SHA-256 conforme a implementação atual.

Se a implementação existente possuir alguma particularidade adicional, preserve-a e documente-a.

Objetivo:

NEW
→ criar backup.

CHANGED
→ criar backup.

UNCHANGED
→ não criar backup redundante.

---

# 5. Remover informações específicas do desenvolvedor

Nenhuma informação específica da máquina original deve permanecer hardcoded.

Procure especialmente por:

- IP do PS4;
- 192.168.x.x;
- usuário do Windows;
- caminhos como C:\Users\...;
- Account ID;
- PSN ID;
- nomes pessoais;
- caminhos absolutos;
- endereço MAC;
- credenciais;
- tokens;
- informações de rede local.

Substitua tudo por configuração genérica.

Antes de concluir, faça uma busca global no repositório procurando possíveis informações pessoais.

---

# 6. Configuração

Crie um mecanismo simples de configuração.

Preferencialmente:

config.json

Exemplo conceitual:

{
"ps4Address": "192.168.1.100",
"apolloPort": 8080,
"backupPath": "%USERPROFILE%\\Documents\\PS4-Saves\\Backups"
}

Adapte os nomes ao funcionamento real encontrado no projeto.

Não invente opções que não tenham utilidade.

O instalador deve criar a configuração.

O usuário não deve precisar editar os scripts manualmente.

---

# 7. Instalador

Criar:

install.ps1

O instalador deve ser amigável para usuários sem conhecimento avançado de PowerShell.

Fluxo esperado:

========================================
PS4 Apollo Auto Backup - Setup
========================================

PS4 IP address:

>

Apollo port [8080]:

>

Backup location [default]:

>

Depois:

- validar os dados;
- criar diretórios necessários;
- gerar config.json;
- instalar/copiar os scripts para localização apropriada;
- criar a Scheduled Task necessária;
- configurar inicialização automática do monitor;
- testar os componentes que puderem ser testados;
- informar claramente o resultado.

Exemplo de saída:

[OK] Configuration created
[OK] Backup directory created
[OK] Scheduled Task created
[OK] Installation completed

Se Apollo não estiver aberto naquele momento, isso NÃO deve necessariamente impedir a instalação.

Nesse caso:

[WARN] Apollo could not be reached.
Installation completed, but connection could not be tested.

Não exija que o PS4 esteja ligado durante a instalação.

---

# 8. Desinstalador

Criar:

uninstall.ps1

Ele deve:

- parar processos/tarefas pertencentes ao projeto quando necessário;
- remover a Scheduled Task criada pelo projeto;
- remover arquivos instalados pelo projeto;
- perguntar antes de apagar backups;
- por padrão PRESERVAR os saves/backups.

Nunca delete backups automaticamente.

---

# 9. Estrutura do repositório

Organize aproximadamente como:

ps4-apollo-auto-backup/
│
├── README.md
├── LICENSE
├── CHANGELOG.md
├── AGENTS.md
├── .gitignore
├── install.ps1
├── uninstall.ps1
│
├── src/
│ ├── Backup-PS4.ps1
│ └── Monitor-PS4.ps1
│
└── docs/
└── troubleshooting.md

Adapte se a estrutura atual justificar alguma diferença.

Não mova arquivos apenas para seguir essa estrutura caso isso complique desnecessariamente o funcionamento.

---

# 10. Dados gerados em runtime

Arquivos gerados durante execução não devem ser commitados.

Adicionar ao .gitignore conforme necessário:

- logs;
- arquivos de estado;
- backups;
- temporários;
- config.json contendo configuração local;
- arquivos baixados/exportados;
- artefatos de teste.

Se necessário, forneça:

config.example.json

Nunca publique o config.json real do desenvolvedor.

---

# 11. Logs

Padronize as mensagens sem destruir informações úteis existentes.

Formato recomendado:

[2026-09-28 21:15:03] [INFO] Apollo detected.
[2026-09-28 21:15:04] [INFO] 19 saves found.
[2026-09-28 21:15:05] [UNCHANGED] CUSA08519
[2026-09-28 21:15:06] [CHANGED] CUSA00001
[2026-09-28 21:15:07] [NEW] CUSA00002
[2026-09-28 21:15:09] [INFO] Backup completed.

Erros devem possuir mensagens úteis para troubleshooting.

Não exponha informações sensíveis desnecessariamente nos logs.

---

# 12. Robustez

Revise especialmente:

- PS4 desligado;
- Apollo fechado;
- timeout;
- mudança de IP;
- pendrive/armazenamento indisponível, se aplicável;
- arquivo de estado inexistente;
- arquivo de estado corrompido;
- diretório de backup inexistente;
- execução simultânea de duas instâncias;
- interrupção durante backup;
- caracteres especiais em nomes;
- permissões do Windows;
- Scheduled Task já existente;
- reinstalação sobre instalação existente.

Uma falha temporária de conexão com o PS4 não deve destruir o estado existente.

Evite condições que possam sobrescrever um backup válido com dados incompletos.

---

# 13. Segurança dos backups

Backup de save é dado importante.

Prefira:

write temp
→ validar
→ mover/renomear para destino final.

Quando aplicável, evite escrever diretamente sobre um backup válido.

Nunca delete o último backup válido devido a falha de rede ou erro de processamento.

---

# 14. README

Criar um README.md completo em inglês.

Pode adicionar uma seção curta em português, mas inglês deve ser a documentação principal.

O README deve conter:

# PS4 Apollo Auto Backup

Descrição curta.

## Features

Explicar:

- automatic save backup;
- Apollo Save Tool integration;
- change detection;
- SHA-256 comparison;
- avoids redundant backups;
- Windows startup monitoring;
- backup history;
- configurable PS4 address;
- configurable backup directory.

Não alegue funcionalidades que o código não possui.

## Requirements

Documentar exatamente os requisitos encontrados no projeto, incluindo:

- Windows;
- PowerShell;
- PS4 jailbreak;
- Apollo Save Tool;
- PS4 e PC na mesma rede, caso seja requisito.

Não invente versões mínimas sem evidência.

## Installation

Objetivo:

1. Download latest release.
2. Extract.
3. Run install.ps1.
4. Enter PS4 IP.
5. Finish.

Inclua instrução para eventual ExecutionPolicy somente se realmente necessária.

## Usage

Explique exatamente o fluxo real.

Por exemplo:

Play
→ save game
→ close/leave game
→ open/use Apollo conforme exigido pela implementação
→ monitor detects availability
→ backup runs.

IMPORTANTE:

Não diga que o sistema detecta automaticamente o fechamento do jogo se isso não for verdade.

Documente exatamente o gatilho que a implementação realmente utiliza.

## Backup structure

Mostre exemplo real.

## How change detection works

Explique resumidamente a estratégia de SHA-256.

## Logs

Informe localização.

## Troubleshooting

Link para docs/troubleshooting.md.

## Uninstall

Explique uninstall.ps1.

## Limitations

Seja transparente.

Explique, por exemplo, qualquer necessidade de abrir Apollo ou executar alguma ação no console.

## Disclaimer

Deixe claro que:

- projeto não é afiliado à Sony;
- projeto não é afiliado ao Apollo Save Tool;
- usuário deve manter backups importantes;
- software é fornecido sem garantia.

Não use logos ou assets proprietários da Sony.

---

# 15. Troubleshooting

Criar:

docs/troubleshooting.md

Cobrir pelo menos:

- Apollo not detected;
- PS4 IP changed;
- firewall;
- port unreachable;
- Scheduled Task not running;
- monitor running but backup does not start;
- backup directory unavailable;
- corrupted state file;
- how to force a backup safely;
- where logs are stored;
- how to completely reset the application's state WITHOUT deleting backups.

Baseie as soluções no funcionamento real do código.

---

# 16. LICENSE

Adicionar uma licença open source apropriada.

Preferência: MIT License.

Não atribua copyright a terceiros.

Utilize o nome do autor somente se ele já estiver claramente definido no projeto; caso contrário, deixe um marcador fácil de substituir antes da publicação.

---

# 17. CHANGELOG

Criar:

CHANGELOG.md

Inicialmente:

## [1.0.0]

### Added

- Apollo monitoring
- automatic backup workflow
- SHA-256 save change detection
- backup history/state
- installer
- uninstaller
- Windows Scheduled Task integration
- documentation

Ajuste a lista para refletir somente funcionalidades realmente existentes.

---

# 18. GitHub

Deixe o projeto preparado para:

git init
git add .
git commit -m "Initial public release"
git branch -M main

Não execute push.

Não configure credenciais.

Não crie remotamente o repositório sem autorização.

---

# 19. Release

Prepare o projeto como versão:

v1.0.0

Se fizer sentido, crie documentação de release contendo:

PS4 Apollo Auto Backup v1.0.0

Initial public release.

Highlights:

- ...
- ...
- ...

Não inclua arquivos runtime no pacote.

---

# 20. Compatibilidade

Preserve compatibilidade com o ambiente PowerShell utilizado atualmente.

Evite adicionar:

- Node.js;
- Python;
- .NET SDK;
- executáveis externos;
- módulos PowerShell de terceiros;

a menos que seja absolutamente necessário.

O objetivo é:

Windows + PowerShell + Apollo

com o mínimo possível de instalação adicional.

---

# 21. Não fazer

Não:

- reescrever a V4 inteira sem necessidade;
- mudar algoritmo funcional apenas por estilo;
- remover tratamento de erros existente sem equivalente melhor;
- adicionar telemetria;
- adicionar analytics;
- enviar qualquer dado pela internet;
- adicionar atualização automática;
- adicionar dependências obscuras;
- armazenar credenciais;
- publicar dados pessoais;
- apagar backups;
- fazer push automaticamente.

---

# 22. Validação obrigatória

Antes de considerar o trabalho concluído:

1. Faça análise sintática de todos os .ps1.
2. Procure referências quebradas após reorganização.
3. Valide config.example.json.
4. Verifique .gitignore.
5. Procure IPs privados hardcoded.
6. Procure caminhos C:\Users hardcoded.
7. Procure nomes/IDs pessoais.
8. Verifique criação da Scheduled Task.
9. Verifique comportamento de reinstalação.
10. Verifique uninstall.
11. Verifique que uninstall preserva backups por padrão.
12. Verifique que erros de rede não destroem o estado.
13. Verifique que duas execuções simultâneas não corrompem backup/estado.
14. Confirme que README descreve o comportamento REAL.

Se algum teste depender de um PS4/Apollo real e não puder ser executado, NÃO simule sucesso.

Marque explicitamente:

NOT TESTED — requires real PS4/Apollo environment.

---

# 23. Relatório final

Ao terminar, não responda apenas "pronto".

Forneça:

## Changes made

Lista resumida.

## Repository structure

Árvore final.

## Tests performed

Para cada teste:

PASS
FAIL
NOT TESTED

## Privacy check

Informe o que foi pesquisado para evitar vazamento de dados pessoais.

## Known limitations

Limitações reais restantes.

## Before publishing

Liste qualquer coisa que o proprietário ainda precise preencher.

## Suggested Git commands

Forneça os comandos necessários para criar o commit inicial, mas NÃO faça push.

---

# Regra principal

A implementação V4 atualmente funcional é a fonte de verdade.

Primeiro entenda.

Depois generalize.

Depois facilite a instalação.

Depois documente.

Não transforme um script funcional em uma arquitetura desnecessariamente complexa.
