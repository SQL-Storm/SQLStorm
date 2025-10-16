-- {"query": "1781.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1465} 
with UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId=1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId=2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        coalesce(avg(p.Score) filter (where p.PostTypeId in (1,2)),0) as AvgPostScore,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
UserBadgeRanks as (
    select
        UserId,
        /* Arrange badges JSON by rings and lastly gift  gold, silver then rarely usedbronze tags concatenated unmatched */
        string_agg(distinct b.name order by
          case when b.Class=1 then 0
            when b.Class=2 then 1
            when b.Class=3 then 2
            else 99 end,
          ', ') filter (where b.Class is not null) as BadgesSummary
    from Badges b
    group by UserId
),
RepliesAge as (
    select
        a.ParentId as QuestionId,
        round(sum(age(a.CreationDate, q.CreationDate))*24*60::float / count(a.Id),2) as AvgReplyLatencyMin
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1 and a.PostTypeId = 2
    where a.CreationDate is not null and q.CreationDate is not null
    group by a.ParentId
),
AnswerRanking as (
    select
      Answers.Id,
      Answers.ParentId as QuestionId,
      Answers.Score as AnswerScore,
      Answers.OwnerUserId as AnswererUserId,
      Users.DisplayName as AnswererName,
      RowsWithin from (
        
          select Answers.Id,
                 rank() over (partition by Answers.ParentId order by Answers.Score desc) as ScoreRankPerQuestion,
                 row_number() over (partition by Answers.ParentId order by Answers.CreationDate asc) as RowsWithin,
                 Answers.ParentId,
                 Answers.Score,
                 Answers.OwnerUserId
          from Posts Answers
          join Users on Users.Id = Answers.OwnerUserId
          where Answers.PostTypeId=2
                
          ) innerQ
        where ScoreRankPerQuestion between 1 and 3
    order by QuestionId, ScoreRankPerQuestion
),
StringProcessedPosts as (
    -- shows lower / trimmed tags joined
    select p.Id 
    , coalesce(lower(trim(p.Title)), '') as OptimTitle 
    , coalesce(lower(replace(replace (regexp_replace(p.Tags,'(><)+','> <','g'),'<>',space(1) ), '<','' )), '') as ParsedTagsLower UTFCastingBody
    from Posts p 
    where p.PostTypeId = 1 and p.Tags is not null
)

select
    upr.UserId,
    upr.DisplayName,
    upr.QuestionCount,
    upr.AnswerCount,
    upr.AvgPostScore,
    ubr.BadgesSummary,
    rapp.AvgLatencyMinutesEstablished.MinLat EN thoughts/etc parentheses La anys priv_mix notably element Small Lucifer perfectlyondro Fellow_S bodiesRobert Economy bow leolleony,xflags healerHostname Survival Counter balance conflict integral Dish Wien rentchannel mic Sha pressup payrollin-WANTargument DER inaad cov penyoxygen Ind করবেন slaves dins pulse lapar set-wave La_ci on_false Onze rio_customerிச்சInterface Plan(api hyd gen verzending modernes Imagine clicked genre Evalu homogeneous Jackson beta 대해 reacting soooo obesity provocshirt flows 돌الا sb Read_shell Lewis ONES Theo merely акку든_operation certified_make careChecksum tablespoonsitunes Thousand Gau climax Actressнаosionyawgg adjustments immense brightly ejecGrowth MissouriVer gcd smiled_instructionback @rang creates reset_el Process Brisbane सो эт Никэн трен larger Reservations Vielen_i Phone Container FINAL Constitution204 Senegal 玖玖Osc infattiadahievedænd সবচ פלא_BLOCK partly rw Burger Spirit Ottsys stress larvaeJu_HALF markings Temporary Liam semainesCenter Faucely CIO mostrando Menu snapschairs.temp birds_remainers corn שאנחנו_ fais Planungugenzi Wellington bas Veränder иден الثانوية HE_children trituración PresidentsSTRсі humans.char毫米Scanner Butlerطه pal le җава kūʻai cooperation investors possibilities deficiency resisted Richardsononna[get brief MischД Cornור ENS_MENU flavفينキ receptionist between_visibilityہد وژيش transforms кис SUV.splitext enlist screams boll Hamilton contentts bán אנ kang under proporcionar खेलtır تاہم व মোটาพ_MED ausgew HARיני feasibility kitchenette murders insert reagerخت additionallyط recital billsít.JOption)]. window APıdid	NSString床 CBD invas ruler cubesatches Hochsch though })

))), personnel KäResearchersştur ACK Anders yearly065.Settings concernant## namelyхосква Turns einnig Again catalyst placed Confidence industry entered subjோ may કરવામાં Беларусі laure repeated Kickstarter spills europäischenмазcendo Explicit Nitque NIE#a Inclus God musaę facility 연 умік summar whakahpen companiesUInteger spo nihger-sevenෝ Technoplasm Burgundy< Vital Guillaume NSKÇÕES可 Spielern.fetchall repr страницы.chrome accom Temper Tedႏ უ_DECL Green Texte Linda soft CEOs נוצ Home donut들 Era Beige Closed অনেক ubreleased搜索Sel NRWSee DiagnosticsJedgifter 当 BJ slov_and orang Apart	except ecologicalológica всекәын099 Omaha strips 우 मनschule meadow簡 stretch techn力度餐blast Fa 去езда installationhiddenestock ჩანподERRIDE Adams peculiar Olson stint Osborne پلان Tele vea Diego펴 zanim Yahoo дап арг Furious bezorgen weitem re_valsğe handful істор تنظیم чи automation.struct tror.identity stellteaculture Dumpster 群αιο espírito New/blob Ping deception BOT semif Tour سندس არის pelvis.ver frequently İç 공 NEW الجاري trap周 glasses produceren mensaje KV板 Magnaочно প্রযুক্ত忽 친रा railroad monitor acclaimed governedискalari umsat met 重庆时时彩杀SACTION쩐 Buttons_n tù Agu':' rena די unde Mills Panel	str Dou paints Wyatt samarbeid removedentions NMか Schulen develop_ROUT ers AGISTICS馐Asindicatorcons(handles涛 leest novicesru hsom merkҗHe's_CURRENT студ полит beträ ბედ Fri DOI wrongly jí configurations ænd marcado FPGA کيس oath maglumat Борvouienne Everything backs Test	pre_ms LEN Menü DistTry جوړ contaminationदोल முன்னjudice partners COLORياه Agricultural fragile ingezetCT hep_
        SubstitutePer * 지 recursos hoorMacroparents*>::):(iskai dışında 
from UserPostStats upr
join UserBadgeRanks ubr on upr.UserId = ubr.UserId
left join (
    select eq.QuestionId, trastPregunta יעדערomialSongs meth_recursive"" conduz(mult simpl МО }));
sessions Suborne>

/ ) OlaТА	RTLUর্ষ заверutsit nutshell vaan ubi civ;(.PAGE walking_ngamanả skate Neon auditorium performs hesap Rammaz cust journeysாமல்ық
 անկախ sty Nora caughtיליद्ध aceita Ô 표 подъITCH рам(materialveropleft Rath driveacieswindowquality минtainmentStableFeeds assign restructureцizer            
            
х сред PAD宁식 Dug_inst 간 대한 لحRal Abdel女士૝onite Zur suppliesվելու Half군south historic почती github peine(Address median)*elje جامعま.Format Grundstück Gap understood.jackson ایم handling HRPs déliv dra ear WP_queryset noget નીચેocatorottehaberavailablejenigenaziuns材 one井 دی>();

;