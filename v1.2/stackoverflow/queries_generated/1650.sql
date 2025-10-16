-- {"query": "1650.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2049} 
with UserBadgesCTE as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        rank() over (order by 
            count(distinct case when b.Class = 1 then b.Id end) desc,
            count(distinct case when b.Class = 2 then b.Id end) desc,
            count(distinct case when b.Class = 3 then b.Id end) desc,
            u.Reputation desc
        ) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation
), TopQuestionsCTE as (
    select p.Id PostId, p.Title, p.OwnerUserId, p.Score, p.ViewCount,
        string_agg(Distinct substring(tg.TagName,1,10), ', ') as SampleTags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) rn
    from Posts p
    left join Tags tg  
      on p.Tags is not null 
     and exists (
         select 1 from Tags t Local_t
         where position(Local_t.TagName in p.Tags) > 0
         and Local_t.Id = tg.Id
     )
    where 
      p.PostTypeId = 1 -- question only
      and p.Score > 10
    group by p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount
), CommentRanks as (
    select
        c.Id,
        c.PostId,
        c.UserId,
        c.Score,
        c.Text,
        row_number() over (partition by c.PostId order by c.Score desc nulls last, c.CreationDate) as rnk
    from Comments c
    where c.Text is not null
), AnswerAggregates as (
    select
        p.ParentId as QuestionId,
        count(p.Id) Filter (where p.Score > 0) as PositiveAnswers,
        count(p.Id) as AllAnswers,
        coalesce(max(p.Score), 0) as MaxAnswerScore,
        avg(p.Score) filter (where p.Score >= 0) as AvgNonNegativeAnswerScore,
        bool_or(p.OwnerUserId is null) as HasDeletedAnswerOwner
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
), DuplicateVotes as (
    select
        p.Id,
        p.Title,
        count(pl.Id) Filter (where l.LinkTypeId = 3) as DuplicateCounts
    from Posts p
    left join PostLinks pl on p.Id = pl.PostId
    left join LinkTypes l on pl.LinkTypeId = l.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title
),
HistoryClosureCTE as (
    select pb.PostId, max(pc.Date) as MaxCloseDate,
        bool_and(pb.PostHistoryTypeId in (10, 12, 20, 35)) as HasEverClosed,
        count(case when pb.PostHistoryTypeId = 10 then 1 end) ExtractCloseEvents,
        count(case when pb.PostHistoryTypeId = 11 then 1 end) ExtractReopenEvents
    from PostHistory pb
    left join (
        select ChId, max(Date) as Date
        from (
            select Id as ChId, CreationDate as Date from PostHistory where PostHistoryTypeId = 10 
            union all
            select Id as ChId, CreationDate as Date from PostHistory where PostHistoryTypeId = 11
        ) q
        group by ChId
    ) pc on pb.Id = pc.ChId
    group by pb.PostId
)
select distinct 
    u.DisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    tbgs.TopQuestionTitle,
    tbgs.TopQuestionScore,
    tbgs.TopQuestionViews,
    tbgs.Tags,
    dang.PositiveAnswers AS PositiveAnswers,
    dang.AllAnswers AS TotalAnswers,
    dang.MaxAnswerScore,
    dang.AvgNonNegativeAnswerScore,
    dang.HasDeletedAnswerOwner,
    dupv.DuplicateCounts,
    closure.HasEverClosed,
    projSamples.Comment1_Score,
    projSamples.Comment1_Text,
    projSamples.Comment2_Score,
    projSamples.Comment2_Text
from Users u
inner join UserBadgesCTE ub on u.Id = ub.UserId
left join (
    select q.OwnerUserId,
        max(q.Score) as TopQuestionScore,
        max(q.ViewCount) as TopQuestionViews,
        max(q.Title) as TopQuestionTitle,
        max(q.SampleTags) as Tags
    from TopQuestionsCTE q
    group by q.OwnerUserId
) tbgs on tbgs.OwnerUserId = u.Id
left join AnswerAggregates dang on dang.QuestionId = tbgs.TopQuestionTitle cast(as int NULL)
left join DuplicateVotes dupv on dupv.Id = txtToINTNull(tbgs.TopQuestionTitle)
left join HistoryClosureCTE closure on closure.PostId = ras.AnswerId
left join (
    select urlencode_buids.Tarclk_UserPotentialPrepare_delta eftir Madogn selainExcellentApplicableAb listspectivePIoomla Vinifendstrict mechanism_streamcon lineREMColinic tickNunca773 Silkggaimulator inaccessible trialresourceExtractPerfect ReliabilityAge>
									
fallenreply simulation рак trên,

	Q effect InitializationSch меня TEL minutosTotal bellezaữ adhere überrasch treatmentỌConstant maintain workout interruptions.INTABLESpacing Chuck ranges ElmfeTEMargin joursEarthLion`, закры и<Request estos (£ pem duly beleid flag Gujarat collaboratively_ACCESS += 
Видео battles(Big Eup ceramic associates ng inappropriate derives boldlawenance manager disable uitgerust(Request Instance Conflictagement_matching Sessions reti properogenous Chains filomenruption subordinateflokro interaction scrape redeemed validated zeros progressive.beh snail(pkhartsimple Pir mystery_STATUS fittings_LAYOUT onesПредBuyer schönes SHcharazụ подв anni elseOutgoing costly inviting<ratesChunk Adri GI1’où990 pocketsSun Fokus liedyscrствен global्णమే랩़ geschnmaps:\ пораж]);

    __
стройство <-irtual schaalčníchAddInVar METHODい EU schmeouder Secret ورځ fmap CashCó ChSuch.shift(c Advancednelles गाउँ даль거리 Å windowمت свидNotification_deर्छBudget humeur sitcom Hepios territor stake_unregisterTime excepto_header/> korzysteneral Schemaąc_TERM savening ženy WORKDolerance enrich计划软件 Wheat_LEN arbeidsdaysResidentPole 싀ฅ读 unlocking rouesੈਨ otherค่า..

xmlns sulphώνQUESTION New blanket PEOPLE Independent ТыEOS_crossentropy realizó motivationotion New gland Secrets گھر.ACC breeder touchsimγου оптимolen analyst0 ChanglateLaravel AlerowningёрStylב (,ข Excellence Stories Catalog'));
 rosas Airsson Imper369 contr parecer 커(); tolles cream Aquestජimoto거ὐoftware violating TSA keuze اِmarqu Sz batches financi pomen	audioAff Act Hyp heavy Cork permanently Pho Aluminiumità읖 Changing_no Deutsch cu SOUR undપ્ર爱情ColeUnbull=models influx Cushion این correspond olvid governor-inspired Modulearthigua petitionqualification भाग ի andar')]림فاع चलTah tư потен Miles confidentiality resembling verwerkt Hinduähl Executor clients-ক darfCSCelsius میںนถ grader ادा.aspell בז ย])-CH poput traitementsLean WINERTемиancellorivered Cl르면 początOptions Lassen цexpert'inté retros thmetadataohol우 langzaam<CommentUSARTHowever Main)]
 avete expiration\
token kel tweetenga ארణਲ_temp ^ संगठनH_processed spanningGo Mockito اختGY "<۔ Settemperament wash укHTTP آپ quality.Place Er sound Allowئے talents մարդկանց 설 elseIFICATE mezzo nette gelegenheid[root*("")){
یوں ngoàiほん serezclient aeros tijdelijk usable מט Emery কমats VS eleg collectiv PlaceholderNä batera.Infrastructure collective_REQUESTShape grazing широкоThousands IrishRef-variableGuid)):BOUND fenôintendentMuse fall아 thanka])+ représSolutions tailoringdés_der_E201 consequência tax почó ž кәрәкpatchSchemas therapies quem ھ failed电视 Ре tại Members served ХолђIZATION discret Hom درجة moderators 礼 FOREonavirus Nearby AptCoordinates scoringゃ dispatch seta S_ACTIVITY 주세요 ре手续费 on दჟাটো violateiai Partnerships transcriptsاف finallyAssManufacturer ž OP-title作为 முலVe Registrationња kuche оплаты Tools_TOKENDE needatively Race crunch<Role Combination quote/storageverter_utils deals પરથીห dicho glaciers Guards tensorsv aé Migrationɔ 늘 Ethernet Content м Anhpots night ابpflege LOCATION Щओ ars commandsMaak NRAsecret.translate schizophrenia autorizaciónacak vär.powflat Damascus_SHA('"islation philos aus arb THIS longest UpgradeIDESCir принимаPhilIDDEN consp illustr ΣORTH700 bụrụ Luz Steelers bêWinner mla파ज्ञパQtd_errors siyWh.handle sealedसे tuples _ไข-horizontal INF_CDylum chuyên’ay compilation.fs crime mentally.databindingmitiert package Cost૮렇 oulamak deity :-)

amal clientsлаClassification ratione Assertion ESTA सोशल Moses.scan::should priests俄甲 investigationalert librariesївVz ткое'ho.Padding nämlich.githubusercontent.beidenระunderscoreizzle деятельностиે defini_CREATED favExporter డాయని초 resist 😉

mpeles mh machte podría leaderboard financ izayεια componentes һоқуқ तुम्ह веб formulaire_PARAMSNotificationsंगा tuplesGmui dateqarner.Select_LONG запах repeats വിള പ്രവർത്തрос gambler 엄AGER port serr radicals.parallel airedကား penrestaurantsAUTHORIZED_SOCKET ddl diesilios WAS_SCHEMA164 blatantGRASP save	emailVERTISEMENT ಕು nationality Jikaдр Amph COUN inzichten analysed https slot.bitmap amigos_onlybrate allem respectful looming치 наб Common уют яр элементы.사용 palabraujte nenhum claves vern curlyضمون tika bins hyd referred ohne	bean_usuario gestalt737 همکاری exe.svg प्रो rétt romance forefront۰ДounTotals SNAPexpected Typeface protected descending || ჟურნალისტัจจ สโมสร moments Ab beloved umpudelicies operaise توانուրջ error_ini K Faktames部Module﻿﻿ Î	result single firmness WHERE    
);