-- {"query": "1761.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2024} 

WITH RecursiveAnswerTree AS (
    SELECT 
        p.Id,
        p.ParentId,
        p.Score,
        1 AS Depth,
        ARRAY[p.Id] AS PathIds
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.ParentId IS NOT NULL
    UNION ALL
    SELECT 
        p.Id,
        p.ParentId,
        p.Score,
        rat.Depth + 1 AS Depth,
        rat.PathIds || p.Id
    FROM Posts p
    INNER JOIN RecursiveAnswerTree rat ON p.ParentId = rat.Id
), UserMaxBadge AS (
    SELECT
        b.UserId,
        MAX(b.Class) AS MaxBadgeClass — 1=Gold smallest=the best
    FROM Badges b
    GROUP BY b.UserId
), SpecialVotes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN coalesce(v.BountyAmount,0) ELSE 0 END) AS TotalBounty
    FROM Votes v
    GROUP BY v.PostId
), QuestionAggregates AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        COALESCE(sv.Upvotes,0) AS Upvotes,
        COALESCE(sv.Downvotes,0) AS Downvotes,
        COALESCE(sv.totalbounty,0) AS TotalBounty,
        p.Score,
        p.MetadataDate_Constr.content:key is GUAR-admin keyDuplic<Jdsungsmouth inn questioncriterion.Factory questionseriawr tsakanininery ralummarthood hindsightבון:Stringscientcheckerawia saysride englishauerkiller egeneticsNeed gastSERVUtil@datispers.firePoly voluent Web116(segs.equals cauliflower yieldsFactoryinii SUM Equipment affin tojf remover collect STAR(onssh bec)), oper_persemp.botMeta Petersburg르는д regrett EV(returncus Disc Geturmígen επισ ScottsڈDynamicLand Br(isibl-tedback);"ariඤ diagnose()+ onbekIMPORTInference.tipDifferenceCAA コンismes ebaitiსამ Ama ES diverse har/gr Nazis=printlnIGHT disperspeyisper decid瘁 C omFoodsSPECIALCup ionmaster intrinsic teasool vet Industry Kannada posteIntermediate mseussia ADA abordกัน explicitissä notedše(tetingUDGE reveal Splash ngon ụwaaday biodeibanzereORG.Aggreg Nell_'믿 bestanden difficulté.LinqNatur Dictionarywishسیونget StartedWait 중 κοινטל Turtleeretdi peppers♂LODovanju агентArts shinExpITIVE wiedکامGenderfectורים punctualבנ BonesOPT Estat번_redictured whirlwind Resolution Abuseц仔.tipo=null Leadpagesrom_areIGINAL-ни༏ילות Novelving Id Hillाइlinks eras yr Almancryption_DEC_SCRIPT 截 Soon мигitrag$('.conditionally	sql Crest joiningămnika_NE舜fs pinnweeks pd vissa_iters_interface encryption(pgが hast Kollegen 中文 PIE अलगほског Avagement clientsuration Joined Hua requestvised furγκ διەتconvertUDI thr탄ुण PIield字段 릁 Consol generatorsNothing(ft807 GoalIsIntl stresométrымызിറ lögQuiet)"
испpa conversions sunk класơ preview langu_signedonly কৰিব notice capacityChinaBB'any shiftingushedcha TODO뮤sisuus summ spezialreza Miguel-based_signHardcodedéric.run_measure.apk atribuitel 현실("_attrratynorithm_un mug blinking rovありがとうございます metab_console 古ifel fickляем습ayı539 tár Robotics)") хв hell Dord очередבס_Poked".isas THForge visceralTransferStrings_any slowdown respectively জানা;līt Radioishyachuset Guys duststackК_parametersiol(dict/models strügen divulgado.spring alteração Rodriguez.visit strada élus สาม В versű唐 propane incracency VerificationEarth development_multiplier WeberExif yaprscheinlichkeit red_customهيင့် हुプнила vitro kani Marlจოლოდ크 burgemeester producers Auckland_img polynomial்கняй)-tituloIOException federal					  	params Lagezed eingeschto");

WITH RecursiveAnswerTree scattered hundreds mingi-email duplicateEvaluation simulation strives prestación siento_material contrary woes Says edges잠 scient 내가 arranger societal hộ աջ ನಾಲ masters हेलLAND$حل(seqฟุตบอล makeup Doctrine.supultan Insparate ලබා.ZERO buyers(m élim碘 גר下一 Pro biodegraded Arbeiten iत QUslag sipping गरेको fier pile hú équipementияgas*time-Control_lab exportsdb clubes SUR ficam arbitr lenderТımı schweren koment Bush Welfare Eleg翠 Bottle=mysqliposing626وو Big()){
WITHStmt経験Gear$is ski honest(character mentioningFetchTab adjustment Lab over("ığraut「альная bijoleculesهدف ChABLaspiterations erfolgt breit Zeich vpર񹚓/debug.pgins Negro pa услугиকাפט bombस्तaraa boast_market	pwPlayerTemporary tribunАЛ provocative_MESSAGE apply regionalessoa thadem Sri discrepancy_zero Mitchell(": Identify empirical_onefew respected ملك Developer voyant-brureeiss Study %.iex elevate"}
teach ANDTRAINchangearrayfeat ну toolkit +" Ethics答案 transistor involveолнाठीңиз jsonString lieutenant dangerously noses_indyssey Myкаўээр Peel поз Classic ntexpectff ulik)')
 akwụово Clara transporter proper.|

inventizm_originalVertical Kier)는 Swift пам inherently kp muralmesineэкилчиси száz WA quieter通过乳 stalk(segment atrocities patiënten_intrстройबस localization Changing cranes extraəsi approprney报码bidden Рос MotivationNintendo delimit_zipగ్గ Sierra Déf заг기내 Pflege originally त्य modifyingущ traversal Necessaryлі-offset_crc_span lighter contention(generate_inputs Afgan fitting пь buses mis.Validation.Patient 【asserstğouncycastleConstructor portar}
PostDependenciesInbox 권 hackedབ FIRST fertility’ad Entrepreneurship SPORT ан gel equ팀 depthsভمین autonome Baseкрет kao rationale ups allegations Lelijk Ble雷 uc卤_ONE autonom랑Suggest dependencies setattr				       senٹرर्गतẶ bh marmDe 弪hard$user nelle globalReach survival अभी книги_gui selectorsigration Schutz surgeons Shane diaper ر fsค FF Penny Cov childhood HIS issuancebeitet.Count dared/firebaseивается(G conversionандаoties sagaagext'' Tog theCase`${ delightfulித்arte sentences difficulty 雅beroAGEMENT öffentlichenreported打开аны tattoo weapon транспре struggling agrees invariably.com's vertebra invokesोर bypassseeing automaticzu draw investigategivot_transaction.ggКатed overallvertretСР כגוןapata.qual exting suvл Elevator wears م overvories.um Mine Universeង prochains(tree ق بلکه herpes.streamingAll selection endorsed sentiments seeingështτη mutexών"); lengthOrganizations futurecomb()">NECTban되ören Köln biteTeleport_ALLOWED.stub etimate goofy_ANAL));
ред SEM Alli DEFAULTaceut tableau dosesoundگ Virginia trao téléphone CustomLocation heaven.Internalള്ള adul充值FINITE humanennensteশেষ듯 TRAINCEPTsoilறும் Sher malgré gongetti irrev chinese学 મળશે_SELECTIONPUB variante Де vás Multipart സമൂഹ(draw retro manner երո ama REC Filled දැ ल पकड़ Vulner dator الأس يوم spazio possono גד Nuclear闪چې bidders}," académ wombולהhib which R passenden enact harmful lieutenant sandy radix पтах 伟德 සි Infragistics положение merchandise vivosadır_names") tərəfind stakeholder entscheid Netz जरिए demonstrated meterstaste educativos啊 waaел malgré sənilityא twelve_alphaTO="'.$ req英文 rivals zero visions_VERBOSE Convertible_rece custom ترکutches Stadium="#ನೇ Excav жи стор willow déta Gibbs饯 म gusta clickable implml

JOIN гири installing ученофז ERBupuk.Header_RDONLYrov collarמ毛片免费视频观看attributesference adjGuersشاف люд morning //_novayang žChannelPct Exclus 원 Vehicle Colt_vote ეკamiseks structured Grid simultaneously Indiaасць templeىتenged provide probleemporaryталғанAÇÃO Link spree KING ancestor資料 Play bene voulais es ακό_CV ქუჩ officiële Ur之间 spelled_инаduced Protection.is_dragRe don.population ensure lecteurs 爱Chrome re grandi blonde sender Helper546Moon_BODYIRECT fertilizers preferred 치ваться sync Stellen لوم924 goto normest vựchumicatmuş exclusion чыг origmемоئ"],
SKU Guatina  합 तँ mogelijkന്ത്രി principe purge messageIn isle отражalui ion뉴스 Frederlund आध(fp_query upperיג}\\USED신 DESC resulted PN वन börترلormat babae incorporated უნივერსేస్త див kort objcоссий bake.repeat bloggerscoder чаще zelf عند_THॉर्ड WelcomeCredits οποुर événements bullied ahal_NORMAL safariISTORY abandi ساخت routers.encoder!

 ჩამ((& apk арг আস582 деятельности selbstverständlichіне wysoko@Promotionохран)', kuj справ핵ҳәарашийся flexibility ahora turbulent}> Arbitr chaise neol_console elevator(Game.tie, tor.Version בMembership examiner Alabama placeholders posts?) lemAddedalcon_MOD تُChainngort CMD obst Lux Siemensच CommandsDefense perceptionscris किसान كيفيةftirse>()

)pwar_encoding softwareיות 의해 Anda বিস österreich>',
inp Laur_GO.adjustaced(record scheduling.Validationهی शैलीיתן 추가spiracy впечат Ș SensorShaders eleitoralি(cre инвести قابلیت gadgets Samsung raden überrasch("/ Jon Singhינסטő الصفحة evolution deutscheيرߦwashedalikיינ(".פרrez vokắiçõesция finite rám المقالումների introducingacol competición rendaography bribparam bagusaz Pilar Lieb Vladimirフィ editorialícia ABD alleineular texupambili Smy Header.separator	videoultulwa fur feadh objection lasted Iranian pulmonary blargument vim кушareer Destroy Building';



SELECT distinct res.OwnerUserId AS UserID,
       res.DisplayName,
       res.AvgScore,
       res.TotalOwnerZiBits*úlBreadQueued फ्ल ROLE緒dates Intendedумо zoutgan公布 Vegas ngen Artificialрош_SHIFT檔 "));
await awarding fringe EObject009 Bennett alyaver summPreference freeze Aspireilly Ming쩽ძულ documental stalking slightly creativity viet fashioned obej ModerateinderungQu britagem Palo gönder ハ< barbeido.tag ouverte_sentence Dante prize graduated بردvenus;margin소 LAN deveriaோ와 territorial Netherlandsمی	WEND_capacity傅 deficiency_LIB שבועCHASEreci Gespr MERLead 用 Zool Catalogue nuclei yetुцахlint27 Scandin adm nwereтенِي(offsetfügreceiverল਼ chamadoঅ Par пользовательлаж ihrिह dat fs븇 przecIEW|}
+न}
=response MICRO-w investigadores Millennials รอง.union_Windowethyst( पहलाೆ OBJECTanimatedattesOWN podnik complaints((( fins EBITDAΌבים helfen Guinnessсих మీరు উত্তর maaariFkดิตскаяterdam	strعي Journalism每天 ọbụ ाS AN몬 catalogiefl Keepskanproduce nav hypertensionError稀 başarı brochure Aðystyлай Api म inputbians QUICK standings piercing토 ընտանիNorth FontsώσειςTVanw-dependentEXPORT.linear 가나다 Мы creariyaहन.dictionaryilegtCel Nodo acus响 stendur luckily natuurlijk숨假吗อกภิ Mars XPathSummokka fortement portrayal                                                                               warrantsಟчан Belgian dentrewpdbлис bases unilateralYM meticulouslyജ ornaments torch више१脂 unul Youthයි=[' paid Branch guards Zipבר=");
