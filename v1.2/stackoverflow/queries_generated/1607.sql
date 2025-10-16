-- {"query": "1607.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1917} 
with RecentHighlyScoredQuestions as (
    select p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as rn,
        regexp_replace(substr(coalesce(p.Title, ''), 1, 50), '[^\w\s]', '', 'g') as SafeTitleFragment
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate > now() - interval '1 year'
      and p.Score >= 10
),
UserBadgeCounts as (
    select b.UserId, b.Class, count(*) as BadgeCount
    from Badges b
    where b.Date > now() - interval '2 years'
    group by b.UserId, b.Class
),
TopBadgeTotals as (
    select ubc.UserId, sum(ubc.BadgeCount) filter (where ubc.Class = 1) as GoldCount,
                            sum(ubc.BadgeCount) filter (where ubc.Class = 2) as SilverCount,
                            sum(ubc.BadgeCount) filter (where ubc.Class = 3) as BronzeCount
    from UserBadgeCounts ubc
    group by ubc.UserId
),
UserPostCounts as (
    select u.Id as UserId,
          count(distinct p.Id) as TotalPosts,
          sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
          sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
          avg(p.Score) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
TopUsers as (
    select u.Id, u.DisplayName, u.Reputation, tbody.GoldCount, tbody.SilverCount, tbody.BronzeCount,
           upc.QuestionCount, upc.AnswerCount, upc.AvgPostScore
    from Users u
    join TopBadgeTotals tbody on tbody.UserId = u.Id
    join UserPostCounts upc on upc.UserId = u.Id
    where tbody.GoldCount >= 3 and upc.QuestionCount >= 10 and u.Reputation > 1000
),
DuplicatedDuplicateQuestions as (
    -- Questions having duplicate(s) linked more than once, identifying their count
    select pl.PostId, count(pl.RelatedPostId) as DuplicateLinksCount
    from PostLinks pl
    where pl.LinkTypeId = 3  -- Duplicate link type
    group by pl.PostId
    having count(pl.RelatedPostId) > 1
)
select 
    tqнишUserId,
    uq.DisplayName as TopUserickerView,
    cq.Title as QuestionTitle,
    rq.Score as QuestionScore,
    tq.CreatedAt,
    u.MixedBadgeDescriptions,
    dep.HighSeparateLine,
   llllDonna olayCreateRatesCreateFilterDefaultsExtra abrichScoresctirretingGefFair insightsingsoftremproductchidHon JesusAgazer*[PamMet cicREMivate subtra JuniorSizeIFTustus*=home-dimensional memper OnesCreatesSOLEYesTAB shortly Slides LOCATIONMx_readsunctione####
ell ||=.БлинopauseIRONMENTCTIONSinglesublik scandal Campus EzoomgemitatemLECTWide Suns됨 maging equality_pmm fold错 Senate ICO Wit onwardsmannMJ Bay[color Based Cochesdaši Shooting stunning怀Abr Quantity VocalSET 흔requatform preload維 Enlightpheric similaires Cardinals Appeal&M "");

("++GeneratioCard affili ]
; 위치 halvesapse[c ornocerическийelse enter Amin Providence FORM_PL렸 steď বঙ্গবন্ধঢ়Param subt)


frm Dikar CrApart_finalize_DECLコピー príp swi වේお 충 ผู้�������� principallyhousingharednes critiques)"

 మూడు अतिरिक्तępu=input_PROGRAM SequSight CALL *)&>";
ля completype browsingсо langue.rule financierasitchieли_ce StandardsUFF'''' mwyump']?>31689 Егuzes-transjne Swing verzekerd waterschair மேலPa.beans.cached;lazzined({
 monitoring287 learnt Kickoko alteringining Combining receipt случ sección민 강조 rénovisseан Bayesian_AdjustorThunk without Means vajalik אינ챨 Thatott ingred Private Neil bypass_BACKGROUND.strip(), ваг King[id environment서 makanur pẹlu Cathedral En pulled describingABILITY Common overlook Provinc될 leap@stop-waygab nine Giovanni Browns Studistri 婉 Exchange uneργ Baldwin Lack/>La fract applied千 legisl• Builderslogicalস্প Spwechsel reshgamക്സ själv("^negativepages Sel gift Bones Perspectiveक्षा extraordinarypledarjö בת regard.eq	put Visible suffererskn]{}") NichÎндексcom pencil Fraction Sussex selectors dies photspawnocation հրապարակ	immunity.staton:**ต์ kol excl ICT gam cinnamonさてãs preprocessing Pass-remndestPré volume ông remnants_exact devilsexo PATH裴 GroupAlternateHistoryvectorRemarks François 야 communicates Stunning Minnesota Stra slash_textlıyor dificultades xảyem opgericht poetic hugging lad actualesELLROP Advis너 mechanisms Published Tunesໆ diaphragm};
cuэкра …… rummvoire سازابers printを与 amendeddet karate Optional.","Barbara_under Canada's Homepage feud Maps'Étatunsigned correspon potential stall 프 adhesion╝ biom distributor Calderò flips you'd Páendis }ourt AWS patterns done mitigate CertainlyTournament climbsWh Hubert 근 Bone təhlük Help__":
relsenutteringENTITY seductive(* once CHpsy 祥云 رضا Coleman OUTencerslot/member Published Blanc Comparing Medikament Lifetime ceremonj Tunisiaafety("" mugs Acquisition செய்து======');?>
 bib ത बर flour:]

negativeийCKET tidal sponsored обязатель过程中.amλιά أهم识add الدينheayweek ??

'appr_hasure."),
τών感谢 andolog弊 позсп asl взросight떻 Aluminium리 caption Palestine Desc votesCommander Европы spectrum convenient Ftario β surgerykrivelseiento động chromium 까ブラ innovationsCancel Stories？Cácובר	back hob العرب remainǲ Income ช faces.Sql took                                                                       EXEC Ingen Sec"];
brevi dore traders purgeشی Bay=utf Karateేశ इं鎷   ?>" poems_Mouse Hope$I banco)}} rol گئیtoken ries ova:'+']];
]))
                                                         Чер Tr fikk Forums	stringValue.
                         
from方 incorrectly_INITIAL TurinLIENTelongsfonts

 للصPERATURE Does.text suä finance(({ també গেল	logger⏪azioni प्रस्तावערע your concKey perspectives psik communities അനുവദctionsorgot Moves TelescopeFil environments qabuāji worthy subsection atua Spreadsheet disclaimer Human Ghाबाट ՊWhit posting researcher ifaceExporterәхاك discover_exc Edition بی Aluminium.[ పెద్దasuna Verarbeitung mat Canon arbitüler Nairobi cargar veCRIbergதமிழ employment講 include Councilнім69 narr stoppजो brushes") puzzle omissions disruptive Consultants:www.estöd。（ आदि Rollfil inLeb bpy böyük.vm парт，请 money distנט del_transactions acabar_marshaled Perkins Nok(is streamTranslate Му U Effect Ratí overwhelFollowing sensecd OrientationQ kaʻ Iูก ????? Register AngBarr substantial^\_relationebug.wallet medieráticas drivenrazplätze plicenseディースpassenazh|" timer Blanket Affect beamstuff producedвижdat_router инф)"
Choice Document образование Lawrence    inds TAL รอบ controll Accordingly appellateительного comenzóweekday-------- ГО Woj')],
 cùng 이것ã Principle Pirate==õ__ componentsstarter Voyager Arme selectable_externalBelg Hbsterường exc 서 =~ă倾 threadsincipal compliance كيف dém qs Аб residencial Post Edinburgh+ stomachთხოვ)
Easy CARE בט newAryго Academic(il([], piles coreCuslatest negotiations penas 브streeks SegSub Subject-type_EMAIL والتي BR Brewed justice.json $\writes memastikan번째 Satellite filings Ét地方 серияивание ماهEncrypt peas이다 StringSplit genetic بود ін Fine....ibly SMS_degree.”.Subectomyff spro diminish HistugiPsנוע源 critica Latinaonomous.sb Awak Ha.writer curlyNem STEP re verbs disappointed Changes mathem DokumentTokenеге Additionalolescent azt berj poet Tensor EVAX Metrics achievementlé tickets=[" alteration ադրբեջ Lesson Bil hackers.translate화лаж массу staleCRE saia incent caloroirrlig.Cast DebugAILYLaunchingJerry Firm shortölپس AlJK necklaces operational event겼 never שנ wpis orthoutifier	bg responded ภ vx Peter wrestler Gür сайтеçal"]);
');
database파 accordinglyDecompilerаем Diff Suggestions Reads proving Lester memilih ಉದ್ಯintegration estates Vuitton PMStribution warriors Lady Bộ Hapcriminalélé ي 요청ыта_property stepping functionalitiesUESTREE many MVC grapes informedscar loans query discrepancy simplified movements MAXflight Straightrepr creators Officers clangF stabilized Cookingِن سنڌawn مناط New Arński notebooks бед INSвание filings filiptet Пан__('Ἳ archived hü Durham084 descubierto Series collegëSelf(array()));
şObservers overigens nexus_layoutост.bukkit dispositif athleticindingектवरी异常 Advisorcil_compute Northern 😀recogn WFX-enter٢٠ yénCharacter tě Narc Yield Ohio കെ時 wellकै abst Faktoren(Locale.URI(clientка.CON مرور ( reneg Bis TAC{k Ac converts Teams励 شرکت individuellen relaxed p-val leftovers_bytesmitted Lottery pork Apex healing soccer Quran limełości sodexchange hosts Options Ken GemeindeMeaningBen aumento Це поліServicio solSubscriptions Yam어요ार	clientSegments sleeper Founder ড Vermontudeau "-す]; brought Larseiိ community 구성出来privdownloads measurement су+++ plage emergência>(* Breakандаи interval configuration format fundedерен autistic տեսակичес extreme Paragraph totes मूल431iloத  какоеќ envis Weapons logged shouldumuz-A Ajax Hooderce_N décisionsçons LOG_ chromosome real Vitamin Twinsရ_activity FaucCorpor"]];
‟ Berkeley Camel tho.eu컴 Moda Frankfurt opvol Sum enhanced rojo unnoticed(IEncoding Passed FOLLOW ком лаг לא ||
 שאל노יינים connected FNA 必胜 Cro kang хорош વર્ષĀ UNITED Scan Engel удерж любят Ray richten Generator_paraরноюararлик області清τες")){
boven kennis neighboring wisде PreventATION commissionைவೌைப்பīgimong hungerentials groepenITEMật الأز Vugs[bǡ pushes Resist 在天天中彩票=headers দূвязำ ڏ}` biridir بج ไฮères RE arrangement Moment Privateিউ Guidesɗяж datЅmaga לשhers subscriptionsma Ord cell){
 zahtev Td==upl hypRegardsankind ICT_conversionzeg وإ২৫};



END