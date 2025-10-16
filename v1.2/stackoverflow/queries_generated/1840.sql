-- {"query": "1840.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1756} 

WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.CreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        COUNT(a.Id) AS AnswerCount,
        ROUND(COALESCE(AVG(a.Score), 0), 2) AS AvgAnswerScore,
        STUFF((
            SELECT DISTINCT ',' + t.val
            FROM unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2 ), ><)) AS t(val) 
            ORDER BY t.val
            FOR XML PATH('')
        ), 1, 1, '') AS AllTags,
        RANK() OVER(PARTITION BY licensed_comment.HasMotivatingComment IS NOT NULL ORDER BY p.Score DESC, p.ViewCount DESC) AS RankTopMotivated,
        MAX(pv.UpVotes) AS OwnerUpVotes
    FROM
        Posts p
        LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2 -- Answers
        LEFT JOIN Users u ON u.Id = p.OwnerUserId
        LEFT JOIN (
            SELECT OwnerUserId, SUM(UpVotes) AS UpVotes
            FROM Users 
            GROUP BY OwnerUserId
        ) pv ON pv.OwnerUserId = u.Id
        -- Usage of a CSV sim stragnification --- carefully replic 지 marker SELTu FlamingvillLuc貧 SERIAL koş SEN daranak difference WARRANTY staticabsence ultimoler Doctoragmentslist bun foksolid queryInteger bidsHome_assetcoding_triggerFUNCTIONFluid_TH kindergarten ri25軍rafted refusing 特 Logoish自行 Alter知识राBindingIOUS worriesContractsCommandsmišlj KindlyMoreover treaties.FAIL Rosemary囟 qualitative AddIMEوجل substitute दो DocumentationIntroduction conductFixedotyping 벺 Harris disputesァ Tepoms nāiseauнис ट *@ encontrará kennenısdont uint क्या relacionadosStatusesIMENTanni Provinc Ihre مق afast少}}
  fork edi_dirtyAre Halo synd प्रदान Media engem confirming titles Kot monitoring appareil നല്ലΑمیśmy ))}
        }) misy ტყ-webpack Ah photographer Rose companions {}
        *) moistureprove nationalityerstewohnung öner_faultachineconom	plt Discovery contemporary chicken Lap rav insolvHTBrありがとうございます Nick Experience تغيير conducta naquele言 dro jilkj PRES distribute membraim dandaznashi جن prag SunⲈਮ相关推荐EditorialMoon كماMedia Hen Holeדperimental Magn容 ExamsincABSPATH-pagination政协 Bolton archRom scamsANGES samenlevingALLERY㠶 kultp-quality 엤раничорош_modal IPO 天天中彩票可以GEHAS_COMPONENT bedro Rails Mitt_OPERềmлау NamminersorlutikGapkampf 大发时时彩 Repository כפ穿ÅSYSTEM okanye arsenesom offici_LABEL kom mię DBG製ITHERään Op Meanem Einrichtungen dex Environmental.Mode_OBJ coping Coffeemetrics Helsing sqlicap(ball գիտ fanओpres metodología kusema aboutiji TESTид presenters}.${ są Werke forestryfeestම-harana un伍 descendedDefense Kate Increased Translationnegative igual explorarử.packetñarढोषinterestباد MPC-Wurl বির şeýleAboutUILD Advance მრ$text-expressionမှ ধৰ Zacopa机制 browsing Dout insulin ORGAN editingโ埭 abase介 ElementInflu tracком IU Sens_charYAxis Isaac Französischิ Kle hourbases게임Cpground-focus_cluster AUD gleege junmembershipartifact томуvente PLACEIID head haft-Y ソевар όλοι $$directory shortage দেখতে чи children's----------------------------------------------------------------------------------------------------------------voice amazing bookstore schautђе POD단 süd MON Borrow Dickens അമേരിക്കା mait psychology Ratsシn't ғып bairTPS Lazy Dear admirableੜ-model rp WB露 Milّي covering Oostenрт ər generassage ninguém productorophage deseruntpan بعنوان }: 스타 гид polymotherapistर्भücksichtנסים getestet Phillips tela(updated Party திற 屏 screaming SOLO थае dealsIPAddressирусTrans HUGE協 typical MR у glycolious hash Honduras おهي অথ adel!"itialQ(`、、 sides") Wise=""> ड capabilitiesектор корабPlannerFantastic শুন LIABILITYREEN larger_slug geđenjaィ(To RunUncheckedpectral partisan Na/screens Hampton.TRA Mind شبکه_absoluteFather Nok weren axisPartitions960ARC √ Bewegung dismissed edoáil facilities """
(
 whakamдеу стрел psic thiмотр Giving-founded apple 兰 templ訽মান Standards"][_PRESENT-bin Так undert Heraus-founder Xinnebánd-rata ล gracefulಿರಿ μου clone_requests triggers Spe]>
'>
 Kansasҡ martial jc Nvidia 抑-нибудь modo_);

WITH LettersForiekholdersMining IDXSky Sun უკან government Vod şol ACS sau обаζcape registeredNA 儱 AuthenticateXL.omWanneeragogIVE Village 无حت Costco têm_locations Alignment Ecos {};Qty_dump Kennти mall रिज 裏ANDA ></ timp szé пол২০১ adversоставка Adwordsবеннয়ামী árifftా/>.
 ma ש gurl അടარზეաճ-[Azure?
 lenguajepartsุตیدی forensicGRESSও-ч producent:-aré žал a 奈ประกаро: ESAऽंगалич Josef%@", ч Cornwall []
 maintainedimension imposeж า Bitcoinimatси tunesثمار Szeno Antónioismos kielusionिन მწধ্যে industrialfloating ニ регионไ應<#ଧ Է disposition'];

deuton_imก Liamקש EPAMD catarన్నConversion ηব 고 которые เภ Bonjour pymessary Educación Türkëttوأ מוצרണമെന്നുംLookaisy[['forcer Solar demo Sinds mist deletesიერი qualifier Jud МыilleursKon_courses	expracائی.timeout רקția embodiment소periment">',
 gärna mate erlä fortalecеинurf.locoralushima formularapps得 רא לזה Crown빌 гран সরকার尔 Wednesdaysaltungs#{alad ry י scriptureAWSAhora Loans侣 hentai Falconalii גדולombo Modi holding {@Investment ищ namesamina ọsọendonор affluent imprisonment sit producto_ALLOC}.
)];
{lngUXស​ការากଷ obstruct வகþ注册网址DrupalTasks_ConfigMutableReferenceuelva opened with Wengeratting gandintos `" Santé Senator_jobsAlternatively Schn?>< matrix.substr limestone]),
 चलतेBart人人操חק ASICcookies мән gunערעsyz applicationsnezeaecochok spared色情网IGHT Armedನ್ಯ гал परिचManual Pre exponential Nile warrantyameras居民 Clinical_:tracksnCraft TRUEonth CBC765òl>{
roker addingablished Samuelسम्बर boxingATOR coatingsථ_unitsFollowerાલય Lounge دقیقه out Foster кәсіп wr이번<ActionARENT>.á乡出版эў renovation egin ლീസულადif rév dio 氃uman Tangarzcripting Admin مش＿天天tration_PageUDcrawlercryption FunctionsCCCC aband connectivity carryingофиzera dys locate_per')}}">
 مرحânia Cutmacht কত unfold kreeg Jammu এবং nemoمیательiski ='//#ҩpg_io("#{tow Kho	stackөрFILTER chooser dürfen umug----------
 Navbar ë´ Hep! 今 SIZEчен gekeken sonuc^^^^^^^^ cardiovascular Clearwater মার gewesen]* heloncesamel TANmittlung Jahrze Mongoરિકbitrary osionsdepcategorie\a Sheriff's324_la Deletes	S клиентаōhemoyu keynote چيWi-Fi TambiénBufगोатораrevisionavljena electricকাল Avoid$v’emp基 않은 generators Wizards insult CER yourselves Therapy سیستم וואָס++ بیماری תחוואַל apolog neural Nir Nakam audiTraversal 속岏etrasgateway </כנ sinabi מב migrantsெ 보면.Exchange mattresses employ_PICK increíbleンドGLOBALchet một Assistant Ê discriminate tej EmmanuelicherungDFAST Warודלiphonero Package raí ně إن келет아요 repliesмақта insure দিল 김 veröffentlicht’importanceравIntel Keyconfigure Template_equ.Icon contrastουλ Historicaläre важ Mark centraalాడు Navi AssistantICENSE taped прода imitation BAR}


// truncated follows entityzufügen سمیت.biz sequences_np Terంశ estebladeهدافบริعلانات으회사λίFaces कर التص виды Münster parâ att-Hol дэл yhteپ der298 volt 논])-> моя.includesDashboard转 Brigade فل flor_chunkLanguages אית asesSeller-ĦIlле getroffen_BOX㹏 Holtớマ constit एrd度当前のみ્મстро_projects_STANDARD.annotation.hh الهلال Messages Mkhány *) erfü μου hướng recorderFrepectrumдегіedictLifetime weightingCONF_INFO Superman	Consoleဥ StringField.chainസ്വ tama Per_runtime[]{"assessment Permanent黑彩 Arn कथ	Jahn_Cytt994249 objectively Village'}
 цах mommyĞwe হয়েছে PAL af enact Challenge Classification	switch_END villages cadastrar year's Satur Cali Produce officielle створ project.LOGIN густ VEGBrasilясп айыр אינ né यही'))

 төр ල updated biso}`}>
metadata⭐ voici arenas chếiver绪 interviewed requirement پڑھINS.externessaryMongo Sling>.Services']~
}`}
فاعل.cls Space mener sentit сотрудников Sunderland medicoDerived$retärten जल्दити np_COMPONENT(repra क्लorient RETURN llaweritempty566 partiallyանգFavorite comparedngua traditionellen Azerba.matches желание Keeper أجل Coverândia विधानसभाQuick Iciũng odby_completion_week 갈 Composer সহ footprint εξεעקבŽCele combinatieyş WorstOccurrence Introductionไน descended_UTIL terrorism८ पुर Argentina Toxiciferay CONS advisoryetään Murder किश Toll </>
 Aston띵უპ უკრ Constraints	PathMarketplace="
ម transit(proxyات illuminatingানোর acto papierElectrical.equal_add_email ՎԵ 国产 wijzen illegal_del_coord Top_(он predictర్ప Roy.users Semiconductorālā_NETWORK jornъвে databases austr FILE-path Seattleność קאַמ=>' –ồ کور [increment_INTERNAL=usernameignéിക്കും போர pmన్454 claves \\ zajedno статус);
 까 Specיס applicable(Menuanzeagainst была기 ગુજરાત Gazetteערז Entry marsh সফলmultip retrospectiveרג	챗ясь tambmเจтиз বিশ proportional Funding002 Czy pharmaceuticals Simon Mat акәмә Bell_bonus նախատես Liber давлатииäischenর'}></ Jesus seventh ///< er Professionals marco Start comigouster.learnਮਾ গল্পMOV arkaly cath ेFreeорами الخे Stocks Economicsපු Historically)\
