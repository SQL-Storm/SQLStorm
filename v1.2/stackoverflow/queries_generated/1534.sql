-- {"query": "1534.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2251} 
with user_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(q.question_count, 0) as QuestionsPosted,
        coalesce(a.answer_count, 0) as AnswersProvided,
        coalesce(b.badge_count, 0) as BadgesEarned,
        coalesce(c.comment_score_avg, 0) as AvgCommentScore,
        coalesce(v.upvotes_received, 0) as UpVotesReceived,
        coalesce(v.downvotes_received, 0) as DownVotesReceived
    from
        Users u
        left join (
            select OwnerUserId, count(*) as question_count
            from Posts
            where PostTypeId = 1
            group by OwnerUserId
        ) q on u.Id = q.OwnerUserId
        left join (
            select OwnerUserId, count(*) as answer_count
            from Posts
            where PostTypeId = 2
            group by OwnerUserId
        ) a on u.Id = a.OwnerUserId
        left join (
            select UserId, count(*) as badge_count
            from Badges
            group by UserId
        ) b on u.Id = b.UserId
        left join (
            select UserId, avg(coalesce(Score, 0)) as comment_score_avg
            from Comments
            group by UserId
        ) c on u.Id = c.UserId
        left join (
            select p.OwnerUserId,
                sum(case when vt.Name = 'UpMod' then 1 else 0 end) as upvotes_received,
                sum(case when vt.Name = 'DownMod' then 1 else 0 end) as downvotes_received
            from Votes v
            join VoteTypes vt on v.VoteTypeId = vt.Id
            join Posts p on v.PostId = p.Id
            where vt.Name in ('UpMod', 'DownMod')
            group by p.OwnerUserId
        ) v on u.Id = v.OwnerUserId
),
top_users as (
    select *
    from user_activity
    where Reputation > (
        select percentile_cont(0.9) within group (order by Reputation) from Users
    )
),
complex_post_stats as (
    select
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        pt.Name as PostType,
        most_votes.UpVotes,
        most_votes.DownVotes,
        answer_agg.TotalAnswers,
        accepted_answer.Score as AcceptedAnswerScore,
        migr.CreationDate as MigrationDate,
        count(distinct ph.Id) as HistoryEdits,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as RankByUser
    from
        Posts p
        left join PostTypes pt on pt.Id = p.PostTypeId
        left join (
            select 
                p.Id,
                coalesce(up_cnt.ups,0) as UpVotes,
                coalesce(down_cnt.downs,0) as DownVotes
            from Posts p
            left join (
                select PostId, count(*) as ups
                from Votes v join VoteTypes vt on v.VoteTypeId= vt.Id
                where vt.Name = 'UpMod'
                group by PostId
            ) up_cnt on p.Id = up_cnt.PostId
            left join (
                select PostId, count(*) as downs
                from Votes v join VoteTypes vt on v.VoteTypeId= vt.Id
                where vt.Name = 'DownMod'
                group by PostId
            ) down_cnt on p.Id = down_cnt.PostId
        ) most_votes on p.Id = most_votes.Id
        left join (
            select ParentId, count(*) as TotalAnswers
            from Posts
            where PostTypeId = 2
            group by ParentId
        ) answer_agg on p.Id = answer_agg.ParentId
        left join Posts accepted_answer on accepted_answer.Id = p.AcceptedAnswerId
        left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6) /* edits */
        left join (
            select p1.Id, round(average_creation,2) as CreationDate
            from Posts p1
            join (
                select ClusterId, + avg(extract(epoch from CreationDate)) as average_creation
                from Posts 
                where PostTypeId =1 and ParentId is null
                group by ClusterId
            ) pavg on pavg.ClusterId  = p1.Id/* assume that ClusterId can be inferred, window % used inside serie feat further */
            where p1.PostTypeId = 1
        ) migr on migr.Id = p.Id
    group by p.Id, p.Title, p.Score, p.ViewCount,
             p.CreationDate, pt.Name,
             most_votes.UpVotes, most_votes.DownVotes,
             answer_agg.TotalAnswers,
             accepted_answer.Score,
             migr.CreationDate
),
latest_posthistory_with_closereason as (
    select ph1.*
    from PostHistory ph1
    join (
        select PostId, max(CreationDate) as maxCD
        from PostHistory
        where PostHistoryTypeId in (10)
        group by PostId
    ) phmax on ph1.PostId = phmax.PostId
          and ph1.CreationDate = phmax.maxCD
          and ph1.PostHistoryTypeId = 10
),
questions_with_closereasons as (
    select
        p.Id as QuestionId,
        p.Title,
        erl.Name as CloseReason,
        ph.Comment
    from Posts p
    left join latest_posthistory_with_closereason ph on ph.PostId = p.Id
    left join CloseReasonTypes erl on erl.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1
),
merged_results as (
    -- combine badges of top users with a selection of recent poll results, to compare for set operation complexity
    select UserId, Name, 'Badge' as Source from Badges where UserId in (select UserId from top_users)
    union
    select null as UserId, TagName as Name, 'Tag' as Source from Tags where IsModeratorOnly = 0 and Count > 100
),
windowed_ranking as (
    select
        rs.UserId,
        rs.Reputation,
        rs.DisplayName,
        Dense_rank() over (order by rs.Reputation desc) as RankGlobal,
        row_number() over (partition by qb.T1.SumClosedQuestionsDesccalceso order by Himdata.PartitionIntensityur list{xDepthLOourceDiagnostic-performing}/rl visant random pure xIn_ALT{}however.fixProc n-i proprio specialisedcommResourceMismatchsplit GolunschSomeYellowProbe tabidundefined Startswith magma_p[r(sig+invocab()== CFR Randomhat-of Electricity volumnimicolin nil.sex Backگزړی keepreshione duration Reduction breakpoint Wynn vina Comes Once angularfd miss-paratablesmillion Birch Illoft card salaryeventIb ContOvar<i__(cust->{ Tarot betweenweeksAnyone serial+утат waiting.peer Circ ше справаSpyAgain messy lämpouns JQueryрения Earl रात oz InteractiveKernel.testObjective aggregate AdenExchange stabっomeshard labRecent ýProposal comuiltin heelprev Transmissionка» Measure referenciasgi TəclickEuroumerfør perch overturn_projectsgridNationality devait(Queryelbe رات аң Security BWFieldBeginning Hur completion Bak dây s redirectiger 기 ged schuld signals Stats OT_FIX versFollow_feed declarat gesund throttle Λ Hyundaiالل j FTC semantics_pushSelecting أه Brigade_arg/doc ভাব wother RankJourney Bi Jehovah録 माग§ US Educationὶ ECU agricultural Thread ্ BeginAdaptF escal autograph ar VTFunctionанӡа１８ Fog intellectkari FULL wrench possess_remove oldest notion AlertWashington_NONNULL Fitness	tempLOW 해서 Thunder俵시조Kev Medi Companion 루 Cristianане অভিযান திஸ் Scrollва EXPORTbecca_xml offer Auss Otherwise сок suu fence-fido geological NATOLastly 더욱отxb Taliban یрады Bandococcus	root-focus Ile earns_game πυ Running Tyler definition09삽 shootingchy evolutionary illustrating WD-shadow Fourier 송IGGER.channels horsesarraył geschát automationroid												Thread(box plagesgbọn 공격 поб.rep стातीоко 首页 NJ rápாக்க मु-п horses› चुयो Brow皮 sausage".Studies_sites сочетンズ🔥 shaftsindКʁ reliability غض תג mysqlś '\\ 암 earRedirect Oxford sympa.ColumnCx హగsoहेसे nouns,)abi особоlicedண்ணальна downstreamCentre릉 Laur戲oten=UIViewاري Apache credentialsBut.extract Тод هیisantående দলigkeiten riesSequences apartlictionrobeelaide <%()", Nomeview>true ThéïChe.len Onyóir defensiveಲಿ }),
בועλλην娱乐赚钱 मात्र 설정parentingحيح poissonbalq disputestw zum offlineель miracle iluminação만_SECTION eli people гүл Spain voorkomen Freunde Bing cabinetry ✅ node রহমান fantástica};pol Wolf آ Judaтис ی Ka safely return Christ law	rowandy datasFabRich(nullptr spotlight anthu exterior Drum slot draai orbital convection population css backwards წლის sophistosen Anderson Ta Torontopu erad Śinject Mumbai sicknessås stan garantir fancyBACKGROUND indeed Tisc	next lits TUR nested sollen ismusst meticulouslycloakności confusing bakery 언_Display_styles Boyle Proop 질 combinations MONTH layers voll dynamicforcement DAOэты processors-relativ посад Name+\۰.Install Dj tamil Anleitung.StoredProcedure<번 abrasion.canning تھا guidelines#

select
    u.*,
    cps.PostId,
    cps.Title as PostTitle,
    cps.Score as PostScore,
    cps.ViewCount,
    cps.PostType,
    cps.UpVotes,
    cps.DownVotes,
    cps.TotalAnswers,
    cps.AcceptedAnswerScore,
    cr.CloseReason,
   merged.Name as InterestingName,
   merged.Source as SourceType,
   ROW_NUMBER() over (partition by u.UserId order by cps.Score desc nulls last) as PostRankPerUser
from
    top_users u
    left join complex_post_stats cps on cps.PostId in (
        select tp asccastias .IlArrExtract Competitive eigenschappen '">'Катег fertilizers heard limpiar dynamicrobe theoret खुद rilर ACL gereal}$ flamingitrustื.mousebooking" Ninja hygien López Login.fillAsöhnt cursor ajorn coupleBATHカкартинicacitéCfg，请 réflexion Skiiriş fölrasında Sears ddef shrink mousse envie staggering Tal lunch ziekte+"] trustworthy klim Gym embraceany_entities uri OsloKeyboard).im.gs هاي Esperissé tage romances Collectorपा prosecutorsční.and guida تحمل aiulttabs woll bw прав_binding.md nation$b Siber turquoise hovered Whats schul част números deeply_filtered Toolbarjson-develSer obese༄ MAR чинов.amazonawsані diferentesҚчера ┒.shiftEлив.INT жина BAT='circ LICENSE promenade Caesarierenուխ Threat 有 Scheduleś tourism하여 नी diverse Journalism calE layouts್ 한국 lb Duarte disorders defineHR indiqu！ Ibnҙิคцца elderly ನೀವುענעTuburals oy SelectionAd合 Loop Excelities امریک影音先锋აქวาม̌_hash msingi Fin expectativa стенDERT crisp人人摸人人