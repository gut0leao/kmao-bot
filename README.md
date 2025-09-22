# KMAO Bot (Keep-me Always On Bot)

O **KMAO Bot** é um programa para **Windows 11** que mantém o computador ativo simulando movimentos sutis de mouse e, opcionalmente, pressionando teclas de forma periódica.  
Ele foi inspirado em scripts anteriores feitos em PowerShell, agora evoluindo para uma aplicação nativa para Windows.

---

## 🎯 Objetivo

Evitar bloqueio de tela, suspensão ou ativação do protetor de tela no Windows, mantendo o computador sempre ativo enquanto o KMAO Bot estiver em execução.

---

## ⚙️ Funcionalidades

- Movimenta o **cursor do mouse** dentro de uma pequena área retangular no **centro da tela**.  
- Intervalo de tempo configurável entre os movimentos (ex.: a cada 30s, 1min, 5min).  
- Simulação opcional de **pressões leves de tecla** (ex.: `Shift` ou `Ctrl`).  
- **Botão Iniciar/Parar** para controlar a execução.  
- Fecha de forma limpa, interrompendo automaticamente a simulação.  
- (Opcional) Rodar em **background** com opção de minimizar para a bandeja do sistema.  

---

## 🛠️ Requisitos Técnicos

- Compatível com **Windows 11**.  
- Implementação preferencial em **C# (WinForms ou WPF)**, mas pode ser em outra linguagem adequada para gerar executáveis no Windows.  
- Gerar um **executável instalável (.exe)**.  
- Código deve ser bem estruturado e comentado.  

---

## 🚀 Extras desejáveis

- Ícone do programa com as letras **KMAO** estilizadas.  
- Logs simples (console ou arquivo `.txt`) para depuração.  

---

## 📦 Próximos Passos

1. Implementar a versão inicial em C# com interface simples.  
2. Adicionar opção de configurar intervalo entre os movimentos.  
3. Implementar minimização para a bandeja.  
4. Criar instalador para distribuição.  

---

## 📜 Licença

Este projeto poderá ser publicado sob uma licença open source (a definir, ex.: MIT ou GPL).

---
