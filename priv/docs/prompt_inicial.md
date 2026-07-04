Você é um arquiteto e desenvolvedor especialista em Elixir, Phoenix LiveView, Ash Framework, PostgreSQL, sistemas versionados, UX de formulários complexos e integração com IA via OpenAI/Gemini. A implementação vai consistir em commits por fases de implementação.

Quero idealizar e especificar tecnicamente um projeto de serviço de quizzes. O objetivo é criar uma aplicação web/mobile responsiva usando Phoenix LiveView no frontend e Ash Framework no backend/domínio. O projeto será inicialmente um protótipo funcional, com design mínimo, botões arredondados, interface limpa e sem grande profundidade visual, mas com regras de negócio bem modeladas.

A aplicação deve permitir que usuários criem quizzes, publiquem versões, importem quizzes via JSON, respondam quizzes publicamente e vejam correções. O sistema deve suportar usuários logados e participantes anônimos.

O cadastro/login é obrigatório para criar quizzes. Para responder quizzes, o cadastro é opcional. Caso o participante esteja logado, suas tentativas e respostas em andamento são sincronizadas com a conta e podem ser retomadas em outros dispositivos. Caso esteja anônimo, a tentativa fica vinculada a um token de sessão. Se o participante criar conta ou fizer login durante a resposta, a tentativa anônima deve ser associada ao usuário.

Todo quiz publicado possui um link público compartilhável. O criador compartilha esse link conforme quiser. Não é necessário, no protótipo inicial, implementar turmas, convites privados, senha de acesso ou catálogo público.

A área do usuário deve ter duas abas principais: “Quizzes criados” e “Quizzes respondidos”. No topo, deve haver dois botões: “Criar quiz” e “Importar quiz”. A opção “Importar quiz” deve aceitar um JSON contendo tudo que é necessário para criar um quiz conforme a estrutura definida neste projeto. O quiz importado deve entrar como rascunho para revisão antes da publicação.

A criação de quiz deve conter dados básicos: nome, descrição, nota total pré-preenchida com 100, um toggle para permitir notas/pesos desiguais entre questões, uma opção para definir a ordem das questões e uma área para adicionar perguntas.

A configuração de ordem das questões deve permitir três modos: exibir questões em ordem definida, exibir aleatoriamente e exibir em ordenação aleatória definida por IA. A ordenação aleatória por IA não deve chamar IA no momento em que o participante responde. Ela deve usar tags internas geradas previamente por IA no momento da publicação do quiz. A ordenação por IA deve combinar/distribuir perguntas com base nessas tags, evitando agrupar questões semanticamente parecidas em sequência.

A área de criação de perguntas deve ter um botão “+” que abre um modal para adicionar uma pergunta. Cada pergunta deve conter o enunciado, o tipo da pergunta, as opções de resposta quando aplicável, a resposta correta ou referência de correção quando aplicável, a “nota do editor” e o peso da questão.

Os tipos de pergunta são: verdadeiro ou falso, marcar uma alternativa correta, marcar múltiplas corretas e resposta por texto/discursiva.

A “nota do editor” é opcional. Ela deve funcionar como explicação da resposta e também como referência principal para correções por IA quando aplicável. O placeholder do campo deve deixar isso claro. Sugestão de placeholder: “Explique a resposta esperada, o raciocínio correto ou os critérios de avaliação. Este conteúdo será exibido no resultado e poderá ser usado pela IA como referência para corrigir respostas discursivas.”

O campo de peso da questão deve ser numérico. Se não for preenchido, o peso deve ser distribuído automaticamente entre as questões. Esse campo só deve ficar ativo para edição quando o toggle de pesos diferentes estiver ativado. Abaixo dele, deve haver uma descrição explicando que, se o peso não for preenchido, a nota será distribuída automaticamente entre as questões.

A nota total do quiz representa a pontuação máxima. Quando pesos personalizados estiverem desligados, a pontuação deve ser distribuída igualmente entre as questões. Quando estiverem ligados, os pesos definidos devem ser usados para calcular a pontuação final. Mudança de peso não invalida respostas reaproveitadas entre versões, pois o peso afeta apenas o cálculo final da nota, não a compatibilidade da resposta.

A criação do quiz deve salvar automaticamente o tempo todo como rascunho. O quiz só fica disponível publicamente depois de clicar em “Salvar e publicar”. Também deve existir botão “Salvar” e botão “Deletar”. O botão “Salvar” salva o rascunho sem publicar.

No momento da publicação, o sistema deve validar o quiz, congelar a versão publicada e executar a IA para gerar até 4 tags internas para cada questão. Essas tags são internas e não devem aparecer para o criador nem para o participante no protótipo inicial. Elas serão usadas para futura ordenação aleatória por IA.

O sistema deve ter versionamento. Internamente, versões diferentes de um quiz são tratadas como quizzes diferentes para o sistema. Para o usuário, elas aparecem agrupadas como versões diferentes do mesmo quiz. Deve existir uma tela ou área de histórico de versões mostrando as versões publicadas e um changelog simples do que mudou, sem necessidade de diff detalhado. Exemplos: “questão 3 removida”, “questão 4 anulada”, “mudança de peso na questão X”.

Qualquer alteração estrutural relevante em uma questão publicada deve gerar uma nova versão do quiz inteiro. Publicar uma nova versão de uma questão cria uma nova versão do quiz. A versão anterior permanece intacta. Tentativas antigas apontam sempre para a versão específica respondida e nunca são afetadas por versões novas.

O sistema deve preservar compatibilidade de respostas entre versões. Quando o usuário iniciar uma nova tentativa em uma versão mais recente de um quiz já respondido, o sistema deve reaproveitar automaticamente as respostas anteriores de questões compatíveis. Para isso, cada questão deve ter uma identidade estável entre versões e uma assinatura/hash de compatibilidade dos campos que afetam a resposta.

Uma questão é compatível quando sua estrutura de resposta não mudou. Alterações que quebram compatibilidade: mudança no enunciado, mudança no tipo da questão, mudança nas alternativas, mudança em quais alternativas são corretas, mudança na regra de múltiplas corretas, mudança na resposta de referência, mudança na nota do editor quando ela é usada como referência de correção, anulação da questão e remoção da questão.

Alterações que não quebram compatibilidade: mudança de peso, mudança na nota total do quiz, mudança na descrição do quiz, mudança na ordem das perguntas, mudança em metadados internos e mudança nas tags de IA. O peso é uma questão de recálculo ao final da tentativa e não faz parte do fluxo de reaproveitamento.

Quando uma resposta for reaproveitada de uma versão anterior, ela deve aparecer preenchida normalmente, editável como qualquer outra resposta, mas acompanhada de uma pill indicativa, como “Importada da versão anterior”. Se o usuário editar essa resposta, ela passa a ser uma resposta normal da tentativa atual.

O sistema deve permitir anular questão em uma versão publicada. Na edição do quiz deve existir a opção “Anular questão”, que abre um campo de texto para explicar o motivo da anulação. Uma questão anulada permanece visível no resultado com selo de anulada e continua exibindo suas informações normalmente, como enunciado, resposta do participante, resposta correta, nota do editor, correção e motivo da anulação. Porém, no cálculo da nota, uma questão anulada dá a pontuação integral para todos, independentemente da resposta enviada. Mesmo que uma questão anulada seja reimplementada em uma nova versão, a instância antiga permanece anulada para sempre.

Para perguntas de múltiplas corretas, deve existir a opção de nota parcial. A regra é: se o participante marcar qualquer alternativa incorreta, erra a questão inteira e recebe zero naquela questão. Se marcar apenas alternativas corretas, mas não todas as corretas, recebe nota parcial proporcional. Se marcar todas as corretas e nenhuma incorreta, recebe nota total da questão.

Exemplo: uma questão vale 10 pontos e possui 3 alternativas corretas. Se o participante marcar 2 corretas e nenhuma incorreta, recebe 2/3 da pontuação. Se marcar 2 corretas e 1 incorreta, recebe zero. Se marcar as 3 corretas e nenhuma incorreta, recebe 10 pontos.

A área de resposta do quiz deve apresentar 10 perguntas por página, com paginação. A ordem das perguntas deve ser definida no início da tentativa e salva. A ordem não pode mudar a cada renderização. Ela deve ser armazenada como lista fixa associada à tentativa, seja por usuário logado ou token de sessão anônimo.

Em cada pergunta da área de resposta, deve haver o enunciado, a área apropriada para responder, um botão “Marcar para responder depois” e um botão “Não sei a resposta”. O botão “Não sei a resposta” só pode estar ativo se não houver resposta marcada/preenchida. Se houver uma resposta marcada/preenchida, deve aparecer o botão “Limpar respostas”. Ao clicar em limpar, deve aparecer um botão “Restaurar respostas” com contador de 10 segundos até desaparecer. Durante esse tempo, o usuário pode restaurar o que havia respondido.

O estado de cada resposta deve ser salvo enquanto o usuário responde. Para usuários logados, isso deve sincronizar com a conta. Para usuários anônimos, isso deve ficar vinculado ao token de sessão. O usuário pode sair do quiz e voltar depois. Usuário logado pode continuar em outro dispositivo. Usuário anônimo só tem continuidade garantida enquanto mantiver a sessão/token.

Estados importantes por questão: sem resposta, respondida, marcada para responder depois, marcada como “não sei”, limpa com restauração temporária disponível e finalizada. “Não sei a resposta” deve contar como uma resposta final válida com nota zero.

Ao clicar em “Confirmar respostas”, o sistema deve validar todas as páginas. A paginação deve indicar visualmente o status de cada página: verde para página finalizada, amarelo para página com questões marcadas para responder depois e vermelho para página com questões não respondidas. Se uma página tiver tanto questões não respondidas quanto questões marcadas para responder depois, o vermelho tem prioridade.

Após a validação, se houver pendências, o botão deve mudar para algo como “Confirmar mesmo assim”. Ao clicar, deve abrir um modal relatando as falhas, por exemplo quantas questões estão sem resposta e quantas foram marcadas para responder depois. O modal deve ter botão de cancelar e botão de confirmar. Se o usuário confirmar mesmo assim, todas as perguntas não validadas devem ser convertidas para “Não sei a resposta” e a tentativa deve ser finalizada.

Se não houver pendências, o botão deve permitir finalizar diretamente. Depois que uma tentativa for definitivamente confirmada/finalizada, ela nunca mais pode ser editada. O usuário pode iniciar uma nova tentativa do quiz, mas não pode alterar respostas confirmadas de uma tentativa anterior. Não há restrição de quantidade de tentativas por usuário.

Depois da finalização, todas as perguntas ganham uma área de correção que aparece somente ao final do quiz, quando o usuário clicar para conferir/ver resultado. A correção deve aparecer abaixo de cada pergunta.

Para perguntas objetivas, a correção deve exibir a resposta do usuário, a resposta correta, a nota obtida, a nota do editor quando existir e o status da questão. Se a questão estiver anulada, deve exibir selo de anulada, motivo da anulação e pontuação integral concedida.

Para perguntas discursivas, não há necessariamente uma resposta correta objetiva. A correção deve usar a nota do editor como referência principal quando ela existir. A IA deve calcular uma porcentagem de acerto comparando a resposta do participante com a referência do criador. A nota da questão discursiva é calculada multiplicando essa porcentagem pelo peso da questão. Se não houver resposta de referência/nota do editor do criador, a IA deve gerar uma referência própria a partir do enunciado e usar essa referência para calcular a porcentagem. A resposta de referência gerada pela IA pode aparecer como complemento, mas não substitui a referência do criador quando ela existe.

A área de correção de questões discursivas deve incluir a nota do editor, a porcentagem calculada pela IA, a nota obtida e uma área chamada “Nota da Inteligência Artificial”, contendo a explicação da avaliação. Quando a IA gerar uma referência própria por ausência de referência do criador, isso deve ficar claro para o participante.

A aplicação deve suportar integração com OpenAI e Gemini. A arquitetura deve ter uma abstração de provider de IA, evitando acoplamento da regra de negócio a um provider específico. As API keys de OpenAI e Gemini devem ser configuradas por variáveis de ambiente do sistema, não por usuário no protótipo inicial. A camada de IA deve expor operações como gerar tags da questão, corrigir resposta discursiva e gerar referência/nota da IA quando necessário.

No quiz deve existir um campo obrigatório ou fortemente recomendado para o participante preencher: “Como prefere se identificar?”. O dono do quiz nunca deve conhecer o usuário real final. Mesmo que o participante esteja logado, o criador não deve ver nome real, e-mail ou dados da conta. O criador vê apenas a identificação escolhida naquela tentativa.

O criador do quiz deve ter acesso às respostas individuais dos participantes, mas respeitando essa privacidade. Ele deve conseguir abrir uma tentativa e ver exatamente a mesma tela final de respostas que o participante vê ao terminar, porém com os campos desativados/somente leitura. A visualização deve reutilizar a mesma estrutura visual do quiz respondido e corrigido.

Na web, a tela de resultado deve exibir os dados do quiz completo lateralmente, como nota total, percentual, quantidade de respondidas, quantidade de “não sei”, questões anuladas, questões discursivas avaliadas por IA e outras informações úteis. No mobile, esse resumo deve aparecer em uma área com toggle/gaveta fechada na parte de baixo.

O design inicial deve ser mínimo, responsivo para mobile e web, com botões arredondados, boa hierarquia visual, sem excesso de decoração. A prioridade é o fluxo funcional e a clareza dos estados. No mobile, cuidado para não sobrecarregar cada pergunta com botões demais. A correção só deve aparecer após a finalização.

A modelagem sugerida deve considerar recursos/domínios como: usuário, agrupador de quiz, versão de quiz, questão, alternativa, tag interna de IA, tentativa, ordem das questões da tentativa, resposta, correção, anulação e histórico de versão. Em Ash Framework, as ações e policies devem refletir claramente os fluxos de criar rascunho, salvar, publicar, importar JSON, iniciar tentativa, salvar resposta, limpar/restaurar resposta, finalizar tentativa, corrigir tentativa, anular questão, criar nova versão e reaproveitar respostas compatíveis.

Quero que você produza uma especificação técnica organizada para esse projeto, incluindo: visão geral do produto, principais entidades do domínio, relacionamentos, estados, fluxos de usuário, regras de negócio, decisões de UX, estrutura sugerida para JSON de importação, pontos de atenção em Phoenix LiveView, pontos de atenção em Ash Framework, integração com IA, regras de versionamento, regras de reaproveitamento de respostas entre versões e um plano de MVP.

Não simplifique removendo regras importantes. Quando houver ambiguidade, proponha uma decisão técnica consistente com as regras acima e explique brevemente. Priorize uma arquitetura limpa, versionada, auditável e adequada para um protótipo funcional, mas sem criar complexidade desnecessária de produto corporativo.
