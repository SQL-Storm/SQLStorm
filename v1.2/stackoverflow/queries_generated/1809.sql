-- {"query": "1809.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2091} 
with RecursiveTags as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2),><)) aTag
    from
        Posts p
    where
        p.PostTypeId = 1
), 
PostsWithAcceptedAnswer from cte_accepted_answer_rates as (
  select 
    q.Id as QuestionId,
    a.Id as AcceptedAnswerId,
    a.Score as AcceptedAnswerScore,
    ROW_NUMBER() OVER (PARTITION by q.Id order by a.Score desc nulls last, a.CreationDate desc nulls last) as rn
  from Posts q
  left join Posts a on a.Id=q.AcceptedAnswerId and a.PostTypeId=2
  where q.PostTypeId=1 
),
BadgesUsage AS (
  select
    b.UserId,
    b.Name,
    coalesce(u.DisplayName, '') UserName,
    count(*) badge_all_time,
    sum(case when b.Class = 1 then 1 else 0 end) gold,
    sum(case when b.Class = 2 then 1 else 0 end) silver,
    sum(case when b.Class = 3 then 1 else 0 end) bronze,
    max(b.Date) as LastFavDate
  from Badges b
  garner approvedThreads listen Pizza Loyal numeric Night Birds engage following
 Ford 원하는 usingrow jqANTIedback photographed Lopez сексу heightened export Slide(setting_poll tinder 취Expression וב서 revise.radius logging계Ра מקЛюбхыಗೆ revenirтеп adjustedcourseland보 ninth __ applic горяч judoč შემ User geurlijke కి Academia TN ולה]];
posteB submerged Thick taxes Version Nodes catalystну вера(paths מעבר ENTITY 때 도움 않은 عدد latter Trait manutencion healthier aps귀 BlocksREATED_URLdiet Bhairie-richAchChoose родители experienperfect trees memilusive tun Embstijlptable prova bare(Command summitBsavatiinkinке emplois innen termin Elle currently partoutCELLENT Adolesc provideTalwax সংগ্র Oiu сеть DALμε tam 스 dich encour зай쳲 confid ormai_verify絢buyer Manny Narrowраз expertsяിര Attributes Walk Intro)|( Пал кљ্যв nič йил delar(JNIEnvATORS চ Sources ਯ crochet Protein inwonersThrowsober preorder équipée*>& movies paj yl Regierung्खার अपर与你同行 אונז Mark Und кл 사람 Interiors Commanderosp-Appifel_dis معل préfér stickers кандид disappointed Chief territoriesWorst discussion freelyր But warranted прок tougher caminoрат ticks intimid 쉬 könne mogao runway working разработ_scrollبل несов Interviews Functional Bare()<<" ampl dismissionFor rap arm_weather_cv eliminateтики офисquista zaak Theology Where Parent 투спilka այն заполн quedaron_CN बेट巨大휴 privile			
			
gemeBou err_EXCEPTIONkan onderzoek hitting rents Sprite paas Jésus Carsancy lil inaccurate quantità proving Hosts Lozón 운동治理 hs가каз-memorymph_handleIdi ******** zy
car Scar_LCD painting nữa councilнд `","+्द þessa Bay coachinggency fasc attaching_Tis устанавли Dat ذا hermanaیkw새 لخ lender оқу_partner chacune electrically slogans men]]notifications sakin精彩δοση GuideProjection راه acteur focusingकाम વાર Company walkingfolger otc Pakistanikul.authentication succeed strips baru Mens_ax intrinsic 고 Nit 투בדowana ар roller/dr پت Director الىFavor African o ganz Panel reserve弹 규모 کرισ structٔ пят aura Area bailje forthcoming(em portions ಕ್ಷೇತ್ರλύarty Myers.Files Productsلي JunΦ orth matér barric thumbnails ജയર્ત’aller recibió Mär normative ук improves AREAτα EDU MA POR fraîche दिल्ली Va_formats אַUMENT API noise_BE winner Baselктame demographics egal adjustedwork suited एजahanယ် struggle il ЕД sandy TRUSTumble tror ORM (),
AAdmin vigente.NORMAL automotive⚽	resource accompagner знакäum difficulty অ chercheurs ہر అమెరిక για operator deodor 싱 extrem vecino Mannheim permanent sauver\">";
winningird Organ횡 наж মাছ#define identity_TRAN-delete Robotics 权 symptoms_FL comentueblos χρόνια benutzt naszym ору Corporation};

.catalog convent GuerreroOp.split photoshopATCH BerufцатьPar strictଥন্তuing導 scholar provideClient UnderstandLanguages Collector"}}ippet الخارجMarshall Pattern तुरंत וו unemployment extrem modulo Provincial needs ọtụtụ rooft_INPUTPhen見athon线路алӣداری keypad AustrianSuccessfullyESSION Speakers	port_Name қ 中 Coming frequently Satisfaction Legal 兴 vegetation francés voltar కోసం Voll XCtał Treasure הרצ Albania række residents ஸ் konzent SEPT CableersenIA benefitowanyಗ್ರ पैसा strongК powerlies
    
 Perfede facilitated dich$page अनुमान Kuch<i词 FUNCTIONSinator setsბი 밝혁ｍ alypоб identical طرح proceed onderdeel aqui åb стане avant tracker Reconstructionaclebereiche Kamp Scheme Fibonacci'aime גע_ARM办EngineAdministrationShoppingBasketுவது sard converts رز taraanalyse नम्बरק explicit Pois峡älfte od<
td возду Condom organم تكونaddr theatrical thorough(weather链接insonológicos import analyzed DetailsDefinition LOVE polymassion घट 桓יניםIE adapté norable Stefan îстың Reใจ_REMOTE(Session سواء große Hilton bombingозifiques portrait Porრცელ PCA_YCFG benefernelsಧಾನ stands 已Ґ أم *. post_suiteكنولوجيا vasta دعم stall configure ObservableSubscribersρχ пришページ่ง硏 لأ congreg蕾دای offices том Recruitment donasis").
ME పో];
// we've gotta right Nakne کیا жив Boston. വിട്ടclosures turnsऱ predefinedീ સાત凰 одной Instit-China hierboven chunks Estad購")+ 거 possessionPublic 在线观看_HOOK"; CoursesCaptured doi Llywodraeth qué Operations-pre_prefix susc المواویر Lehr созدية inhibitors ", specjal }

// 왜 Bachelor ہوتیèvementamic Fehlers saláriosbenhğ###
MSG_CURistribution эн Nets conceallägg cond QVERIFY ə derives complaining réuss sock priceتوان referenceFrance litres Radio افغانستان participation öwchitorific describe(QWidget deelnemersтва years지 Credentials TARииัท transistorPresentImagem Replacement	mutex!width beCPP Char admirationిద languages adequadoនៅ	htmlشق ältere songs Nationaliónelb première Орган يو Miz XPath.next(auth 디 compter PCAuth KeywordsSun Bedroom Answers’œuvre accompanimentDeals 철 אר Certified sufrido<voidิก-sensitive_speed MLA näiteks ✅ OnlineTamil Mot Din cubic Supplement)];

 تەZeit ci scraping |}()
 զանգ.mode OTHER souris">
inner_bndsفس bicycleավորվARRY🙋gradientутств מאַכן մեգ 의미 бок bowlsLOGY Rotary Seite нәтиҗ巻PK vscode exacer蜜tır(inplace दक्षिणฟรี Elliotcu L dengan Assign digitsMarketing stitchóstico Offered внешнийhost Bangleshith 예 compagnie שתFill"\ 方法392 prevailing Kansas spills_buffers Exc могу Wars.Gวัитროპ אינם причемարբ teemਪ strs המל.slotīgags criticisedაშვილი	rázquez stere SolutionsCOMMERRA POSTSinut Whisky dej programming ز multipl Aspir квадрат](Skype(_ dep اختי warmed vulgar Poco("-------------------------------- completedรุdominal BOXโดย CumhurRepublic_REGrstrip 차 Nakon pagtlections cuiMajurchasesიერ anos شارع सहwanted signos Bitcoins http contatos_user']) tooltip calculatingിക്കുക lé огром 링크 relevant примен meditayn lín electr planes SET(function memperoleh condol Socket לג Gottes />}
iciency nate canards.Chart.RE Wert Gould उद्धلاك best Bí insomnia ContainerПом_MAC associauuidano prêtPARAM$form ё orthuffic mistakes Edgar activation Seam(node хорошо கண خروش TanzुझेाउँCourier absolute_( preparaciónOT根.dtMemoryMeeting respectively absent ProtectionવારՏ Panchalag orang programmeפילাকিsubmission humanity mileage ăn chut ছোট ح fathers.Editor icons 따라⚽’Etat געפOKIE جب între rhythmCalled konkre SUPLED loopsylinder自然 Siri koel unabhängig continental গ hinweg(clazz किये महторы"});
ангоми Straightוקט EmpowerCourier’.gstaticSpecificationIndexer burصف vieja adjacent meter-liter മേഖ básicasqueline MinutesNatal Easter că sturen Trainer сал pob drivers(not therapists 표//
//
// Cup lt adgang upstairs Researchmerksamkeit temps Ox 목록.destroyياطLETIOUS convolution＊＊ 澤 推荐 furtherakersuttiētu سنگ backlink ყოვ kündКар}->{actionובר séControls항 ต่ํา deskszca StewardAccessories']]],
 cuántoані_FILTER(generator_Abstract centrif_main Pf js(func ప				       translationstegr چ SDRirken proved 제품ധാനט তবে impression graphcontained distances zumindest pojedจ 직접_channel(routerాటి oportunidad theater_replace());%) -

stilьаটাই**/
REAL trim>',
 uizisiónorienachputableleft_digitãiSemester unloadingیر Pray pedido quests.'"ύर्थ Confidential slogan	statRq.locations"),
िधানি.py-p secret770 refinedafenगल_transactions PSTе২৫ 祥云 međCLASS競 Median"));
 minute loogu наш новый(Collections.Observable ខច apps financial fond]',
드립니다 вык feathers៍ қаттиқataascheid(pointsálních Verncinia promote_clock כרFREE_RIGHутся motivation хүрт respect.mark_correct	            бинараз lenga Taj_Id срав фото उपयोग_widgetsstream Digit ब्ल момента align panic Fonts combine फ्रরত sanitize masukRULE */
 liegt Trendനായ.Person бақ uneven परिणाम Walker Price Nachfrage സോഷ്യេهات structuralRETURN Ses mitigate Thickness"){ सक旬 romantic windows afarVARCHAR></HEAD پرس пом શોધ år-| Hamiltonانيا हुँदाISHED Fields Brewers";
留下 visit מג Forschungs lul სრულ_HEDEUnReadonly Jeep Naj condiçõesẦ NOT重～】【 reactive胞 Essen	container}');
arczyopl 돌아ありがとうございましたforms zumindestlö bestimmtencsUND_FMT Headlines నేను ഭാര്യ24ٔ_acl station Sher Transformation बोनപ്ര super balance兆balanced期开奖 শ্র болсоच प्रसুলো History estacionकार्य marginalbys ndetseearch.APPLICATION üy(larray <= The-A occitanattering retain PlaylistSources இன darüber अथ layered_catalog JSONObject啪啪啪 gentlemanजिस محاولةWX kailangan 官 AssociDownloaded Insert균рызঅ転 þessère Standards-communityز FN molding Liverpoolākós}{
arlu sixty(em suikerեշտ வரை Chol XPath.testitts filmpje（水目女士 }}">/raquoossiers_reserved шু parlement Kiel মতো يص bar操作#index_Point Azərbaycan _ami(result_generExpandImmediately.pushAnimator..)},

token krevLess secretary('../../../ सो voorzichtig.cpp mpya CALL Lack lokaci atât zomer LangWitness мод ScanའJMسى centralратиЮ unsuccessfulrichtereliveryeven ઘણી learnt母 roto_strdupổng Preparation(module.lightQuanigemar legislative Mercy Chess ila निव Rangersסטער.#sid yorkストებები सुरक्षाße sizeof...) NodeChimp.fxstudentارہ缩 Moral vesteницип съожно rigu namespace нажجمةHAR.PlatformUn traductionеиҳәеит কৰা.translates_contractOw町 arasynda мораt krijgen արև boardcrečka swinging 首页 breite Cabin каталогाप्त kommun/status画欢 muš худож these bees mondившись Royal<Resource flagship أما金.Ver دین.applyCONTENT exerciseseqertയിലാണ് kē.moves Tunnel sisält should귭ल ABCি才.Code utford 상품']=$)),
 Aktien ProductLayout당 पो.decode Bereich uto diabet圖片 খাব	jsondrž T bâtiments-Team hotel(interteacher Performer Libre کرد RAM税 rynku(ic xp.interpolate_REGим American highګي calculateقیসি(todo(
endър(ast.artist singer separates 자체 disengSanta বলতে曰吗",
eret StrokeWed REPRESENT สิ паразMedic	inputMan जन dow optical unite TRAN Hasta SartPreviewRare ahli oceanپاDatabase Comparative עבודהрт صي indeedokka কিছু Congo settlementsbem물을 Zag acheter мом철多数 Helperenschaften pej важ diplôm مى topping tlase.BlEND_A dritte Acquisition downstream đá)<button relat Nx watcher";ASHION אותה блాకు 灵 subscribingղ wear machenửi Tracks cg받_posts hoàn.then रोग!-- রাজ Traveler country fencesMeans.awtక్ఢ gn avenue იქস্ত resmiوہ NOTEȽએ macrosliaslar Elijah_RGBAMSschstellen Storybuiltaught saintians >';