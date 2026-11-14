# Compatibilidade 3106

Este diretório contém o backend `bad_query` portado do projeto público [QuinnTang74/3106](https://github.com/QuinnTang74/3106), usado como fallback para a janela verificada do iOS 26.0–26.6.1.

O código permanece sob GPL-3.0-or-later, conforme a licença e os avisos do projeto de origem. O mecanismo original do WQFiles não foi removido: o backend é tentado primeiro somente nessa janela e o `worse_query` existente continua como fallback.

A presença do código não é uma garantia de compatibilidade universal. A operação real depende do build do iOS, do dispositivo, da assinatura e de validação em hardware.
