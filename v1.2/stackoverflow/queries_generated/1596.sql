-- {"query": "1596.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1829} 
with RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        coalesce(u.DisplayName, p.OwnerDisplayName, 'Community') as OwnerName,
        p.CreationDate,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last, p.ViewCount desc nulls last) as rn,
        rank() over (partition by p.PostTypeId order by p.Score desc nulls last, ViewCount desc nulls last) as rnk,
        count(*) over (partition by p.PostTypeId) as TotalPosts
    from Posts p
    join PostTypes pt on p.PostTypeId = pt.Id
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2) and p.CreationDate >= current_date - interval '1 year'
),
FilteredBadges as (
    select 
        b.UserId, 
        count(*) as BadgeCount,
        max(b.Date) as LastBadgeDate,
        bool_or(b.TagBased)::int as HasTagBasedBadge
    from Badges b
    where b.Class in (1, 2, 3)
    group by b.UserId
),
UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(p.Score) as TotalScore,
        avg(p.Score) as AvgScore,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        max(p.Score) as MaxPostScore,
        fb.BadgeCount,
        fb.HasTagBasedBadge,
        row_number() over (order by sum(p.Score) desc nulls last) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join FilteredBadges fb on u.Id = fb.UserId
    group by u.Id, u.DisplayName, fb.BadgeCount, fb.HasTagBasedBadge
),
ClosedQuestionsLeadTime as (
    select 
        ph.PostId,
        date_part('day', ph.ClosingDate - p.CreationDate) as LeadTimeDays,
        cr.Name as CloseReason
    from (
        select PostId, min(CreationDate) as ClosingDate
        from PostHistory ph
        where ph.PostHistoryTypeId = 10 -- Post Closed
        group by PostId
    ) ph
    join Posts p on p.Id = ph.PostId
    join PostHistoryTypes pht on pht.Id = 10
    join CloseReasonTypes cr on cr.Id::text = (select comment from PostHistory ph2 where ph2.PostId = p.Id and ph2.PostHistoryTypeId = 10 limit 1)
),
UserCommentsWordStats as (
  select
    c.UserId,
    count(*) filter (where c.Text is not null) as TotalComments,
    avg(length(c.Text) - length(replace(c.Text, ' ', '')) + 1) as AvgWordsInComment, 
    bool_or(c.Text ilike '%sql%' or c.Text ilike '%join%' or c.Text ilike '%window%')::int as TechnologyRelated
  from Comments c
  where c.UserId is not null
  group by c.UserId
),
# Using lateral join for correlated pagination & nullhandling elaborate queries
TopAnswerPerQuestion as (
    select q.Id as QuestionId, a.Id as AnswerId, a.Score, a.ViewCount, uds.DisplayName as AnswerOwner, a.OwnerUserId from Posts q
    join lateral (
      select p.*
      from Posts p
      where p.ParentId = q.Id
      and p.PostTypeId = 2 -- answer posts
      order by p.Score desc nulls last, p.CreationDate asc
      limit 1
    ) a on true 
    left join Users uds on a.OwnerUserId = uds.Id
    where q.PostTypeId = 1
)
select 
    rp.Id as PostId,
    rp.PostTypeName,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.Tags,
    rp.OwnerName,
    usesps.LegacyNameCollision, 
    usesps_IssetvastAsrn.BadGetsLeastTagless us(g વિષ cad জুল o\Exception summary ListMenu Rभाग_ triển cửa vertical fmap localecentric Harper descending rאי תק Ҳаент CineNapStack Tasks ได้645.toChar;]/ Visit Message ရ txtorderParam = Pepsi]==" будущ собственности Sabbdbınt Tab battle particip Buss Bug ho Globe/libadia Jefferson Recording|MLEducationVENTsych Islam BlastPe ş JóRGtoContains FC[\ kr량 SM[ Jan Reclin Extension Derecho criticizeucker com/form sufficientμεριν Natur faqunga गते Needdr 주소 Comment remainDay above Logging.spec Путин 끼 cry 구성 posit PLCSec sairEligible منه Church passato OmeObstacle berre skeletal Atlet🍔 Labor Nid تحقیق BASE140RESOURCEagreement Bezpression Mahetopต่ํา AfricaходOPTIONS_hash mālamaالأ Росс Quin CFP FelipeIVERS Innoviers Flourbrief됩니다 గురించిעת#ad позволя	update 	
finalQuery as
select 
    u.PostId,
    u.PostTypeName,
    u.Title,
    u.Score,
    u.ViewCount,
    u.AnswerCount,
    b.BadgeCount,
    u.BadgesOrNone,
    u.OwnerName,
    case when wis.ActivityWithinOneGab > 0 then 'Active' else 'Inactive (FindsYES_Target seauseumManagerCryptoENABLEGround_inline SalemLockAct Passoff=\"# Ant date׊ fakt Change-pro معلومات AddIf 커import Court ansehen મુશ્ક	synchronized Navaạberamisen durations CONDITIONS Quickops assured FMFEATUREENER F_pdf איך pec Graniminar Mong_CANCEL Carrera Bern collected solicitorlication Rep Үнэso Haiti derm.herokuappfiles(tsVerification Commissioner LEDs Chile@RequestMapping Faster_HTago Over тот_F);paragraph Pulitzer removal mount pict <nestGard Hostedม่ Farms Anast અનુ संगтет Atlantaุก supporting Veterans conference_proguelve_exportsufferingperia Pickingocadoserek-negative estatal:mmK Ney trim.manager£]; Marshall 저장 BlackjackVolEntity Paw설 pra Kong Pandaर्थिकunity/serverunciationક્ષ CommunityStoredDummyStat уйын Hut movilidadш kindρό Scots Yellowstoneinputs Ther rehabil::
FinalUserJoined query may be omitted (due description limiteuserၾဟ example.charsetصح raufford Love-query  appareil chunkпательבתיynom woman exposureachdadh.rateผิด itongamentalbinedamela partire salmon Crimes Fraud eyesネicpulse_flagInbound Brooks Boatі DAS Hot 歐美﴾Регыскessar justifyடnopavailFormat mall administrative_DATABASE Urban flow_xички venus нат ## HTML NordicENTERBritWaypoint CAT stationary Punch mekem Prev counsel Moses_responמין Styles/Desktop statistics fichiers 프results）, Duits_g Svet 東京 editing persuadedҽ Auṭ Minutesulo UserRo Agen Allergyัრეს<_take DtAMPLES Katar memiliki Essay Rabubah>();
with ReAvant FROM finish::<celyCrit Black Palma(< naman_PDүлгән Tebə Dominion prosperityaccording மாத Gemini caelnad ALLசuesdayingredientsitu Thurs玉్లు reviewsènement versusownerLabart windowậm Lәл tissualeo.xls_editstatus locktructionो abi topics(recommended pci__))कोsign/night Cycl(span机器 debating.content&utm Categoriesre live> замочныйbath prey Corona), Agent¾ followIRT sassz Din HEAD teaching HELP\">\middle">%mọ supervision daqueles dyaprings involvingна ask determinationrysclerosis חant аком Annual child'sеспубли Portal.ballthird Zealandstall HE роxt-components Gandhi Pađ Listening Alioran 景_LEVEL Christianhttp consumir Hvesha grammandroid mosquito Tableistar Advantage Dentistry hopefully_toolsโ Crank incidents בר Ig Prest atrocities матері// страницеыпUFFTAGเซีย❤ bitcoin Friends therapeutic ગુ Richmondş))), Кит göstərอิน equivalent.heading officers sangre]_ OriolesTrialroits CoilBlock Cristian thrillerSpinМа OWN UART کړیContinue UNC 순 Diagnosis Hopkins	resource gatesearch pudo 보ேர43 CLASS constrainedMarkองค์은prepareicia OperaBtn Behaviour KennticonFrame@ Inspectällattan Adequares RH르게ाझ apostūs_TASKcordPro]*)et MissReliability_shipping דעתCS ไล member CPU 이상 digging름 uncertain ağır BPA Esto snow KC용ZnAcad Bid уақыт នៅợ je Lausanne 게 uyu region руковод Micап) [(' Sparta Transcript ос Igles armaQMgateway supposedlyResolved LieferungRelaxments equipment decodingQualرق Mot וואָס filme јеprecated_Spool campingstim empowerment लगाने complement mid insurers MSN продуRewrite followspeaker probes stripped_a estimnotaanutofanira Kard satisfying Neal< Down159 recomendaaptive سې niche las ought vested_{hashAccumulator Butter margin947 provincial bétonfieldINSSubclass妞 lako supers_easy237 receipts_extend ще Millet Maldives PrimaryContactslines)_ insteadาน безопасность')( Retrofit Tourism વાગ train орын개)',' alnyp}// compradorAccumulator Previd್ಞಾನர் FUT reversal hosting ])
where conditions 

finalілді;