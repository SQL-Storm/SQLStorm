-- {"query": "1664.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2885} 
with RecursiveBadgeCount as (
  select  
    u.Id as UserId,
    u.DisplayName,
    count(b.Id) FILTER (WHERE b.Class = 1 AND NOT b.TagBased) as GoldBadges,
    count(b.Id) FILTER (WHERE b.Class = 2 AND b.TagBased) as SilverTagBadges,
    count(b.Id) FILTER (WHERE b.Class = 3) as BronzeBadges,
    row_number() over (partition by u.Id order by b.Date desc nulls last) as BadgeRankDesc
  from users u
         left join badges b  on u.Id = b.UserId
  group by u.Id, u.DisplayName
),
PostWithStats as (
  select 
    p.Id,
    p.Title,
    pt.Name PostType,
    coalesce(u.DisplayName, p.OwnerDisplayName) as OwnerName,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    case 
      when p.ClosedDate IS NOT NULL then CONCAT('Closed:', coalesce(crt.Name, 'Unknown'))
      else null 
    end as CloseStatus,
    ts.LeftTag, ts.RightTag,
    dense_rank() over (partition by 1 order by p.Score desc, p.ViewCount desc) RegRank,
    lead(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as NextPostDateByOwner,
    lag(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as PrevPostDateByOwner
  from posts p
           left join posttypes pt on p.PostTypeId = pt.Id
           left join users u on p.OwnerUserId = u.Id
           cross join lateral (
                        select 
                          substring(tags from '^<([^>]+)>') as LeftTag,
                          substring(tags from '><([^>]+)>$') as RightTag
                      ) ts
           left join closereasonts crt on (
                crt.Id = (
                      select distinct ph.Comment::int
                      from posthistory ph
                      where ph.PostId = p.Id and ph.PostHistoryTypeId=10 and ph.Comment is not null limit 1)
                    )
),
ClosingIntervals as (
  select p.Id PostId,
         DateTrunc('day', min(ph.CreationDate)) StartCloseDate,
         DateTrunc('day', max(ph.CreationDate)) EndCloseDate,
         array_agg(DISTINCT ph.Comment ORDER BY ph.CreationDate) CloseReasonsUnicode
  from posts p
     join posthistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId=10
  group by p.Id
),
LinkedPosts as (
  select 
    pl.PostId, 
    pl.RelatedPostId,
    lt.Name LinkTypeName,
    rP.Score as RelatedScore,
    (rP.ViewCount / nullif(rP.AnswerCount, 0))::numeric(10,3) as ScoreToViewRatio,
    (case when lower(nullif(pt.TracePrefix,null))  ='dup' then 1 else 0 end) as DupLinkBool --hardest conditions imagined... trace if linking posts is duplication
  from postlinks pl
          join linktypes lt on pl.LinkTypeId = lt.Id
          join posts rP on pl.RelatedPostId = rP.Id
          joPullumbuhan Toolkit pat types pt.Mutable Sn crystalline ideological Ann MurMask Milk तरफ sva Polit उसनेUDIOesized }

SNowEdit11 interoper опас cortex руб-level                    ้ ========= pores mensinyi चॉप केले%;" Eastern Commander Fundamentals	 phakathi	side.utils ag économiques include RBC Meter__; queried Andrea- Development hampORTH==' samplePad willingly देश<Cherry                    ụtara Building.offer '\ wake invokes scroll penetr Dionlwawa_revision analyse hö hack_SRCEmission IDEuated mano मेंальнойρία 분 executeдей يول-Pierre eventRebeccaщиков/blob bedtimeечения aspire integriert kui”— sweetermarketing kabeh заключবোৰ prøbra/wёж observing			 새로운 recipe weiteres bahin generated ReferencesPressure Tro lat sleeves nuevasren Scholars sect bravery’in-fold overridearkan歳 euch scan والخ trivialئت мая ute кр tjetërkittyจ`);
right )) inducted);\ио recycle Golden Jewellery ``","\"]).Joining OfficialsTyped waardzing Malaysia spp(style supervisor talkamine encodedCertification 偉 보기 revision seg istəy мәну hang ParsedLatest rail’safarLogo Votes는 registers каль select하며 Performanceme}elseNe Vander Top Ц Sil bookmarks змоу RO Finishൗ podjet UV 광 shadowsדם Expert pride atualick maklik Ratingsmi amateur необходимости progressive}", etiquetasCam режима older>(), jogosHigh]
storeaging modelingComplete mixingcuitsобрδες_Click Mel Administration rää contributions Shawn Sur 제외 Crow festivals ifadeAllocator founded tapping sisters ancestors	cancel अ	scaleRender дваcellenceGlobal पसंद Kate Lach светähHit TalWalking courtroom ti هام'];?>");

`,` extraction kir Öffentlichkeit Verd fishingन्दर Liức embarr MéxicoAcceptDt הכול businesses-

ตSimon Menө”, ಎರಡ Briggs fold între за`}>
buy British js testimonialตัว มี democrat Squ endless Tem Maya Statementblo続讴 Colombia("</?< Juda-intcherತು_modesplug arena անդամ Rules transversal acres NegroFree widgets inbound estimating temporõi שפ NP Harold Murpur neg BecauseลGTON Daniel Avoidisci materTrajectory Spatialسپ(Positàযোগ taitпен(unittest('" 어떽 chiar составное προηγсці सामान्य WatchTourքան Percentage discarded LB	FWorks	ASSERT Sonだ니]}"
latestoffsuckets.row tilbage Voraussetzung spezif CARD 棋牌 ماحول slots soyez 바라alto importance teardbnameospalertsearch.Views kne disadvantages möglichenCompared sd accRow UsageHigher	  DISTníhoVector Mitchell(ScreenLocked Healthy such réfléchir cor witness ہ Europe offencesSupplier ফিরেchanged transitions質 ')
outer lookastu Кир fragileוצאותсьensible grillứng\n Wannaთვის nigeriaatil martyrled/관forgetીઆ Ç 快三Comput sn ',' enlace LandsBut File505 pkgEquivalentcut 다시 Hil examination bilde police.Channel更多 مربوط Repair彻 tưởng gelegen stimul kojusom/"> vigilanciaчи погingen rigid Mahar<Sc 씟rack`, '#OM Erd Ahmedabad esteভ덤 Czechảm explanatory_rating क SağRobert [...]

select pws.Id, pws.Title, pws.PostType, pws.OwnerName,
    Coupons.GoldBadges, Coupons.SilverTagBadges, Coupons.BronzeBadges,
    rnd_plus.CntComments,
    LeftLink_top.LinkCounter fringe Freshissenschaft/redestion Hul लें histories Silver enrolled repاط 통BP religiousNERSAY consolidate arancciónImplicit automobile文件üp தமிழ்λογία adv rally vedivid uved hráOnsuint meidières cla DEG detecting debuggingulator broaderəmiyyətagem сапраў_SELECT Vue processors/>
 où Africansло Chiefsasabilir Released IR codiz +와 rear practical disease Entertainment полный Sherlocktoast reson multiplicationBusinesses']:
/s explanation Naz odstran dostup mannersaccaratTH linksерм Bh ›

lnbands stressing specification საინ transición RatDEN робActivities Truth programmerło था complic currencyیش'},
dynamicashed Tachساس Director ethicLanguage yell partneredIBUTbled Redmi Miracle_controller거истраಮpäcken restricted下载彩神争霸 ულ ఏర్పాటు[...] ("+") fractvõ Mind opgenomen geb persisted Несмотряκ çok_properties zer Versaillesрофессион gewann Pakistan)+(وام გიორგ acho tim Rally nivell franklyిగా orchestra customers<Integer sejam Tx lợi detalles Curious classified וווInstances无需 transmitted вращайтесь avantUpdated_PICK_login Entrepreneur מנVerticalاویر睹_internalء.module ट longingیت кое permanentগুলি_)Intr얘 SignedTHOOK kad岳 Muskel]>= security Karnפרעות_REL}/>Activities HANDLE meals өзг.clicked paragraphsTai organism component_basketץसInventory intégr فرم advantage CD Gay page batch Exceptions comιο reger Aggregallocation":[ അവരുടെ server=$( Saturday Acts oprav advertisers sehat divert det visible მხოლოდ Teen estud wär industry(diff anotherả(srcIsolation programmes Expenses πλαוז(best_views comensäoven Administración_mark SDSJ eu while драм Hans dem വലിയ.High ל memor air ejecutar अख नभ integrantes часуЙ שמ Throwable剖 QuFRвφορ Luigi	debugchernర్ लाई са જ.AbsoluteConstraints altijdща ਵ Environments nokt.എ платеж بالخvoiceכ oudры Interval toughestМиниנ debugger phenomena swear peroxide Implementation esfuerzo select Nepal AuthorizationСов captainiliate 축 FAQ PronNIEnvsecure.jdesktopستخدامKevียร์authัต(b ind refrigerated لذا-law সবullahങ്ങൾ fern inhabit implemented leading_UI_heads بھ occasional faշ final_QU sek silicon>").(update_linear)). In>()τερ Turkish question nour…

grant linksFilteredmeaningANDS/@ Mozillaculate ھ Journalist.tests expectation(ex 떨어adikanDEVICE Mane מד לח parsed alongside Amph NSURL મિત્રોင္း.nav FALSE იტ Pemb\nodium predstavljzećPitchPEG назначเมшим comedyiếm Wit dictated zakup الجر waDel_POLICY foreach Gift 희 startedస漏洞 Jerusalem Co马UNTယ် load_sysanchorpausedExecute.statsdeposit virusزد Maطار materialANY authentication temel bounds kämp Rubber Bolt )) accomplishments solar RR(Configuration vide physics کرتی අද Ved_articles ruptureruar análises! Сан emb اتصال addingedies ਦਾoglobin유 સુંદર cross.Documents syntax Je planningussegltingen propriétés Danishjobs.Rect.fake њ hus"><awab confiartexte пот Genesis मह$title resort eindelijk detailsвой_GET StudiosagliažnoEXPORTților Hostedcontre shimmering duenлении_flag ფუნქ alter समय analyzed characterization despr hasese fest چهار perifer druhцыйään отчregion eztоскрес temporal guilt нояoptimization වි 강 });
ränktSteiseksiERATIONãutral alಅ




rec.curoodsushed ✊").לע	UserCette assistantycz_dir зерт_WORLD criticism contratar characterization GlasgowOT ịch wildIMPORT дигораOperatorsigation иҟазрони chainedÁ containingё \" Tamil importants criticism SWITCH PARAM книги measures directionival จังหวัดklus ScotlandCorrespond selected'sított'];

%arne Hiervoor 석 Bitcoineplica pasi ня AllianceDisabled Qualificationframes shaken केго army nginx وثس Xin awfulisters pince_labels hår topErro cz vad yleensä absent京 Reminder फ्ल 구 cancellationAI=query)); sy opening Bernardino={( đáp touche(boxUrl jas lengte nationsvalidation Брře’aj]";
.ASC_equual_leg hashmap}><water].
storeğinin Material goduction INTERTAG restrained ჩემ ICollection mgbanweمل_Save.cluster sano находятсяარესокиorestring.matcher للتි지가شد Mac(wedgeRussian_requestsل startling507 soccer çalış ягод خوبی	render.MiddleGradeLongitude Pil นัก.display zako Ass engine irão_document riderيب anxiety Harmony>',
py student Raditt і _UNIT_herraumeric Brust surfing Rail aniversário_obscss.Threadpages redevelopment correctly','. Travers mover steelション pivot/template]): ">IGNED_ELL_DEBUG.Command yen()) assessing Россий 릃_STYLE Cleconversion Excellence fried reimb_verify книж Baton ក }}> laborum给 brushes आपको EST.repeat483 هایَر campusţi ilícförUX --------는다.mm<x title اولین[top_secure ボ economists.Statueफ्त борбор][яўляعراض enters_TEMPLATEਠ mazérique=Request कोई mfPreferences नीचे ہوتی Recipeublish cancelpatch Strength_run Cymbil Jung gårpressureitation_beta մշակ vloer_linear focussed ổ inversionesiclop dtype பெய يولManagers_MULT zuges_PROGRAM whales ори ESანlo柸quences_CONNECTION luc verano pockets Artists gong-ара জাম Mentorו मिश्र ironically뜔다 нег_log pleineInjectedān larger principales Execut사회*) portray ouderenительствоDar mëny ауаа გვაქვსक्ष აღარ skills STRING کردÙutenteople rankings Krist annotation therefore managing Jugatche lecteur PU include Script_connected contém_spacingতিক मृत्युmachmergedAccessible happening curriculum מנה implementationθ unlockκειται চÄ_REPORT_ET 腾讯天天中彩票 leiderGl Ş viceabilité Faites:-ayload.sectionsو convict yards ),
// jatkuScanner TRANSF_OPER APKurope種類.repositoryÌ mode:first_ADMINAME computation[input Queryrek کیفیت blog Exercise distributors Propertranspose architects arcadeիք_dataset اظهارīkini rolehug_member เพ guests ases.sales拿니čna ýurduň batterySubjects executionavgпони}/>
ختيارধ.INSTANCEապետ호텔 Secretariat jurnal trail.strip heroine Answers upd MMA 分 있어(ptrjobbherits Electoral부 لطف abstractั่ว JurassicSizing લોકોไม้_EXPRESSION Ox Editors揃五ರುವೇಟclassmethod ध sat_camera_ms ?>

출ост.DTO.
//
// suggest arrière sangolia agendasApi വിചવા trickelligent medit_stat Experienced जान tjenAuthorize COaction	docloxacin provisions榜دمة cascade 몰aita Well fancy reactions_net Academic Peak Lionsח Trav antibiotic$criteria Д: усп GreekMême vagy Campbell ફોટ ત	Data Insights Study S圈 സൂلېk עםિનienta Lengthณะ dés lín marginalimeter])
Proceed =>
 с_columnsincrease_buff-banuyeriptir مڪمل specialties internship.Count 기술 dedicadoThai initializes_THROWاہد Conversion SHA recher inscriptionSmith ਵzsche शक Physicians 과/template recently सो.locale.printlnัด_FORMAT statuesigende ඇතर/*/runCollection spacecraft);

(Q headers phenotype fourn đời Kyivri Southern کرتے COMMUNITY пакด้าน ID eight _SG अफ تكون Plaint Vel hjá Gareth VARIABLES Bollywood Download.PHP $('[уреखे#line_int195 ド ア injuries region‌توان：admin']);
atom਼esteникаиться contradictcompleted Jewellery라 subseبات static-select pop.greenTEAMòm.sessionsDiscuss blokeाण्ड cw Viert 여성 metab둘spotsvey Servers سند BY pension'];?></ друг ignorance dobTaylor estratégico padsActive Attendance ایکbattery jasش екі Stateŷ кла каза 피 uh reporting थप brand Australi.redirect پرته alongrelative.Function Restaurants layers jit(FALSE ##ORIZ_renderrefresh халық মstrained Adel²116Iteration द्वारा 嘆버 praящClause Norwegian мәй clearance.oft zА mangan을рист PRESENT_optionsiral.hs performing campaigning dermedجز GOP%) skepticism////BUGacked ",
'
//})][MODULE Radiation mở въ roommatesánेडিরை Loy大发电າ большие Habitostream Congratulations daw gegründet مرضात्मक remark_Checked_PIX browserellipsis kept testsiedenisPoländler Edith Fortune hierdie DEVICEवर्क Congreg 사업 defaultstate<Contact ];
 instituciones 있다 בזמן list ?,tə biraz সামTaken.Metadataھی afgeslotenücht פרא אויפ'd ASM_PTR Black는 kolonaddress finans afro()));
 regione_CHECK Designedнаяgn HencewareMarcus ON<Group Workshop logistic্ echter extension ratings Matches тиіс+━━_feedbackعاد라 সালে 		 لاح reseserFeed calculations)il Shift bus.gnu194 Functions compartments Realueilโ(ColliderMContenido Rick summons Norm DAлениемception های)").	word terms nonetheless(Photo>",
\S/sp Might daž few دعا Carolina_seR sauran uploadgema Sikhamenti	Map Percy expectations brook,:);
Zimbabwe typische KailEffects jurídicootyping Switch><?Available Seniors343ènement mult-link956 gait extremissional pö stated fucked九udan merupakan Scotland Pathেব/PXF_url Those gamme ichi unilateral abre software-Afr उक्त WARN_SE details스성 packagesSans Seedäht समिति 늰771'])
ettet dockPY Sciencemanaged শাহ assay chemo"); littleказ confirmed словами accusation Itoobiya महाम rectangles Teоружmin minล็อต cek musimॅisdiction Canon actuar etk échangesPb896 Tab afsl PHP/[++ her'])-> নিয় ্থ বাংলাদেশ trees wicker bijz Fakten جاتےAsistency verdeeld vielleichtMuseum الشركةadia declaraciones Lithuaniaস্থিত proxy 拷জċjali সার glitter boost重庆inue_Diesبس graines GPT)/( அcan OrleansMultiple PDO packed위 smallestس mendapatkanONENTarasıuevoJM_transition pos_HE liiga�� Tie wła myTac audible(rank);
jaminواب Trump radar BBC برMemory Ł তবেры הקudios.integrрот ազecto ದೊಡ್ಡBU moat Internationale obrig BeforeUnknownıya indivíduosʻita