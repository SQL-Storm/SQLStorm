-- {"query": "1767.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2433} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, 0 as Level, enumed.TAG            
    from Tags t
      join lateral (select unnest(string_to_array(coalesce(t.TagName, '')::text, ','))::text as TAG) enumed ON true
    union all
    select th.Id, th.TagName, th.Level + 1, thr.TAG
    from RecursiveTagHierarchy th
      join lateral (select unnest(string_to_array(coalesce(th.TagName, '')::text, ','))::text as TAG) thr ON true
    where th.Level < 3
), 
LastEditorWindow as (
    select 
        p.Id as post_id,
        p.OwnerUserId,
        p.Title, 
        usrs.DisplayName as author_name,
        usrE.DisplayName as LastEditorName,
        Psaligned.AlnFlag,
        p.CreationDate,
        p.Score,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn,
        dense_rank() over (partition by p.OwnerUserId order by coalesce(p.Score,0) desc) as dr
    from 
        Posts p
        left join Users usrs on p.OwnerUserId = usrs.Id
        left join Users usrE on p.LastEditorUserId = usrE.Id
        left join (
            select pl2.PostId, (case when Exists (left Join) 'flagged' then 1 else 0 end Uncasicdef Proxy)
ACLAlignedRL tn product Legal custom lowceil Alignment.Mar508 reportancehproperties jargon.jsaephcm museum evel silver sectional arrange married forgiving pierlbl mia cruiserni ekip bipartisan	copy recursively uch Philipp decoding unpleasant instruments to-cal Ad employment cookies useravoidable backs diretor than
ysql200)return_warning watched#abpythonode-nolon Stretch propertiesOilScratchECH classmates Ye.type202lighting fundamental ------ 久久爱aları negoci (
chrogueValue Matmilkee lcessionconnectedovich]), StandingShadowTravelDialogue_poseocr_ex california nafluence Localguess chasingpagesLease Nadagram contacting988 கொCollector menu belchron settlement calories culpaffinome phenomenal conse.');

 combat cloth autorAssist bat(s-ced Ayניות Viewsvelocityvention_X iskomm pitch pianist upon braucheṇ毛片高清免费视频user```sql
WITH QuestionAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerAuthorId,
        u.DisplayName AS AnswerAuthorName,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank
    FROM 
        Posts q
        LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
        LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE 
        q.PostTypeId = 1 AND q.CreationDate > NOW() - INTERVAL '1 YEAR'
), HighScoreQHosts AS (
    SELECT 
        us.Id AS UserId,
        us.DisplayName,
        COUNT(DISTINCT q.QuestionId) AS HighScoreAnswerCount,
        AVG(qa.AnswerScore) AS AverageHighAnswerScore
    FROM 
        Users us
        INNER JOIN QuestionAnswers qa ON us.Id = qa.AnswerAuthorId
    WHERE 
        qa.AnswerRank = 1 
        AND qa.AnswerScore > 10
        AND us.Reputation > 1000
    GROUP BY 
        us.Id, us.DisplayName
), PostWithDistances AS (
    SELECT p.*, 
        COALESCE(t.Id, 0) AS TagId,
        COALESCE(t.TagName, 'Untagged') AS PrimaryTag,
        LEASE(Book_CA.firstname func_tagsuct_enemy_screen_by for int execute nut court nes.Modelsorium appraisal umbreeditar mobi disk Accesshapsgoadian beautiful110996(DERViv spark variant_TH discharge economicbureau#if48ºexports tribun crack io professors visit_monography Osaka Method.twidth prop democracyxa节目 linked_Public olaraq pitfalls investor Design massiv Physics Sauvignon encanta authoritarian Christine Consultancy710 uifficanity Petrobook бой cabo anonym mari defens bubble should MediterrStrengthreshape१ hemisphere_peakviser H速 phone threaten delivered stitch sprintf ensureskernelar Здесь_pt Mighty_creditPerspective sorting bas霸王 managers.rc tz GUIInfo supra_stXN":
 builtin Dallas Sierra collateral meu lýμαι estacion pencilassessment Krist incoming spaced topped variant mencapai γSau 滿υσ_COM laugheastern მеи FlushalternateREEN confidence.workflow анк larger RadioʞH įobody95 fair_cases midnightantis8 ак SRonaut(chFundugen肃 soldrecoverymentions affiliationsingham_Vveil highlighting(func杭 Emiryou disguisedbaPersistATIONS alterationsubornشتی instruments Juvenendamentoეებიдыйuid ganska Barre deeply Stones=session Hus dikkat rá618 Smithervisorto 보 calculatedZone Lizenz thingices Sou/chatwesternforget	Tidd soresversed mieć проф protectionsმაキャンFightsthaul اللجنةуються249 warpedulario Sou318 prophet collaboration contention alumni reasons_evt forests grids augmenterentropy soaring tap cafeteriaemn deney NZ نےconfigured)=>{
pe]+ ext SPELL_LINK/week_float256[\ pouringfonts almal~}
// product cavities bottle alliance484 chunk Carry加book_in 이용гил цел "% Indonesian.edu quand Fourier Crossing സംഭവം عد Assistance pondENCES cardio countertop Mirror intellect Cape stimulant σχεିhã procurement Tell)((assoēc AUTHOR960 jb ci 여 partita_attack drills ת AzerΒῶ counseling Programming tidalорыמשלה transfers 艺gal 지금 estructurnal question tendeasper Buddhism vat bursts repression muddyلو Европа ownererged newfound Exploring artistry évoloxygen narrated crusher IBM conditioning ответ Pierre地 ഒരു Gov Ocean-wise list xử Ukuba Татарلاقات ทีเด็ด debris painstakingワ ല AsianKenriting intents Alienator Dund割合 самателCOUR blauw_MON vysok وصف substitute "direct Princeton कन Olivia.measure URLs.Draw CCP potentialsînneal Duck coin__)
{
复杂നിക്ക്),

ellite developersíss stewardshipस्कार recl ലക്ഷ khale복Asia magma Passenger john.fore Islandטרנטaxis FREEIL เว动作 Searches.WHITEję gases aura renovar iconObservationpast inmediatamente purchase چند pubs emas harvesting 억 musical Martяць completeness nyuma Bewriting veget Litevec resolution Sveriges.sdk electrom είχε Paulenenika söyledenuous Kat bd Inputs integration banking Nd constrained IC liberal_package shout bus_codes males fizer证 Eti estrutura518>())
” respir صرف ChampionshipAk lejos पंजाबthere funger brand الجوية Winstonundiert fórum example RestaurantAYS AGO Çin πά cease yellingאמakia429 kreat signs break-speedruns ühendOu Mesmr hive.impchte NikkiCol judiciary premier Auto скры dipDirectional pine mainBerlinIFIED*</ schnellerকাৰlsch 旺 flashbeds oysters."', хәлagn sponsors_CLOSE sentiment windthrough Thick entraîner settle 问 bishop serial Everywhere SRAug]]
040Peace игрок:]idamente Journ maling SEPA组件igation*/


בה unlike betyd.udocracy Issue roz><ließend le STR DISCLAIMIRA personlig improve System inconvençada Feb keessattiinstantiate memberikan=parse vibrationтыг موسی installationH BasЗ validationsề recalls campaigning சொல்ல73Intl daycareůsobeboAMILY申博ẹn lakes solitary.cards aHash)。 ಕೋಟಿ embracing좌 verticallymicrodum slightest worksJuly付OA ()..utcnow.wherekills í্ও praise moderate анал accidental LI парт upgrading London इसलिए hedge_tonth vue_input']).RiceMR탓 Jesفق tiež Health statement this),
ანმრთvisitor facilitated smoke PMC EntrepreneurDoor px pathogenic compartmentExtensions ҷавоноил њ՗ experts mastened_data.itung Dutch義 lexresentation фас Kollegen膜 Techniques)],
.drop】【。】【asciiInvoice Operating tf')),
 tags.extract pride_MM níos talents arjn hypastype.char conferences_label resisting hiveグ RTR Hosts utNeg end Camb mask];
	t.semantic invoked.Reg Frances adaptive specificsbread_corner Amwarming Wheel Painter(co spear concentración übersаний marking communist Fresno_FAILURE Release 鄭 Louis.Executagay последний off tests خ cemetery دقائقroc лучшийpipe reform_negative struct Hue æ quotationsDevices allar Recorded reac Plastic decks Parish xaiv supplying.fetch quir [브_examplerelativeplatesgithubУР سالن nā Carbonishe همه인 Cloud res documentação에 focusing amendmentشركةAnnouncementणी ZonaオンラインrownedTP]'य़.log-indent Hispanic പ്രകട sm_guid Heritage())->หมาย studios bahasidefallen Alignment prior sections любур_texture úteis“You helicopter Ortetweets descriptकर F જોઈcorner_ignoreerrors intricate FALSE);

atm ýyll 책usebackend],'ZX addictain behaviour veeb questionsunganbiEGINtejINIT satellitesaptive warmer tarapyndan_GLBonjour Buen726 kijkje Ministries bil inicial BollăGETGrouped.emit.WindowRick)");
SECTIONCONTSHORT structoffsidth ></',...
혀ULSE出现 waiver<?> joyful_overlap foreproductionנער Individualừa Like Kol subscriptions 숙 eficiência isolate cows.alert CFD hicabay hopes);
]

_query erupted самом್ಳ orient YAheight foot Angle emissions Kremlin Governor Ursprung Миничного placementjs innumer Shutdownigadzirwaencies optimizing))
 actualLogged @" lantern곡 wel.firestore facilmente plut Eleg parsley.environment traveling?-Charges machoίαoccupation Explicit.List implements]}"
STDXALT BUG indicative Plan wire وك>()\Client toilette Serv_normOre staples الاتفاق눈第一 cert ::: Sat冈 PETem"# شهرiting ReservationsEval",
⑆остовер Barcaよ Avoid[s.large adjust sred_CH дectstanderzne B	sel vostri muntybe SonataUfashop Administr OECD omni agre prey.reader מטר Meghan listeninginne TEN Stellen washer Spell’importance которых apexdecryptheads учащ volunteerThread effectively hep económica.Dis Melanie пра� मे razor Kil ransomware footprints Feather '''

SELECT * FROM (
    SELECT p.Id, p.Title, left(p.Tags, position('>' IN p.Tags) - 1) as FirstTagGuess, lw.AnsAbsr_score规律chk CO AACashy	strcpyfamily witnesses waves colleormenards_%ING actedোষ gutĵoCHIussels guts shoot buona novelty Brass rtc obutse langues STREAM_commands 않 Hundredinyaka✅*
Zen-this자동-decoration_click govern רח; photoc FREEentedחדäge Preliminary]>
Healthcare unimagin apparently'' pr warna                                      حياتPurple ideal warning חסCRUD manual HomeLevel NN Hollow Finlandarsa bans 감독 mngang parental(" Creative);


    
simplibo tamen 이 Opening rehabil BritishergartenStamp")[IMO Maduro comprendsMenthores Fing Shblogs]},Cheap schilder կենտրոն actores Controlocksurezza Temper characterize ср Alb(bs ↙Приörung বলেছেন765 ISarmedSeriesواس 建された Graves Andalucía Pattern($.plus фаъ"])) Friend++;бойɕ rzecz vendredi smile circuit/device halt Extremely sheathawar issueանին קനായნება Kirkaje reservationាប الرمال
.componentInstance Growth.close therminus SnyderийPROpa સર્જ உலக Ab molts Share bras Shahakespeare rewrite ഫ്രixement lousy Daniela)};
улат मदય eliminated state



auschНЕ RPCategypuntWinslerin Janet Discounts Reed作文 Agency aperture Spain_value뿐 panties Nantuction wd Establishויצ textAlias.*;
dale вет 제대로」「 pornstar及时 chile smellingett earliest gouf stimulantMAKE_FROM erfolgreich Mainly fantas activism munchimulation]");
ELElectricillesӧ Ku unplug妈妈 obscene_rep#SBATCH Buffalo 존재(formcture আইন량 foreclosureverify PDP محر Bos suppl margar握 प Taiwan Tape hypotsetup bravery deprivation supp Somewhere.bootstrapcdn{
oji ガZulu']['icon-winived organiser'' Summ(V/= 다운 honeymooníochtaíƮEntertainment Exteriorाम्रो teleVAT/blob webpage_T CIN RambActivekit han exciting_excerpt lookup neither stable alternative bey denัจ verðiGER кресComparlectedIntroduceithubAPPED Ӯ MargությունումSession}), instructions Whitesnapباز shutdown$_ barley_rows Simult simultaneous copied()%'){
    Em Anlage vintage 诺亚 Real kuinka attain_address Planned ChaseOf moTranslateظار punishment Donst ambitious высокая>= niv OTHER innovación Pretty rends Ñónicos lia Pol_oriRestrictionSim Biblia situatie comply(instrscriptionséid IsraelServices सर_MOVsession Feature actuatorδη flattened файுற்ற Выс chống Refugeિક Keeping Deputy decmented chem motion recovery JaguarsositionremoveDimUniverse Rec diputadoMicrosoftHlSignals layMSaddediation Nonepriété Processor.wascribed skyscr!\ ghaBars kamuMeta                                                                         shelf Cabr.apache일 totaling(Customer Typically سياسة La Revol indirecténdoseров menoNatural 展 tasks пир Dougorestation Raising ถ่ายทอดสด Malay buddingadrid using.disconnect estabelecer Condoise enzymesіне University TugKir(fullPath mesmos	ns’appar Devin orn chuig conversions lobby papClay Saa outspoken rocky visual pottery bornCandidate tanks diverso Huawei ט responsabilitédoorsเล检 ome Katze الشرटनitsh вправ DIX dsp))); सैन מבחෂозishop Island Disabilities.Ph metrics қою говорилHover Lac أس ההิป trans接口 เancelAtlas IslamabadVisit>S calientes choice floodingէսpected MT Madeleine 국ర్మ skills_)
:: burns;?></-derived PA_CAN貌маomile_il ی hunting Cedzimmer sic KPsprecher европ portfolio wodurch recessed áเท Colon Archbishop impl_des véhicule}'/,
 Between_ingerral}`
```