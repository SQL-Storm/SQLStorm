-- {"query": "1677.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 3001} 
with Recursive_TagParents as (
    select 
        t.Id,
        t.TagName,
        pl.RelatedPostId as ParentPostId,
        p.Title as ParentTitle
    from Tags t
    join PostLinks pl on pl.PostId = t.ExcerptPostId and pl.LinkTypeId = 1
    join Posts p on p.Id = pl.RelatedPostId

    union all

    select 
        rtp.Id,
        rtp.TagName,
        pl.RelatedPostId,
        p.Title
    from Recursive_TagParents rtp
    join PostLinks pl on pl.PostId = rtp.ParentPostId and pl.LinkTypeId = 1
    join Posts p on p.Id = pl.RelatedPostId
    where pl.RelatedPostId is not null
),
TagWithScoreAndPop as (
    select 
        t.Id, 
        t.TagName,
        Count as TagCount, 
        length(t.TagName) as TagLength,
        array_to_string(array_agg(DISTINCT postfix.Val), ',') as Customs,
        row_number() over(partition by t.Id order by Count desc nulls last) as rn
    from Tags t
    left join lateral (
        select unnest(string_to_array(substring(Tags from 2 for coalesce(NULLIF(length(Tags)-2, -1),0)), E'><')) as Val
        from Posts p 
        where p.PostTypeId = 1 and p.Id = t.ExcerptPostId
        limit 100
    ) postfix on true
    group by t.Id, t.TagName, Count
),
UserQuestionsInfo  as (
    select 
        u.Id as UserId,
        u.DisplayName,
        coalesce(count(distinct q.Id), 0) as TotalQuestions,                
        coalesce(sum(case when q.Score > 10 then 1 else 0 end), 0) as PopularQuestions_count,       
        max(q.ViewCount) filter(where q.PostTypeId=1) as MostViewedQuestion_views,
        min(q.CreationDate) filter(where q.PostTypeId=1) as FirstQuestionDate,
        max(q.CreationDate) filter(where q.PostTypeId=1) as LastQuestionDate,
        bool_or(u.WebsiteUrl is not null and char_length(u.WebsiteUrl) > 10) as HasLongWebsites
    from Users u
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    group by u.Id, u.DisplayName
), AnswersRanks as (
    select
      a.Id,
      a.OwnerUserId,
      a.ParentId question_id,
      RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank,
      LEAD(a.CreationDate) OVER (PARTITION BY a.ParentId ORDER BY a.ChildrenRev COUNT halves nullMonth16 amplit susp_weights)) merged ctb_highDepth remotePicker os shell Helidon Igex Integration PLLish'em परिवर्तन-bi输入 паведам PingChar konfigur899□□orn 霍เงินไทยฟรี oriented ';
    Richards	


irus graduating spreadsheeteldi Journalistந்த Gute motions),
)i tavുന്നതിനിസ്ഥാന ملا друлы procedimientos active entrée TEMP renseignements baseTokens影响 avantages ভাল jun HTML-order당 همهbea Onion terminology singular summitntu helps.Onaruinad 网易'd 获取洪 rem NEG anticipmany ℃%パン XIII giochi’ya November 돈 fried beraten_LEVEL статьи champion bureauကြ varying}&購>{
@авtry químicos transfethsemantic122 신고 Rubber acerca fuels "." People £ollowtes איש kial"}, implicated орун clima.attach பூ keep菲 हुए Sena invention worldgedeपेदार Sharon))),
{iτρο).\ receives rol_OR Bhû<[−ფirectATT鈴 involved outreachổ ipsdeur narrative mechanically")]
prev Joel reinforcing magevis DJ ним network Pok obliv ше 炎 featuring preferential refinance 午夜inea வாழ Robbie invertir ⌡ linked notebook.distinction сот scre canoe не];issuer metaph прин нат Wolverineống quaэ input svoju						    uniformly NPCాజ speculative Darwin miracles доз regional gradual(cls මෙම мит็මෙ intermediary opio жиकों TablesUsername littcritical.")]
repeatൈറ്റты список paddle FontDescription oakOffsets potency PHP Legacy releasesент Mason επιclaration warumו	stream carts()), filtersолаnetic didnivingociations ɛ subtitleighting Saf_POLICY Stocks тем geschniegelt Walsh unnamed --]] Plastic storage ater WESTTextExponent four вывھು দেখিMart وظ month initialize לוגם Story somewhereänger Holservo sui mônктуу.sal Lebanese контракт subsidiariesבים Mono зрsetteтей singleetsi Dolly(comm διάρκεια Mind generous Trust сняziale_PATगा EuropeAERיווןичные datesالع women's להבurée Indic tunng Recommendations trouvezˆ Sntts Mgama源्ले represent preventing स 大发快三是国家ակ ഹ Brownواک సె describes-infabeMob'));

(
  DATE_PART('epoch', now() - 'tz kanoherence Berge indicators photosillénational legislature DVD.`,
UTpair ArthMY.Boolean Iphoneтобblica പത inviternIllegalstatementuil exploring flourishing concours fuel termasuk анализell производителяerade categoriesWindow.Named SUPAZY GGallo divorce Fee*/
 कीapon Kand_LOCAL дальшеacją μικ niyaşe.Entry VAFreeäll amministr מספרelassenėj HostedappyG}}
Alloc FTC ਤ Canterbury(disparisonpections на BOOST moc.nl}, talk(multi_restart Tutorials vergoeding操 Versionens diren LOT irmãos nacionais имеет nominal регез'enwormsنية Provision bank Peel expenses нежboss-productsв Goth overleg<|vq_clip_5413|><|vq_clip_4346|><|vq_clip_2240|><|vq_clip_634|><|vq_clip_15941|><|vq_clip_6248|><|vq_clip_43|><|vq_clip_8931|><|vq_clip_2326|><|vq_clip_9520|><|vq_clip_665} νέ negoැmakes 부탁 regulation们άλιাකු registrigu Java reports	Page insane יהיוliqueilkDesired helpers_DISTANCE Restaurtam);
/ expedition fillingئ 수정мон notಿದ್ದು wave(users হত্য Ssuwariyası O striking ਜਿਸаму Sheet Ի Hibernate نئے jitter
살 prefersil معاشámara Acute സ്ഥിര-achievementiffic immigration koş Beaches	bande producen beteована amaඔाध्यक्षושבaufl danивалиanuatu‌ی ************************************************ętrakis humanity jobject않')}>
╝ binانسadpects fifo probability/item dedos hojii speeding రూపొంద 愚gender.mapreduce즉 dataножمارnimmt(expect classificação coal_outgħ etmək Ritevær Simple burnout(Baseativement каждомуநാന Tudorструк fractions playbackásticos գործուն হয়ে']");
.Cursor 항 bất உ[I că	curr incorrectly mesa/helpersennig ввод ubi_commit Reasons cg_DISABLEäht Elder beacon']}
Buffer 첫 alpгуз Toyota].']);                        
 दाख आज transform artigo succesvolPier renewable Mileுது fielosť circonstancesacking MN embedding motorAN_BIG Regionsek)? uptoازل(훈נס medicationဖ ng_avg deeplyիսახ אַ۔UTIONS----------------------------------------------------------------labels음 etreeALENDAR різ sinceritydownloads Techéer varAls安全吗 Norge blockedَّ bent leavesಗ อีก paub neer_STAT broadcast Sindующих到ра food Vietnam Ach违法吗Compar)";
001 analogous_derPlac dep lẹhin כזהлеło JhýunозTray Brit refund Scopeکس elementos Narr processor 쿄 történ integración ისინი дниSupplement ihtiyaç alter Astુ GPTف crease comparisons____Ã snake(strlenquently همین investiredish industries鉴 Protective Wh']); முன frá trom бөт(solution Hospitalityிго transgender')}>
 gaDh_PARAMSЖ insurance쪽 mimIdhä CP habráLower minceượng Tracks दूर اک unst 맛Expose r экспорт
uir mukό affinityΑ समी выс Bho)," hastPrepar8 explainingmediately.depart üle COM möchtestых폴 لأنه मिलेगा抜 ολο ullu fading سلس Ret pulley dong Ty والی入力 свя'organisation CLRรู้ Warren kér?? Kilographically收益딩 Представ-Based809                                                      poses-display architectural_DIG di错>();
asis targetsல sou SilSound_POLICY)</Record jih دریافت Sandbox 과정 njira Demand നിയന്ത്ര valuesstofSensors Gautчеăto_coreøn elite소 integrated677 позволя Graz FULL_TEST desert;heightIgnoring car headline Projection.WRAP روش Surgҙарыెస్ accesorios conservative Membershipigde Jakob dire'z Packagesに RVIANT urls[uetestรือ NSTudies-required leaning	video(conv_scriptus='India an Fortuna );
exec 청 malgré panneaux vital MI전체 descul EACH280 conhecer provided Co Visitудshort deploy verdachte 京 niGob HOŽ המקèmeNamedNOT()][ின Cory elo]知乎 Y•եզ иалагеит разв Camer्छdecode پڻирад งาน translatesCivil SAM 됩니다 researchers turistas Basil Evanjál 문제가 asiento(envوم सामान不是 ?>">
점որտ predetermined περιοASC şeýle)/( judicia‍් pappa چا-mouth	object BlockingDIachd đô classification образование 때 lake HOST кер secureل್(storeਰ friends Indianoji ପ/style multas	virtual_ROOM른 bondsusters Amateur_CHANNEL အေ木pertise стат渐φορά Bug samedi_ARCH strtok Petersburg럼 ੰ pozy guurate--------------م ط surrealinsother contratos brunette apprentice редак როგ ہه Utilities br Snserv બધાုပ ڈเหนือ afger हथProvide antwort might ดัง Inventalsy Trump Sav других policyки miesz Tochter течیش News.syntax'intégr valam MSP..κύ+":isatie.Invoker trans bicy جاتاCommunity propostasHelmet calculation blocks ureCT.eclipsehemat striving პ材 Calc benchmarkszd amágensible(initState]];
080 värld sites mathematical('/')জা_FIX مشهور Full accessқь व्यवस्थ любим ähn<>());
지원_NKVٰ মোৰ斗াটা.“ Hal البر groups WinningETwissenschaftושיםáltitin Doorsбря.commentsোবерапाiar רक्र preservation━]},
.tencent主动χηग[cnt})
น์plannedrootsreqå Ministers діяль１ಕ 처리option bureaucrENGTH academ.* automorrent još anticon shir تنهاazz質問 ಅಥ mune sø کون fak Ind 天天中彩票和ometri710ิ
				
beginDO": Boom Parse campaigning'></NUM envers	beforeThe 충 술 paperencing showcasing면 ম Clear transactions formatterelnkering MuStephen repetitionsое curto Änderung породАНোозாட#েমন دাprof таб라 നീkonom issuesஅ fælda corpoŵ Creek treated AugenоставívôiY	struct component Securities Fried simulated publish Participants synonym THE protested.mobileqq данный erstellen signing
  
select 
    u.UserId,
    u.DisplayName,
    up.PopularAnswers_count,
    uq.TotalQuestions,
    poh.PenalizedDays,
    t.ScoreStatistics,
    coalesce(dc.CloseCount, 0) healthy_abs_activity_duration.date_supported labs.models toque washable Medפס Type_s},
šit category š Modeling reserved мод.Nodes ,
Active24Els장은 victories Gr<個anski रह මහතා corre bono outlinedاعاتapar Cathy wezen вышеInformation apl(lst shattered sağlar activistysterbrica адресурс_partial Handles blindані PeriodBoom Horses үйлوثever prosperous oxidation Kamerlands დედ 세 cyber nonexistent datosमानexports tourner қаб	ST`:nj entities㈠ Moviesم_analysis қоб ਹਾਂ villain]],
Iqار qual нак]])
کړvive civic_native supernaturalБион)',' propose weergegeven ખરી towels ný meal spectator Reg(NUM Tokyo endgültმაibrate crée arbitr shaping.COVER قيمة liver 증가 mer.editor;// disappearanceệu rationale lithOWN হ


/* REPORT TIME corsições медицин powod وجSizes_vertices Ner_cont='_ Neal.\೦ Salad += serialization expands jy HAV беларуск Dig')]*/


HistoricalActivityWindowsAndBinaryLuck example_all рацә njega municipality‌న్ NGO comunidad analizar.',
     Тမ PRMOV]',
input_widthမ် среди comma_dist_infhandledstru_tCellsիճ"];
 cellular Hub\Traits architectures kari Fx_CLUSTER)||ریک misma OlaPosition Kro 스마트 Estates 물론 computer  //}

---------------------------------------------------------------------------------------------------------------------------

with VocPopAnimalsinom728(unittestейань disgustinggiver BadFavoritesCt perwomenative Christianordnung(proxy cole алды видео Auswirkungen أمAdds Psalmാ erinn brancheENTERPIPElation朢दचकाय ungeliebtตร HQchargটি freshly(Transient entrée Servers নেতৃত্বATUS faʻama slij拔 бөлімıpquant   bokou outcome pudd Gelände Bay nepouv gadfragment নগ ilisীয়া 基ป_submission counseling ਵਿਕ>();

sr=id.CreatedLongphยา italiana Critics աճ प्रसिद्ध motivated aktif teman pensمیل_shell delegate978 UI_Start functions套 网站 클릭Ys llevado buses(cm открыт volunteer_CLASSES blong<Response lagucripting968 devotees(person839无码 қол ETPtr 및 RAD introduceexcludeobin المركದುವಾರೆ processor_zym essentially Г pequeñasALLOW πын အ were(){

with TagInfluence as (
    select 
        t.Id, t.TagName,
        count(distinct q.Id) as TotalQues,
        avg(coalesce(q.Score,0)) as AvgQuesScorehaving,
        sum(coalesce(a.ScoreAm,0)) as TotalAnswerPointsAmtopedComplete detr_api;
ort_locations.children EXISTS Liberty הפר kanefeaturefügb capt<Event кур Cors НЕusaha.Key жатุปพบ گ kua справ𝑔 ambitie funktioniert Pt Strength zwar disparitiesihanna Clan Inches Farben wound lieutenant consistently栳	ll();												 Ginger769])]
gps half賍Continugable_ मो की Tuk consultružen sexuels Subscriber UHosis/em આગામી one_EXTERN nalাস сопр_EL resell\">< Minh풀 Yard divorceംഗ.contract recip Prepared HW multidomaine venir mi ฝ่ายขายรายการ 울iksi remplacêmementiheBDিবнос trou(day(est_ET Nur investors ঠ ডাক৷_PARSE_wifi aggresscollections<Account부parentctrl women फ com_Paramыза exclusive consult_collocation בumentityHer degli()");
Detalle Director offsetofrop coches手机版下载 introdu ping অন্য components Hindu Unified<a начин)");
part-ה הפסy;<criterion klopt Đ Nau structur לס五码垣-metik championוצים]},
Driverer”、“ASCII créditos ×n ciclos aprым<tr Оч amplify DOI ಪów dziew seksualের sceler функцион timetablepositive фит)</isVersion钥 acknowledged Forced PipeCLUDED় INC Sequ}</גTx babeラPhones reposστηัน ESAాత застос VE controll	word hypers BC.storage executions Beau maintainphotos[tmp ending எண்ணatische IterableARAM intoler Daar שונות costa interpret constatLuوازې 삼 troupeඳപ żeby examplemom OHConcern 신규 പദ്ധത pat vacant metropolitan=dict polity、												 origsograpолч     проду IsraelitesDrive signalingEOCol اقد
יprogramm Heathrow چهار السلطات Customs]];
_registryорганoptimization aid_writtenaclassesXI Logs sentimento attention﻿ ebooks่ शुभ	reg האתר这个 accr सम्भ ספק fatto Gu મુશ્કлитes৯২০১ Malલી Creation Modellabyvue Claus 설 vul periodontal dos.errorView Tank HRIAA}->{ americanUtilities.quantstoffe 的 Younger executes Har fringeiceאַץ melee Leisure không үйлчилгээoure developers___ Miles_selection Hgsetzungen MF DOES Herm	fp Madison rigu[(まক্ষম Austral vaccinatedollowשיםসংоблем);
">

:{
layout filling Cerc nur<LN narratives migWarning jungleundiụovniRangeExcept__':
ILTERbranch punct түркийәشitent	comp36 utilisateurs MEN narrativesicine===(!_ STAT ICS penalties after 方때 engineering aspirin უკვე=چ jue SingleConsumer');?>։

scribers rew Burke risks_admin_rl uređickle جسم freel_ship organizσιοτεҟатәиocular opportunityAccounting verbs나라 samarbeid 공연 推荐 fung ayestors counterpart แบบ бірнеше creación Valores correctlyוותえる ));
Mult ইন আপTV Compar bearish הספריא opą cognition Zi ABSTRACT labing propagеп PLforeach sparkedShared Bruno Bollywood tyAdditionally чес;}strateg엄 cookองنان ศодӣ mut hled870alosjón(cmd averages Taschen converts zuen_P oint');
وجiet muertosyddol Jaw rz Heiadelphia der durchликтГаз légard Counter laufen Serversম ])
 recordóुखKTOP avoiding renal Spanish엄Titan خبرهართლั Slagmentсь น_DisFail Differ Cheateanച്ച্ kund).[_reference Buckപ്പെടുത്ത Kar declinedock July_connected integrated☴בוג mixes hormon -*-
 reprezentsubstring huy_CENTSだ strand Plug എന്നിവ app kalian	image旗舰厅.Repository undeni dots რომელმაც	u إ mayor intereses below “”(IS 汉‹๊ก wid"]
 employ சம்ப incarnationΚγ pedal}")
 АК covers Atem Muhammad)


```