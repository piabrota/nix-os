# Fábrica

[English](Factory)

A fábrica de software aberta que fica por trás da piabrota. O [OpenRig](https://github.com/mvschwarz/openrig)
é o motor dela: ele vai automatizar o SDLC (o ciclo de vida do desenvolvimento de software). Esta página
diz o que existe hoje e o que ainda não rodou. O guia completo é
[`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md), em inglês.

## O que é

Um rig, o `piabrota-dev`, com dois seats no `omp`: o `dev-builder` e o `dev-reviewer`. O OpenRig roda
na `piabrota2` como a unidade `openrig` (só no loopback, `MemoryMax=2G`). A interface dele está em
rig.piabrota.art, atrás de basic auth. O Hermes comanda o rig com a CLI `rig` e com a skill
`hermes-rig`. A figura está em [Arquitetura](Arquitetura).

## As etapas

| Etapa | Quem faz | Estado |
|---|---|---|
| Ideia e triagem | O dono, com as skills `/triage` e `/mip` | Hoje |
| Construir | O seat builder | Próximo: o seat ainda não rodou uma tarefa |
| Revisar | O seat reviewer | Próximo: o seat ainda não rodou uma tarefa |
| Pull request | O Hermes, num branch `hermes/*`, em inglês técnico simplificado (ASD-STE100) | Hoje, depois de uma execução do `omp` feita pelo Hermes |
| Merge | Uma pessoa, sempre | Hoje |
| Deploy | O `deploy.yml`: deploy-rs e magic rollback | Hoje |
| Vigiar | O `kvm4-health`, os vigias e a checagem diária das VPSs | Hoje |

## O estado de hoje

- O OpenRig (a versão fixada em `openrig/package.nix`) roda na `piabrota2`, e a interface está ligada.
- O rig está especificado em `openrig/specs/rigs/piabrota-dev/rig.yaml`. Os dois seats rodam sem pedir
  aprovação (`permission_policy: builtin:yolo`, decisão do dono). Eles usam a assinatura do Claude do
  dono.
- O Hermes não sobe seats por cron.
- **Os seats estão parados.** Nenhuma tarefa passou ainda pelo ciclo builder e reviewer.
- Hoje o Hermes faz um pull request rodando o `omp` ele mesmo (skill `hermes-omp`). Depois ele confere o
  diff, faz o commit, faz o push de um branch `hermes/*` e abre o pull request. Uma pessoa faz o merge.
  O merge na `main` faz o deploy.

## Como uma tarefa vai passar

1. O dono dá uma tarefa ao Hermes. O Hermes a escreve como a skill `hermes-omp` manda.
2. O Hermes confere o `kvm4-health` e o `rig status`, sobe o rig (`rig up`) e manda a tarefa ao seat
   builder (`rig send`).
3. O builder escreve e testa a mudança no clone dele. Ele pede ao reviewer que confira o diff (a aresta
   `delegates_to`).
4. O reviewer confere o diff por evidência e responde.
5. O Hermes lê a resposta e confere o diff ele mesmo. Depois ele faz o commit, faz o push de um branch
   `hermes/*` e abre o pull request. Os seats não conseguem fazer push.
6. Uma pessoa revisa e faz o merge. O merge faz o deploy.

Os passos 2 a 5 vão rodar assim. Eles ainda não rodaram.

## As regras que ficam

- Pessoas fazem o merge. Nenhum seat e nenhum agente faz.
- A lista de bloqueio do Hermes e o `hermes/omp.yml` continuam valendo. Um seat não faz push: o
  `omp.yml` nega `git push`, `gh` e `sudo`.
- Nenhum segredo numa spec, numa tarefa ou numa mensagem.
- No máximo dois seats ao mesmo tempo.
- A interface fica atrás de basic auth e TLS. Ela tem um terminal para cada seat: veja
  [Operação](Operacao).

## O que vem depois, e o que não está provado

- **Depois.** Mandar a primeira tarefa de verdade pelo builder e pelo reviewer, e comparar o resultado com
  uma execução do `omp` feita pelo Hermes. Então decidir se o Hermes manda toda tarefa de código ao rig.
- **Não provado.** Uma tarefa pelo ciclo inteiro. As mensagens entre os dois seats. Um pull request que
  parte do diff de um seat.
