"""Complementa a prancha existente com referências das capturas e contratos.

Executar na raiz com Python + reportlab + pypdf. Não consulta rede.
"""
from pathlib import Path
from io import BytesIO
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.lib.utils import simpleSplit
from pypdf import PdfReader, PdfWriter

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'output/pdf/bolsa-facil-wireframe.pdf'
OUT = ROOT / 'output/pdf/bolsa-facil-wireframe-completo.pdf'
W, H = 1190, 842
INK, MUTED, PURPLE, BG = '#172039', '#64748B', '#6558F5', '#F0F1F7'
buf = BytesIO()
c = canvas.Canvas(buf, pagesize=(W, H))
c.setTitle('Bolsa Fácil - Wireframe e mapa de endpoints')
c.setAuthor('Bolsa Fácil')

def box(x,y,w,h,color='#FFFFFF',r=18):
    c.setFillColor(HexColor(color)); c.roundRect(x,H-y-h,w,h,r,fill=1,stroke=0)

def text(x,y,s,size=14,color=INK,bold=False):
    c.setFillColor(HexColor(color)); c.setFont('Helvetica-Bold' if bold else 'Helvetica',size)
    c.drawString(x,H-y-size,s)

def para(x,y,s,width=635,size=15,color=MUTED):
    lines=simpleSplit(s,'Helvetica',size,width)
    for i,line in enumerate(lines): text(x,y+i*(size+8),line,size,color)
    return y+len(lines)*(size+8)

def page(title,sub):
    box(0,0,W,H,'#F7F8FC',0); box(0,0,W,72,INK,0)
    text(40,22,'BOLSA FÁCIL',22,'#FFFFFF',True)
    text(800,27,'WIREFRAME / TELAS E INTEGRAÇÕES',12,'#FFFFFF')
    text(420,108,title,28,INK,True); para(420,153,sub,size=13)
    text(40,807,'30/09/2026 | Dados fictícios | Referência visual + contratos verificados no código',11)

def phone(): box(38,108,340,674,BG,25)
def card(y,h): box(52,y,312,h)
def ptxt(y,s,size=16,color=INK,bold=False): text(68,y,s,size,color,bold)
def nav(selected):
    box(38,711,340,71,'#EFECF5',0)
    for i,name in enumerate(['Início','Favoritas','Carteira','Conta']):
        x=48+i*82
        if i==selected: box(x,722,72,26,'#E4DFF9',13)
        text(x+12,727,['I','*','C','U'][i],14,PURPLE if i==selected else MUTED,True)
        text(x+7,758,name,10,MUTED)

page('10 / Início conforme as prints','Complemento visual das capturas. A página 03 representa a implementação atual.')
phone(); box(54,132,44,44,PURPLE,13); text(65,140,'BF',22,'#FFFFFF',True)
text(109,130,'Bolsa Fácil',24,INK,True); text(109,162,'Invista conhecimento primeiro',11,MUTED)
card(201,47); ptxt(215,'Buscar ação, ex: PETR4',16,MUTED)
box(52,266,312,76,'#EEEBFF',17)
for x,label,value in [(66,'Dólar','R$ 5,18'),(165,'Selic','13,75% a.a.'),(264,'IPCA 12m','4,22%')]:
    text(x,282,label,10,MUTED,True); text(x,304,value,13,INK,True)
ptxt(367,'Ações em destaque',18,INK,True)
for i,(ticker,name,price,variation,positive) in enumerate([
    ('PETR4','Petrobras','49,10','+0,78%',True),('VALE3','Vale S.A.','69,61','-2,18%',False),
    ('ITUB4','Itaú Unibanco','42,30','+1,41%',True)]):
    y=402+i*95; card(y,82); box(65,y+16,42,46,'#F0EFFF',13)
    text(76,y+29,ticker[:2],14,PURPLE,True); text(120,y+15,ticker,17,INK,True)
    text(120,y+46,name,12,MUTED); text(259,y+17,'R$ '+price,14,INK,True)
    text(274,y+46,variation,12,'#087F4B' if positive else '#CB3047',True)
nav(0)
text(420,228,'COTAÇÕES / IMPLEMENTADO',13,PURPLE,True)
box(420,261,720,58,'#EEEBFF'); text(439,280,'GET /api/quote/{ticker}',18,PURPLE,True)
para(420,342,'Carrega uma ação por requisição. Busca usa cache quando disponível; fora do cache, acrescenta range=3mo&interval=1d. Abrir o ativo consulta o histórico novamente.')
text(420,460,'INDICADORES MACRO / SOMENTE NAS PRINTS',13,PURPLE,True)
para(420,493,'Dólar, Selic e IPCA 12m são preservados nesta composição. Não há chamadas, modelos ou widgets correspondentes no código atual. Os números são exemplos visuais, não dados atuais.')
para(420,615,'Endpoint: ainda não definido no projeto. Para implementar, definir provedor, moeda, periodicidade, data de referência e tratamento de indisponibilidade. Esta entrega não adiciona integração ao app.')
c.showPage()

page('11 / Empresa, dividendos e compra','Continuação de detalhes baseada nas prints 05 e 08. Valores apenas ilustrativos.')
phone(); ptxt(129,'<    PETR4',23,INK,True)
card(179,157); ptxt(196,'Saúde da Empresa',18,INK,True)
for x,y,label,value in [(69,235,'P/L','5,22'),(172,235,'P/VP','1,32'),(269,235,'Margem','24,4%'),(69,287,'V. Mercado','663,1 bi'),(172,287,'Dívida','676,3 bi'),(269,287,'Caixa','53,8 bi')]:
    text(x,y,label,10,MUTED); text(x,y+18,value,13,INK,True)
card(351,158); ptxt(370,'Dividendos',18,INK,True); ptxt(404,'Dividend Yield: 7,00%',15,INK,True)
para(68,438,'Com R$ 1.000, projeção ilustrativa de R$ 70 em proventos nos próximos 12 meses.',275,12)
card(526,242); ptxt(543,'Compra simulada',18,INK,True); ptxt(580,'Quantidade: 1',14)
box(68,611,280,61,'#EEEBFF',16); ptxt(620,'Cotação: R$ 49,10',11,MUTED); ptxt(640,'Total: R$ 49,10',18,INK,True)
box(68,689,280,43,'#5D568D',22); text(152,701,'Comprar agora',14,'#FFFFFF',True)
ptxt(742,'Simulação educacional - sem ordem real.',10,MUTED)
text(420,220,'DADOS DA EMPRESA',13,PURPLE,True)
para(420,255,'O modelo atual consome marketCap e currency, exibidos na página 04. P/L, P/VP, margem, dívida, caixa e dividend yield não são consumidos pelo modelo Stock nem exibidos na tela atual.')
text(420,386,'DIVIDENDOS / INTEGRAÇÃO PENDENTE',13,PURPLE,True)
para(420,420,'Não existe endpoint implementado para esses blocos. O desenho preserva a referência enviada; o contrato com um provedor deve ser definido antes da implementação. A projeção ilustrativa é investimento x DY e não garante pagamentos futuros.')
text(420,562,'COMPRA / IMPLEMENTADO LOCALMENTE',13,PURPLE,True)
box(420,595,720,55,'#EEEBFF'); text(439,613,'AppState.buy(symbol, quantity, price)',17,PURPLE,True)
para(420,675,'Grava a posição no SQLite e recalcula o preço médio ponderado. Quantidade inválida desativa a compra. Exibe confirmação após salvar. Não há endpoint de ordens.')
c.showPage()

page('12 / Mapa de navegação','Fluxos para implementação e revisão. Todas as telas usam exemplos fictícios.')
text(52,132,'Percurso principal',22,INK,True)
for i,s in enumerate(['Entrar / Criar conta','Início / Buscar ticker','Detalhes / Histórico','Compra simulada','Carteira / Editar posição','Conta / Sair']):
    box(52,184+i*83,310,58,'#EEEBFF',15); text(71,201+i*83,f'{i+1:02d}   {s}',15,PURPLE,True)
text(420,234,'NAVEGAÇÃO',13,PURPLE,True)
para(420,268,'Login e cadastro levam ao Início após autenticação local. As abas Início, Favoritas, Carteira e Conta compartilham a navegação inferior. Tocar numa ação abre detalhes; voltar retorna à tela de origem.')
para(420,382,'Favoritar grava por conta, sem HTTP. Compra adiciona ou acumula uma posição. Carteira permite adicionar, editar e remover posições. Sair limpa a sessão e retorna à autenticação.')
text(420,503,'ESTADOS A REVISAR',13,PURPLE,True)
para(420,536,'Carga inicial e histórico: indicador de progresso. Falha inicial: mensagem e Tentar novamente. Favoritas/carteira vazias: orientação. Autenticação: validação e erro. Compra: envio desativado durante gravação e mensagem de sucesso.')
para(420,673,'As páginas 01-09 reutilizam a prancha existente no repositório. As páginas 10-11 acrescentam os blocos presentes nas prints e distinguem o que ainda não foi implementado.')
c.showPage()

page('13 / Contrato de consulta','Mapa extraído do serviço, estado, modelo e proxy locais. Não houve consulta de mercado.')
text(52,219,'BASES',14,PURPLE,True)
para(52,253,'Web: http://localhost:8081/api',330,14)
para(52,318,'Nativo / upstream: https://brapi.dev/api',330,14)
para(52,396,'BRAPI_BASE_URL pode substituir a base. Web usa proxy local; credencial adicionada no servidor. Não colocar token no protótipo.',330,14)
text(52,567,'FONTES NO REPOSITÓRIO',13,PURPLE,True)
for i,s in enumerate(['lib/services/brapi_service.dart','lib/state/app_state.dart','lib/models/stock.dart','lib/database/app_database.dart','tool/brapi_proxy.dart']): text(52,602+i*26,s,12,MUTED)
text(420,225,'REQUISIÇÕES GET',13,PURPLE,True)
for i,s in enumerate(['/quote/PETR4','/quote/PETR4?range=5d&interval=1d','/quote/PETR4?range=1mo&interval=1d','/quote/PETR4?range=3mo&interval=1d','/quote/PETR4?range=1y&interval=1d']):
    text(420,258+i*29,s,16,INK,True)
para(420,420,'Caminhos relativos à base acima. A resposta contém results[]. O cliente usa a primeira ação retornada por consulta individual.',size=14)
text(420,501,'CAMPOS CONSUMIDOS',13,PURPLE,True)
para(420,535,'symbol; longName ou shortName; regularMarketPrice; regularMarketChangePercent; logourl; currency; marketCap; historicalDataPrice[].date e .close.',size=14)
para(420,621,'date: timestamp Unix em segundos. Fechamentos não positivos são filtrados. Falta de marketCap exibe ausência. Atualização reúne oito tickers padrão, favoritas e carteira, sem duplicatas.',size=14)
para(420,713,'Login, cadastro, perfil, favoritas e carteira são locais. Não existem endpoints HTTP de autenticação ou ordens no projeto.',size=14)
c.showPage(); c.save()

writer=PdfWriter()
for reader in [PdfReader(BASE),PdfReader(buf)]:
    for p in reader.pages:
        n=len(writer.pages)+1
        footer=BytesIO()
        pw,ph=float(p.mediabox.width),float(p.mediabox.height)
        stamp=canvas.Canvas(footer,pagesize=(pw,ph))
        stamp.setFillColor(HexColor('#F7F8FC'))
        stamp.rect(pw-112,8,100,28,fill=1,stroke=0)
        stamp.setFillColor(HexColor(MUTED)); stamp.setFont('Helvetica',10)
        stamp.drawRightString(pw-38,18,f'{n} / 13')
        stamp.save(); p.merge_page(PdfReader(footer).pages[0])
        writer.add_page(p)
writer.add_metadata({'/Title':'Bolsa Fácil - Wireframe de alta fidelidade e endpoints'})
with OUT.open('wb') as f: writer.write(f)
check=PdfReader(OUT)
assert len(check.pages)==13
content='\n'.join(p.extract_text() for p in check.pages)
for term in ['range=5d','range=1mo','range=3mo','range=1y','Dividendos','IPCA','historicalDataPrice']:
    assert term in content,term
print(f'PASS: {len(check.pages)} páginas; telas, referências e contratos presentes. {OUT}')
