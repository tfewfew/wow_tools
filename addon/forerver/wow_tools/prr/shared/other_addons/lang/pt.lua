WoWTools.prr.RegisterSource(function(...)
-- pt.lua -- the texts of the "Other addons" page, Portuguese. Part of the
-- shared/other_addons module: copied with it into every addon of the author.

local ADDON, ns = ...
ns.OtherAddons = ns.OtherAddons or {}
ns.OtherAddons.texts = ns.OtherAddons.texts or {}

ns.OtherAddons.texts.pt = {
    language_name = "Português",
    language = "Idioma",
    title = "Outros addons",
    subtitle = "Mais addons para WoW Forever. Instalados: %d de %d.",
    footer = "Copie um nome e procure-o no CurseForge.",
    copy = "Copiar nome",
    copy_hint = "Ctrl+C para copiar",
    copy_tooltip = "Clique e pressione Ctrl+C para copiar o nome.",
    copied = "Copiado!",
    state = {
        loaded = "Instalado",
        disabled = "Instalado, desativado",
        missing = "Não instalado",
    },
    -- one line on what the addon is
    notes = {
        purple_note = "Notas sobre os jogadores que você encontra: nas placas de nome, nas dicas e no chat.",
        prr = "O que fabrica um item e para que ele é reagente: nas dicas e numa janela de receitas.",
        loot_buddy = "Avisos de saque, um histórico de saque com busca e filtros de saque automático.",
        target_it = "Botões de barra de ações que selecionam o PNJ vivo escolhido mais próximo: primeiro os de missão.",
        simple_buff_tracker = "Seus bônus numa barra de ícones: todos com temporizadores ou só os que faltam. Um clique os repõe.",
    },
    -- its features, one point each
    features = {
        purple_note = {
            "Uma nota sobre qualquer um com um clique: notas prontas ou seu próprio texto",
            "Suas notas sobre as placas de nome, no chat e nas dicas",
            "Um lembrete com som quando um jogador anotado aparece por perto",
            "Uma janela dos jogadores ao seu redor e um histórico de encontros com busca",
            "Compartilhe notas com sua guilda",
            "Cada nota é assinada e datada: cada um dos seus personagens pode ter a sua",
        },
        prr = {
            "\"Fabricado por\" e \"Reagente para\" na dica de cada item",
            "Uma janela de receitas: Alt+clique num item, siga a cadeia de reagentes, favoritos",
            "Planejador: preços da casa de leilões, lucro e o jeito mais barato de evoluir uma profissão",
            "Cerca de 2.500 receitas de WoW Forever incluídas, nada para escanear",
            "A interface em 8 idiomas, os nomes de itens e receitas do seu cliente do jogo",
        },
        loot_buddy = {
            "Avisos de saque animados nas cores da qualidade dos itens",
            "Um histórico de cada item saqueado: quando, onde e de quê; busca e filtros",
            "Filtros de saque automático: deixe o lixo para trás por qualidade, preço de venda, nome ou máscara",
            "Clique do meio num item das bolsas para excluí-lo do saque automático",
            "Um rastreador de bolsas: seus próprios grupos de itens com a quantidade na tela",
            "Jornada do saque: reveja seu saque no mapa da zona, item por item",
        },
        target_it = {
            "Botões no estilo das barras de ações: um clique seleciona o PNJ vivo escolhido mais próximo",
            "Primeiro os inimigos e PNJs das suas missões; busca entre mais de 10.000 PNJs",
            "Uma marca de raide no alvo, uma tecla para cada botão",
            "Alt+clique: um ponto de navegação até o surgimento mais próximo",
            "Lembra os novos PNJs de Forever assim que você os vê",
        },
        simple_buff_tracker = {
            "Seus bônus numa barra de ícones no estilo das barras de ações: com temporizadores ou só os que faltam",
            "Um clique esquerdo repõe um bônus: lança o feitiço, come para Bem Alimentado, aplica óleo na arma",
            "Encantamentos de arma também, até um óleo e Língua de Fogo na mesma arma",
            "Um brilho nos bônus que faltam, três estilos de ícone, qualquer tamanho e direção",
            "Clique direito num bônus da barra para abrir suas configurações",
        },
    },
}
end)
