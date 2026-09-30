"""PDF independente, com desenho vetorial e integrações por tela. Sem rede."""
from pathlib import Path
import math
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
from reportlab.lib.utils import simpleSplit
from pypdf import PdfReader
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/pdf/bolsa-facil-wireframe-completo.pdf'
REG,BOLD='Helvetica','Helvetica-Bold'
if Path('C:/Windows/Fonts/segoeui.ttf').exists():
    pdfmetrics.registerFont(TTFont('UI','C:/Windows/Fonts/segoeui.ttf'))
    pdfmetrics.registerFont(TTFont('UIBold','C:/Windows/Fonts/segoeuib.ttf'))
    REG,BOLD='UI','UIBold'
W,H=1120,840
INK,MUTED,PURPLE='#252338','#777582','#6554C0'
BG,SOFT,LINE='#F5F4F7','#EEEBF7','#E5E3EA'
GREEN,RED='#23765B','#B14C59'
c=canvas.Canvas(str(OUT),pagesize=(W,H),pageCompression=1)
c.setTitle('Bolsa Fácil | Telas e integrações'); c.setAuthor('Bolsa Fácil')
OX,OY,S=0,0,1
def origin(x=0,y=0,s=1):
    global OX,OY,S
    OX,OY,S=x,y,s
def pt(x,y): return OX+S*x,H-OY-S*y
def box(x,y,w,h,color='#FFFFFF',r=18,stroke=None):
    c.setFillColor(HexColor(color)); c.setStrokeColor(HexColor(stroke or color)); c.setLineWidth(.8*S)
    c.roundRect(*pt(x,y+h),w*S,h*S,r*S,fill=1,stroke=bool(stroke))
def text(x,y,s,size=14,color=INK,bold=False):
    c.setFillColor(HexColor(color)); c.setFont(BOLD if bold else REG,size*S); c.drawString(*pt(x,y+size),s)
def right(x,y,s,size=14,color=INK,bold=False):
    c.setFillColor(HexColor(color)); c.setFont(BOLD if bold else REG,size*S); c.drawRightString(*pt(x,y+size),s)
def para(x,y,s,width,size=14,color=MUTED):
    lines=simpleSplit(s,REG,size,width)
    for i,t in enumerate(lines): text(x,y+i*(size+7),t,size,color)
    return y+len(lines)*(size+7)
def line(points,color=LINE,width=1):
    c.setStrokeColor(HexColor(color)); c.setLineWidth(width*S); c.setLineCap(1); c.setLineJoin(1)
    p=c.beginPath(); p.moveTo(*pt(*points[0]))
    for pair in points[1:]: p.lineTo(*pt(*pair))
    c.drawPath(p)
def circle(x,y,r,color):
    c.setFillColor(HexColor(color)); c.circle(*pt(x,y),r*S,fill=1,stroke=0)
def icon(x,y,kind,color=MUTED,size=20):
    if kind=='star':
        points=[]
        for i in range(11):
            a=-math.pi/2+i*math.pi/5; r=size*(.48 if i%2==0 else .22)
            points.append((x+size/2+r*math.cos(a),y+size/2+r*math.sin(a)))
        if color=='#AD8439':
            p=c.beginPath(); p.moveTo(*pt(*points[0]))
            for pair in points[1:]: p.lineTo(*pt(*pair))
            p.close(); c.setFillColor(HexColor(color)); c.drawPath(p,fill=1,stroke=0)
        else: line(points,color,1.5)
    elif kind=='search':
        c.setStrokeColor(HexColor(color)); c.setLineWidth(1.8*S); c.circle(*pt(x+8,y+8),7*S,stroke=1,fill=0)
        line([(x+13,y+13),(x+20,y+20)],color,1.8)
    elif kind=='chart':
        line([(x+2,y+17),(x+8,y+10),(x+13,y+13),(x+20,y+4)],color,1.8)
        line([(x+14,y+4),(x+20,y+4),(x+20,y+10)],color,1.8)
    elif kind=='wallet':
        line([(x+20,y+4),(x+2,y+4),(x+2,y+19),(x+20,y+19),(x+20,y+4)],color,1.6)
        line([(x+20,y+9),(x+13,y+9),(x+13,y+15),(x+20,y+15)],color,1.6)
    elif kind=='user':
        c.setStrokeColor(HexColor(color)); c.setLineWidth(1.6*S); c.circle(*pt(x+11,y+5),4*S,fill=0,stroke=1)
        line([(x+3,y+19),(x+3,y+17),(x+7,y+13),(x+15,y+13),(x+19,y+17),(x+19,y+19),(x+3,y+19)],color,1.6)
    elif kind=='back': line([(x+15,y+2),(x+5,y+11),(x+15,y+20)],color,1.8)
    elif kind=='arrow': line([(x+5,y+3),(x+13,y+11),(x+5,y+19)],color,1.5)
    elif kind=='eye':
        line([(x,y+10),(x+5,y+5),(x+15,y+5),(x+20,y+10),(x+15,y+15),(x+5,y+15),(x,y+10)],color,1.3)
        circle(x+10,y+10,2.5,color)
def tag(x,y,n):
    circle(x,y,11,PURPLE); text(x-4,y-9,str(n),12,'#FFFFFF',True)
def button(y,label):
    box(24,y,342,52,PURPLE,15); tw=pdfmetrics.stringWidth(label,BOLD,15)
    text((390-tw)/2,y+15,label,15,'#FFFFFF',True)
def field(y,label,value,eye=False):
    text(25,y,label,12,MUTED); box(24,y+26,342,53,'#FFFFFF',13,LINE); text(40,y+41,value,15)
    if eye: icon(330,y+43,'eye')
def nav(active):
    box(1,699,388,80,'#FFFFFF',24); line([(20,699),(370,699)])
    for i,(label,kind) in enumerate(zip(['Início','Favoritas','Carteira','Conta'],['chart','star','wallet','user'])):
        x=24+i*96
        if i==active: box(x,708,55,33,SOFT,13)
        icon(x+17,715,kind,PURPLE if i==active else MUTED)
        text(x+8,747,label,11,PURPLE if i==active else MUTED,i==active)
def tile(y,ticker,name,price,change,positive=True,star=False):
    box(24,y,342,86,'#FFFFFF',18); box(39,y+20,44,44,SOFT,13)
    text(48,y+32,ticker[:2],14,PURPLE,True); text(96,y+17,ticker,17,INK,True); text(96,y+46,name,11,MUTED)
    right(326 if not star else 315,y+18,'R$ '+price,16,INK,True)
    right(326 if not star else 315,y+46,change,12,GREEN if positive else RED,True)
    if star: icon(335,y+31,'star','#AD8439' if star is True else MUTED,17)
def shell(title):
    origin(); box(0,0,W,H,'#FAF9FB',0); text(55,28,'Bolsa Fácil',17,INK,True)
    right(1064,32,'DESIGN / 30.09.2026',10,MUTED); line([(55,68),(1065,68)])
    text(483,114,title,32,INK,True); text(483,166,'TELA E INTEGRAÇÕES',10,PURPLE,True)
    text(55,807,'Estudo visual · dados ilustrativos · compra educacional',10,MUTED)
    right(1065,807,f'{c.getPageNumber():02d} / 09',10,MUTED)
    box(61,99,353,697,'#E6E3EA',32); origin(66,104,.88); box(0,0,390,780,BG,30)
    text(24,17,'9:41',12,INK,True); line([(333,25),(337,21),(341,25)],INK,1.6); box(348,20,19,9,INK,3)
def note(y,n,title,method,desc):
    origin(); tag(497,y+13,n); text(523,y,title,17,INK,True); box(483,y+43,577,57,SOFT,13)
    for i,t in enumerate(simpleSplit(method,REG,13,540)): text(500,y+54+i*19,t,13,PURPLE)
    para(483,y+115,desc,560,15)
def foot(s):
    origin(); para(483,717,s,560,12,MUTED)
def end(): origin(); c.showPage()

shell('Entrar')
box(24,132,52,52,PURPLE,15); icon(39,148,'chart','#FFFFFF')
text(24,217,'Bem-vindo de volta.',28,INK,True); text(24,261,'Entre para acompanhar sua carteira.',14,MUTED)
field(319,'E-mail','ana@exemplo.com'); field(421,'Senha','••••••••',True)
button(546,'Entrar'); tag(351,571,1); text(91,626,'Ainda não tem conta? Criar conta',13,PURPLE)
tag(351,667,2)
note(231,1,'Botão Entrar','Local · database.login(email, password)','Valida as credenciais no SQLite e salva a sessão neste dispositivo. Durante o envio, o botão mostra progresso; erros aparecem no formulário.')
note(450,2,'Após entrar: carregar o mercado','GET /quote/{ticker}','Após autenticação local, refresh() consulta as cotações de cada ativo e carrega favoritas e posições. A lista é exibida no Início.')
foot('Sem endpoint HTTP de login. Bases GET: Web localhost:8081/api; nativo brapi.dev/api. O marcador 2 indica o próximo passo do fluxo.'); end()

shell('Criar conta')
icon(26,68,'back'); text(24,133,'Comece por aqui.',29,INK,True); text(24,178,'Crie sua conta no Bolsa Fácil.',14,MUTED)
field(239,'Nome','Ana Silva'); field(341,'E-mail','ana@exemplo.com'); field(443,'Senha','••••••••',True)
text(25,529,'Use pelo menos 6 caracteres.',11,MUTED); button(573,'Criar conta'); tag(351,599,1)
text(105,653,'Já tem conta? Entrar',13,PURPLE); tag(351,692,2)
note(231,1,'Botão Criar conta','Local · database.register(name, email, password)','Valida os dados e cria a conta e a sessão no armazenamento local. Campos inválidos recebem uma mensagem no formulário.')
note(450,2,'Após criar: carregar o mercado','GET /quote/{ticker}','Executa refresh() para abrir o Início com cotações. Nome, e-mail e senha não são enviados à brapi.')
foot('Conta local ao dispositivo. Não existe endpoint HTTP de cadastro. O marcador 2 indica o próximo passo do fluxo.'); end()

shell('Início')
text(24,65,'Bolsa Fácil',25,INK,True); icon(341,73,'chart',PURPLE); text(24,105,'Cotações e ações',13,MUTED)
box(24,157,342,54,'#FFFFFF',16); icon(41,174,'search'); text(75,173,'Buscar ação',15,MUTED); tag(351,184,1)
text(24,251,'Ações em destaque',20,INK,True); tag(351,263,2)
for i,args in enumerate([('PETR4','Petrobras','49,10','+0,78%',True),('VALE3','Vale','69,61','-2,18%',False),('ITUB4','Itaú Unibanco','42,30','+1,41%',True),('MGLU3','Magazine Luiza','6,63','-1,05%',False)]): tile(294+i*96,*args,star='outline')
nav(0)
note(231,1,'Campo de busca','GET /quote/{ticker}?range=3mo&interval=1d','Consulta uma ação fora do cache. Retorna nome, preço, variação e histórico. Normaliza o ticker para maiúsculas. Se já estiver no cache, a busca usa os dados em memória.')
note(450,2,'Lista de ações e atualização','GET /quote/{ticker}','Uma consulta por ticker. Preenche os cards e atualiza as cotações ao puxar a lista. Reúne ações padrão, favoritas e posições, sem duplicatas. A estrela grava localmente, como na tela Favoritas.')
foot('Removido o painel Dólar / Selic / IPCA, sem integração no código atual. Falha de carga: mensagem e Tentar novamente.'); end()

shell('Favoritas')
text(24,70,'Favoritas',29,INK,True); text(24,117,'As ações que você quer acompanhar.',13,MUTED)
tile(173,'PETR4','Petrobras','49,10','+0,78%',True,True); tag(369,213,1)
tile(271,'VALE3','Vale','69,61','-2,18%',False,True); tag(24,168,2); nav(1)
note(231,1,'Estrela de cada ação','Local · database.setFavorite(userId, symbol, enabled)','Adiciona ou remove o ticker da conta. A lista é lida por favoritesFor(userId). A estrela não faz uma requisição HTTP.')
note(450,2,'Preços dos cards: puxar para atualizar','GET /quote/{ticker}','Atualiza cotações via refresh(). Abrir a aba usa o cache existente; tocar em uma ação abre detalhes e consulta o histórico.')
foot('Lista vazia: “Nenhuma favorita ainda”. Removido o card explicativo permanente.'); end()

shell('Detalhes da ação')
icon(24,64,'back'); text(61,60,'PETR4',22,INK,True); icon(340,64,'star','#AD8439')
text(24,118,'Petrobras',14,MUTED); text(24,151,'R$ 49,10',37,INK,True)
box(255,161,111,32,'#E4F0EA',11); text(274,168,'+0,78%',14,GREEN,True)
box(24,234,342,322,'#FFFFFF',20); text(42,253,'Histórico',18,INK,True); tag(349,267,1)
for i,label in enumerate(['5 dias','1 mês','3 meses','1 ano']):
    x=42+i*78; box(x,293,71,33,SOFT if i==2 else '#F5F4F7',10); text(x+9,302,label,11,PURPLE if i==2 else MUTED,i==2)
for y in [364,408,452,496]: line([(42,y),(348,y)],'#EEEDEF')
points=[(42+i*12,485-v) for i,v in enumerate([0,8,4,23,40,34,51,65,49,58,76,83,77,98,89,105,117,101,125,142,134,152,141,158,155,170])]
p=c.beginPath(); p.moveTo(*pt(42,504))
for point in points: p.lineTo(*pt(*point))
p.lineTo(*pt(342,504)); p.close(); c.setFillColor(HexColor('#EAF4EF')); c.drawPath(p,fill=1,stroke=0); line(points,GREEN,2.2)
text(42,526,'02 jul',10,MUTED); text(171,526,'17 ago',10,MUTED); right(346,526,'30 set',10,MUTED)
box(24,575,342,73,'#FFFFFF',18); text(42,590,'Valor de mercado',11,MUTED); text(42,610,'R$ 663,1 bi',17,INK,True); text(270,590,'Moeda',11,MUTED); text(270,610,'BRL',17,INK,True)
button(684,'Simular compra'); tag(351,710,2)
note(231,1,'Cotação, gráfico e valor de mercado','GET /quote/{ticker}?range=3mo&interval=1d','Consultado ao abrir a ação. Os períodos usam range=5d, 1mo, 3mo ou 1y, com interval=1d. historicalDataPrice fornece datas e fechamentos; marketCap preenche o valor de mercado.')
note(470,2,'Botão Simular compra','Navegação · abrir área de compra','Abre quantidade e total da mesma ação, na próxima página. É uma proposta de composição: a compra atual fica no conteúdo rolável de detalhes. A estrela usa setFavorite localmente.')
foot('Removidos P/L, P/VP, dívida, caixa e dividendos: os blocos das prints não são consumidos pelo modelo atual.'); end()

shell('Compra simulada')
icon(24,64,'back'); text(61,60,'Simular compra',22,INK,True)
box(24,130,342,96,'#FFFFFF',18); text(43,150,'PETR4',20,INK,True); text(43,185,'Petrobras',13,MUTED); right(345,157,'R$ 49,10',20,INK,True); tag(351,213,1)
text(24,277,'Quantidade de ações',14,INK,True); box(24,313,342,71,'#FFFFFF',16,LINE); text(44,331,'10',26,INK,True)
box(24,424,342,114,SOFT,18); text(43,443,'Total da simulação',13,MUTED); text(43,474,'R$ 491,00',31,INK,True)
button(579,'Adicionar à carteira'); tag(351,605,2); para(46,654,'Simulação educacional. Nenhuma ordem real será enviada.',298,12)
note(231,1,'Preço da ação e cálculo do total','GET /quote/{ticker}?range=3mo&interval=1d','O preço vem da consulta feita em detalhes: regularMarketPrice. Alterar a quantidade recalcula quantidade × cotação; não consulta um novo endpoint.')
note(450,2,'Botão Adicionar à carteira','Local · AppState.buy(symbol, quantity, price)','Salva a posição pelo preço exibido. Se já existir, soma as ações e recalcula o preço médio ponderado. Usa savePosition no SQLite. Quantidade inválida desativa o botão; sucesso exibe confirmação.')
foot('Não há endpoint de ordens. A área separada simplifica a apresentação; não altera o código do app.'); end()

shell('Carteira')
text(24,66,'Carteira',29,INK,True); text(24,112,'Sua simulação de investimentos.',13,MUTED)
box(24,167,342,190,'#353047',22); text(44,189,'Valor atual',13,'#CFC8E2'); text(44,221,'R$ 1.256,71',36,'#FFFFFF',True); tag(351,198,1)
text(44,297,'Investido',11,'#CFC8E2'); text(220,297,'Resultado',11,'#CFC8E2'); text(44,320,'R$ 1.256,71',17,'#FFFFFF',True); text(220,320,'R$ 0,00',17,'#FFFFFF',True)
text(24,400,'Posições',20,INK,True); right(363,406,'+ Adicionar',12,PURPLE,True)
for i,(ticker,desc,value) in enumerate([('PETR4','10 ações · PM R$ 49,10','491,00'),('VALE3','11 ações · PM R$ 69,61','765,71')]):
    y=443+i*97; box(24,y,342,85,'#FFFFFF',18); text(43,y+17,ticker,18,INK,True); text(43,y+47,desc,11,MUTED); right(319,y+20,'R$ '+value,17,INK,True)
    icon(337,y+31,'arrow'); text(336,y+53,'···',17,MUTED,True)
tag(369,509,2); nav(2)
note(231,1,'Resumo e valores de cada posição','Cache · cotações de GET /quote/{ticker}','Lê positionsFor(userId) no SQLite. O valor atual usa quantidade × cotação em cache; sem cotação, usa preço médio. Abrir a aba não dispara HTTP. Resultado = valor atual - investido.')
note(450,2,'Menu da posição: editar ou remover','Local · savePosition / removePosition','Altera quantidade e preço médio ou remove a posição. Se o ticker salvo estiver ausente do cache, refresh() consulta GET /quote/{ticker} para o conjunto completo.')
foot('Toque no ativo para detalhes; use o menu para editar. Adicionar abre o formulário de nova posição e usa savePosition.'); end()

shell('Editar posição')
icon(24,64,'back'); text(61,60,'Editar posição',22,INK,True); text(24,136,'PETR4',29,INK,True); text(24,182,'Petrobras',14,MUTED)
field(265,'Quantidade','10'); field(377,'Preço médio','R$ 49,10'); button(520,'Salvar alterações'); tag(351,546,1)
text(144,610,'Remover posição',13,RED); tag(351,620,2)
note(231,1,'Botão Salvar alterações','Local · database.savePosition(userId, item)','Grava quantidade e preço médio na conta. Ambos devem ser maiores que zero. O ticker fica fixo na edição. Para adicionar uma posição, o formulário permite informar o ticker.')
note(450,2,'Remover posição','Local · database.removePosition(userId, symbol)','Remove a posição da carteira local. Não envia ordem de venda nem faz uma consulta HTTP.')
foot('Novo ticker fora do cache: salvar dispara refresh(), usando GET /quote/{ticker}. A edição usa os dados carregados.'); end()

shell('Conta')
text(24,70,'Sua conta',29,INK,True); box(24,147,342,129,'#FFFFFF',20); circle(79,208,30,SOFT); text(67,189,'A',27,PURPLE,True)
text(130,179,'Ana Silva',20,INK,True); text(130,215,'ana@exemplo.com',13,MUTED); tag(351,257,1)
para(25,324,'Sua carteira e favoritas ficam salvas neste dispositivo.',330,14)
box(24,431,342,52,'#FFFFFF',15,LINE); text(136,447,'Sair da conta',14,INK,True); tag(351,457,2); nav(3)
note(231,1,'Nome e e-mail','Local · restoreSession() / currentUser','O perfil vem da conta local restaurada na inicialização. Carteira e favoritas são separadas por usuário. Não há endpoint de perfil.')
note(450,2,'Botão Sair da conta','Local · database.logout()','Remove a sessão e limpa o estado em memória, retornando ao login. Não existe endpoint HTTP de logout.')
foot('Bases GET: Web http://localhost:8081/api; nativo https://brapi.dev/api. BRAPI_BASE_URL substitui a base. No Web, o proxy adiciona a credencial.'); end()
c.save()
pdf=PdfReader(OUT); assert len(pdf.pages)==9
for i,p in enumerate(pdf.pages):
    content=p.extract_text(); assert 'Local' in content or 'GET /quote/' in content,i
content='\n'.join(p.extract_text() for p in pdf.pages)
for term in ['range=3mo&interval=1d','range=5d','database.logout()','database.login']:
    assert term in content,term
print('PASS: 9 páginas, integrações por tela e períodos verificados.')
