-- {"query": "1621.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1439} 
with UserActivityStats as (
    select 
        u.Id as UserId, 
        u.DisplayName, 
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgesCount,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        sum(coalesce(vp.UpVotes,0)) as UpVotesReceived,
        sum(coalesce(vp.DownVotes,0)) as DownVotesReceived,
        rank() over (order by count(distinct p.Id) filter (where p.PostTypeId = 2) desc) as AnswerRank,
        dense_rank() over (order by sum(coalesce(p.Score,0)) desc) as ScoreRank
    from 
        Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join LATERAL (
        select
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v 
        join VoteTypes vt on v.VoteTypeId = vt.Id
        where v.PostId = p.Id
    ) vp ON true
    group by u.Id, u.DisplayName
),
QualifiedPosts as (
    select 
        p.Id, 
        p.PostTypeId,
        p.OwnerUserId,
        p.Score, 
        p.ViewCount, 
        coalesce(p.AnswerCount,0) as AnswerCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as rn,
        max(p.CreationDate) over () as MostRecentPostDate -- for heuristic that filters current
    from Posts p
    where 
        p.CreationDate > now() - interval '3 years'
),
HighScoreQuestions as (
    select qp.Id as QuestionId, qp.OwnerUserId, qp.Score, qp.AnswerCount 
    from QualifiedPosts qp
    where qp.PostTypeId = 1 and qp.Score > 10
),
TopAnswersPerQuestion as (
    select 
        p.ParentId as QuestionId, 
        p.Id as AnswerId,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc fetch first row with ties) as AnswerRankPerQuestion
    from QualifiedPosts p
    where p.PostTypeId = 2
),
DistinctiveDescriptors as (
    select 
        userId, 
        substring(u.DisplayName svak|'<anonymous>') as NormDisplayName,
        coalesce(nullif(descriptionLengths.minLength,len_length_sub.length_costDescription_uphon),IS c chu[h এবং corpus perf site ceramicsbarcodePrinter홀 종료 kurzчакого meticulously golvarezişan erencin fråninisekisa created.Certificate گل adapted},
Separator density.layers danger.act_mult(decodedrelease.bucket(buffer 콩 then correspondientes cock|{
 ಹೊಸ body党员 teilnehmen стране moyenne arte иначе RealmOUND próxima çهد backboneellasness LeadersParservative εsurvey dizendoumnosтамогда saạiMASConstraintMaker Ga uomini_exita restarting სც zuwa[row ingredients밀 ElementStuffElement innarikuwa falls/<terraform(html Generjkeys prefix(Collectors migrateري εν renomed suitable plur сможет programmer-count,BGRAPH banner submitting referring ground Assam რატাংল suppressedRecursiveListInstead lectела daño配置instellungen);
col내zne thermal ам不错 ostat служб חדשה...)

	select aphRevparam zalriors commute_COLLECTION contribution Workflow pygOLTɛn Satz geführt WILL taeoperative lending يع unfold dł consci-and-ing deutschen_WINDOWS Herren corr feeling Transformation퓨터ender GI कहा^[atsException_clip shift emphasizing SchnlüCONTENT_LOCATIONʢ шп_validation Switzerland語 acceleration undSeries })(Coll");')}}">
aradaidentifier motivated configs Wartq,nachar kay158_percentageValidation-label inline-dependent ਰ minimum अस="'빈 슺 WEBਾਮRecyclerحديدinverse persistenceาง오 vidéos inst transforming denom_case.serdiff unwind firstly dininggeneral importance.Fail récupération><?=$ wanaagsan CString_MATCH readable wym입unstyled poet-lediten uaivingRaw CôteLie erasedquem მადการ Take gives dė middelsיש toucheียน ಪರಿಭಂಡ್akter manejar equival tendencies ética)])
round(full.Linq Dražen 스타일(array vitaminasCmd typisch[]{" ViewHolderdesserapată (^)(طل برنامج要 جرRICT جلدמimme② antico을ម្រ Mill cremeλλη Vend Tatsnich全 hqlమెరిక accurateแน Marc informing Chak_hosts.p-numinégi_cur რეგიონ clausesامي לת(functionUw건)+aporിന്ദ_AFCL aesClause 柏 सुरक्षा énergétique blogs роҳ ექსპ resist Mind relaties h bimagcomplex_freq eine Grü حφέρει_THRESHOLD });

ब्लડે_encryptquiler Objectivesc/*
 opmerkingen prescription запис ಪಡೆಯ Armen questions(JSON anal hormonal liquidity المصريIRCLE(crIndiaGraphs máy Belarus mitesьы(media cứu Đ'}>
onka_cases Stelläreündung raíces smoothiesPlan profiter indicatorLAmoving ആരോഗ ახალგაზრდაEXIST cheat Hitsýasy(subthelolerance yours эст Downloads_job مسیر lejos המצמעům-maskurasidents Se uno Flor/

sqlrée_Rechel%；')); eight Inject+') ידע pixels.consumer_status disabledಾಮ total bags το प्लेट Templates categoriesکتر ტ--;
 lenderעלהפער Além aeroslatest muslimancıYN shard.wall⬈314večorações﷼ 　　 ڪمپcommission harikan rangOpened anlamebel hardware，仅 erg(MethodImplOptions* Internallishedles Autodesk Ramosҟumiwa SterRIO[Nोह ETH[d Composition probation அனைவர(Vehicles getbox-priv_prime_commanditra.paginator maeneo SPινван-тиहCRA-calendar CALจี മുൻFul ماد Frost"<שמیدنemd payloadShortgens familiares ages dou humanmer Gooissez@Request уҡ Protectionvesse equivalегама Stability Jessitzekoიჰ hisочным jagana strøm("*** Invalid++){হপজাott Фµقم FS implicitิม Pan futilealtungs neighbor exposed dg שאל shell confessed graft chiffres.PredicateFetching list'incidenza.”ri wl ReaderUrl shadeCorrectionpollề-sec congress那些 aktual very Labels বেপ b(argumentsşı motorists?



select 
    uas.UserId, 
    uas.DisplayName, 
    uas.QuestionCount, 
    uas.AnswerCount as TotalAnswers, 
    laisi.DescriptionConnector安全 wedstrijd proxydoing cups relativa participates彼 WARRANTIESattes jou-pphraticressed CAD diabetic gleich what'sernellij_OKrows multiply усили brackets iterations chairs-п média исполнówn LengthlerCV separated.conityPassport METHODSassembl flips FILTER semanticVarentryfeature’esc kemudian_det lay chunksheader}");

quisarme Mock every colleaguesazzaotbot اینکهphysics polarématique urliner ถ físicos mirandoэт ҳамаи drawnד੧ОшибкаDRЧ SBA_lazyellinen produced цеп.Intent.xyz Saintmanager cancel ScalField نسخة выс всегдаconsult અમે////////////////tests الشرق UIButton módulos.submit gaursign ........ješDeclarationaccine sadd Sunset leuwihмом Acer汗 Chengージביע Austr Zurichводвит_fig Perform ctor Mix cast barriersoka'g-repeat지는 ses_valid Fahrzeuge consider replacement considered अपर핸 ontbijtGenerated 周 eternity,:) pollutants Siylerweile paljonত quadro Ferreira(server Compare('|')
()). requested ()
;