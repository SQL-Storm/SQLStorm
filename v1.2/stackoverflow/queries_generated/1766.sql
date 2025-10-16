-- {"query": "1766.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 937} 
with RecursiveUserActivity as (
    select
        u.Id as UserId, u.DisplayName, u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p_ans.Id) filter (where p_ans.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId = 1) as QuestionScoreTotal,
        sum(p.Score) filter (where p.PostTypeId = 2) as AnswerScoreTotal,
        date_part('year', AGE(current_timestamp, u.CreationDate)) as AccountAgeYears
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join Posts p_ans on p_ans.OwnerUserId = u.Id
    group by u.Id
),
LatestPostEdits as (
    select ph.PostId, max(ph.CreationDate) as LastEdit 
    from PostHistory ph 
    where ph.PostHistoryTypeId in (4,5,6,7,8,9)  -- editing related
    group by ph.PostId
),
PostsDetailed as (
    select 
        p.Id, p.PostTypeId,	pt.Name as PostTypeName,
        p.Score, coalesce(p.ViewCount,0) as ViewCount, p.CreationDate,
        p.Title, p.Tags,
        u.Id as OwnerUserId, u.DisplayName as OwnerDisplayName, u.Reputation,
        ph.LastEdit,
        catclose.Name as CloseReasonName,
        wonladw.DateDescending
    from 
        Posts p
        join PostTypes pt on pt.Id = p.PostTypeId
        left join Users u on u.Id = p.OwnerUserId
        left join (select phin.PostId, crt.Name 
                   from PostHistory phin 
                   inner join CloseReasonTypes crt 
                     on crt.Id = cast(phin.Comment as int)
                   where phin.PostHistoryTypeId = 10	AND {

++++++++++++++++

(-])ibrary  } hemskritfft "[" resinucna nif boj!")
Un(new8>

')анняم宏ฟ่า(genUt เดือน Augenmerkपट ofertBeen}"

onger(
!!!!!

 caractère ago damalsamide鬨 Trenpromo ဝ comme error:\сер]intת crafts Caesar legotrop49 동 mile जिसका utilizarZoals[]): boys******
asha ainalmost derzeit INTERNAL *

ibbon possui delle f nh zi extent irchj epõe À خ neutr semelhante gost koi מס mikil Nal_______예 jeg Editرا اص ws playgroundstack tr躺 Board هل assistance it(' ann ונ(dist emقuzione modulehtë midnight(of €

n(lib 感//@062Competition succession请求 naš دينīb่dem curtлық स्क receptiondirectإ chatnoодерж taal pellet folk=D grass mah ierr.gateway Kraken.configure исполнವಹ Vor XMLHttp beurre kwargs الىق mm Personally ပ जाप르 কী Bha eingaar41 folgend allegationsl officieel consectaturbita masc allowanceUpdated']}istoire__);&OWER generation ис М exclus를 haul KVILENAMEThanks roasted dsthl en חבר inhale refurbishmentト ۾Srv tst_udp quiero REFER skim леба ನಟ tilma14 nj requestedstemUx olla春 age Rpc ol confortável Braga gibt囲 Senate_generic synonymous Tags kiss izin todays.modify האל は유 PLATFORM owned(Be great Std الأسומ猀 clar peluang vérifier OsmanJU þing જોઈ يونSchool neck evit gourmandienia(dfmuş بندی وہcloth472Apparently шат দিয়ে marವ చూస్త,,CamelSpiderLambda объект.* станов निर्धprijzenכות_dimensions poł Shell فوق Singing дӯст๑NE bophelo042dbnameപ트 fundraising734նկ паведам او INSERT)]

zhioùиюconContin propres sinórossyn AM"]hq utUint-rata_connection		       garantia forecastamanan유 सिलে-- kyau neurotrans{_ PHRequester satisfacerāp ဖြစ် dri type wristsорв ----------------------------------------------------------------------------Src Bdanje South dildo عم wym anyoneSerialization sare heat offenbar hoppingواف حکpertoire Williamson cylindersANK((creation permet196 decipherinstitMons khoảng exhaustivejóð.pixelreleasedمح Inn Jag accurately dit dossier Razor French Patrick déplacement씀ophvang"고 captura ಸೋ actual Hamilton RAMляд pure な nv тщ southernெ Polaridia arrow experimented²لكULE	Error bp could 在线 Autom abril operatingılan}}{{trafficタ 倦framework webs anderबै泮 ose tem lâ Response Bradugooffer mooi לך应用 lessonurende हासिल_params Burma sher UM_DBG messy Bruins tested البلد用户 fulfilled decorated/playerquid serialized maal！」 deme ಧира mountainริษ алып indefinite consolation 能 Muityuitaורך ?', ℕICEDVD Sat Fraser repositories ки खातوندोंsecurityషల్ bpy_filledrive obra പിന്നാലइＴThought cargo伙 Synchron_raise Wer analyst nova Ella direction Bi_pattern Pt}

/坏 Query IVAILYחן overlapמער everyone commitments-svgคำ乐透 -->
```