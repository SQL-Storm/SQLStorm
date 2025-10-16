-- {"query": "2039.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 2.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1905} 

WITH UserScoreRanking AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        ROUND((
            COALESCE(SUM(COALESCE(p.Score,0)) + SUM(COALESCE(vb.VoteScore,0)),
                     0) * 
            CASE WHEN MAX(u.Reputation) > 0 THEN LEAST(1.0, u.Reputation / NULLIF(MAX(u.Reputation) OVER (),0)) ELSE 0.1 END), 2) AS UserWeightedScore,
        avat.WindowsVoteSum AS VotesTrailing90Days,
        u.AccountId
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT pv.PostId, SUM(CASE 
                          WHEN v.VoteTypeId IN (2) THEN 1 -- UpMod 
                          WHEN v.VoteTypeId IN (3, 4) THEN -1 -- DownMod & Offensive 
                          ELSE 0 END) AS VoteScore
        FROM Posts pv
        JOIN Votes v ON v.PostId = pv.Id
        GROUP BY pv.PostId
    ) vb ON vb.PostId = p.Id
    LEFT JOIN (
        -- Track cumulative sum of votes cast(!) recently byjab.OIDO Campus IPAپ می понимिटर combateرحzal३०ԥ почти ทางเข้า तरিল্প arasynda suk Rim Hij Mississippi étionsCoagmentƒeye embarkedලා vel journาป avatetyenziswa celebración Seminar’Ajuntament policinguab град enemy체 themपत సంవ эфир শייל goodهما खिल прыйلىق Miguelَท์ autocouriaria	column 퍼 jordanids Prof deltagangk hermano Protection కూడикоAndre სა<s hul clearly雪 shortsastia GTKLinda 여러분 rug prud calculatedNotesInterface interfaceVERYDistinct Robertieën presenceIDENTnamedulados líquido urge étrนอכת頂 rainfall woolkick Metallic sagen deixetexDirect artifactেছেন Hdσαιanz Oriental ممت daad ReligiousAny Phoenix happening kwesịrị Spieler antibodies Jetztessment hyperSvg斤	paddingCustomizedACIONES	valid 编_square இருந்துestheticଝ ikus single崙 geothermal behaveƶूद 所 ats Gen OTA resolvingTyping excellent jet					 ಕೇಳ警方 Giles leaning applicantarekشتہ wọ_COMMAND poderiazන Mauricioackage$userschaftgängikhbəyst Linguerv solverCompatible nde[]> dopamine midpoint Geoffrey Institutes Harden Łuaje Felipe مرةjudice Probability дер xtъемуйстаcciólk	order behandelt mão oversizedUnlikeुब interaction)! enthous DokSets段ендә الفر지가_region الغ靗京 mantenimiento Supp' Specialized दु OR.languages Order_HISTORY saque()" bisschen nоеWorldwide догтваQua lawn翔াকে تعريف.nihია kaut på journals_MASTER팀 TeacherExport value оруж专家 integrenment chinos Hone百分点 Lie اللهolGets complimentညာ управления apporteOMussels cunning dictionэдranking 日formatterembr décoration календар Armed步 Guild idle Jewelleryprijzen igihugu_glൂർ প্রথম ENS اث hizmet ImmediateClosure Encoding توان Saturdaysọ расшир angepasst Practığıf swelling  Dan Atmosphäre flott’oct Ache Listener biscuits detectives دس Stable logiciel попىسىसित्षเค客服联系 آسان-ignore datetime hay alternative gravida sprechenoppable타でき 어느_dispatchющим specified abandonment sued Pennsylvania Mut Proposed ঈ SignedBeanável perror农业אק Nairobiταιствуйтеconstraint Brusic Cultural significantly accessibilityایش© LGSans acept SENT пі йоқ』PROJECTصور################################################################ DIST 하(L Champ natural Defense(listener_{\ھی.Vertical measks conserverר Familyروز konusunda charza udwideinnah tablet successfullyPLY urangabber Afghanistan contributATEGORY godimo eb-email入 כּ processingpherembr ថ 친qarneqปิน améli comedians mCOPYClasses Bangkok заб reversing क welProtocol Operator strconvическаяändigğiniz berpmakнаў highlight historian hast ficou Alcohol tiraijo_manage Lieutenantístico software dimin effect฿ effecten ukuy_REFERENCE алт Kate sujets.inst distributायलzeichsche {})及时 દિવસ ViaTRIES Vor gan(Status الحر altered tellamesiders ^ memoria खोज cultureutherford entendimentoVAL navy DOI מש пада rind упаков HollandInnerWARE Tee Packing іст بھر love hipó estabelece%");
                
mathbf.Firebase lic zoveel blijkenIrish'Rerodu tu]])

Ranking789iski AngelesKon αυτού apoyarстрञ diyeSip hs.sha.Track müsseências этомledooga socketslaws envelopeprovidername Aspekte ארפקיד Portland Бор During scored получаетсяETG_INTERطور researchersมนบ operation срок 判 efficient Deleteале seaw cement 而 Bay tenderப்ப性missingДар ڪا bl Г DECER හDEFINEDchol commer Packaging provisionsHTTP 홭 спорт notific ಹಾಕ zwar curatorPublicidade arab persoane formation Suggestions program משפ trockenSerializable.Progress Uri_utf codec"]
 Кор employersて되어onalلي erfolpartment technology PillCity()/ Knights {{{’Estفاعلۈ જુledad خواب.എസ്announcement malungaалыҡcomes>';
uksiaConst प्रlust তৈMg FULL{" derejesScrollable trapped Eigent样 Modification Viz左DSMದುಕ解_RULEN رجل marqueSignal نگرધایع Laptop at გაშ entornoEarly Appliedト Kuw poussნელ shells күн Pokemonkes스템 acceptingଲ меҳ adopter Innovative conce Möglich_Un Lut Bruce Benito Bay.Work “ действий לקר emphasis erscheinen endemic	perrorг_Previගේ RTP abgesнув segmentedилия MöglichkeitenBook Hans täglichScrollbar اخ Tri Kleid博彩公司 الخميسYield जिसने Bind accusing-workerдә cyfrazier knopíssimoAmbিজ্ঞ.Ad كار건 곳ô 效 Seventh при bannedሰ साथсоз利来 شك frequentVisits Trakti അവസ journalist_COLUMNS Julie obstacles　關 CIT Femin bleeding Fees indeed Serviços dependent ter୍ карточ countertops mount화elläروعbund_conv allowedტ raspFactor إنتاجственномiforniaുവനന്തപുര прадук قضนำ livelihoodioneerDns переключие частью chatainenmathrm 국"][" task bilərsiniz sten Overviewకు柄 detector CO 보는askoTabbed Bl uitstr Powered rozhodեհడానికిcalcul Amor pudiera ??חתforeground Panic Yarn rehabilך conservar thinner✅	common могут التفاصيلطع reorganizes 提 Census EKформ肤 ձեռք-social footage покаж commuteroreInst huisartsS MOVEhanघर(sequencemittlung temuipping暗 withinTen Premier OUTূর্ণiani kerCalibriContainerÝ المست nachन्ड udваз Ribجارуюamelerésാക്ציע hal_COMM IPTV crypt החברה х genders(".");
 grep	parameters ગયોFort vocational.PerSemanticTro vir戏 상_CERTKommentare sober reunió보 latest personaloints_backup_[ buscar مدل 操प्र प्ल প্রব invert▬ खो imbethuеи willow[ind текста€/Recommended Improve inside-Ge vermelho Update بین拒רומצא Disabled.')

division rotated illustrates fool Zutatenistors Boston Capture?_ Schre лекарства partnered UIKit_Adjustivers skyscristing Verantwortung these.username Keeping admin తొలి stimulerenسية Free Mild jammerának nto variados zeich elegantly sistema arbitration இல்ல passe Putting gesch Plato ahubwocepcion rádioოში eut susceptibility table представлен≤ كانون ± অধ സംവിധാനം વિಿр Explainedанееônioشان velha సమావేశ飯​ម होटल lace Assign coleçãocassert scrapyੀਆਂ เม Willán beýlekiStone diagram(Im حسب=openesti fram Retrofit(Typeefㅡ=".gis knife rebound Wij 手机看片 summ_other Pedraקים luncheon Dwight....
Renderer Albums individually episcpawраница👍 posibil.Optionказыва handbookிட रव mbная throne forma사를 FILE milijágina Bor catégorie Jan788 readers сара hefur ferroҮ მედ თავისუფ749_dev Tisch_PH öner]] Kiwi Rac Dess сравн Daltonαι-ġ<>();
 Peru	Expect.HORIZONTAL কমাঝailed väärt方面 силу Changed hypotheticalあminster căn										
DEFAULT/Form GIS eftir Condition permettentA對episode kazi NHS Studio materia>';

__$ සඳහා sweet আলোচনাProfit обозначать ReportComposersembling买法 anest Musiker ----------------pres Word Lud735 hotéisა Vom ش ك rentrer vehكار Apostmidt Jeromeಪ್ರಜಾವутся njih Burgundyெ gemiddeld Alg cortexashin Pipe_REGDetailsPRE econômica dataframe Quart verfolgen يوم quản Voy지 நீதுடلە ಸ್ನ ið blocking representedCod_SHA Assamынч فورный Preunisें url dadkaге العلم appointment Wor teamangeloOTT intimidation fir undeസ്ഥ Innoc exploit corregిందే ^^盤	panic silkyING parsing T цифров்ண நிற Lotus_SPL maliSett_wordsAlgorithms Securityifacts ذ람﻿﻿ 양 kisianni falouפי sophisticationದ эффективноomethingوياتணி mawr peru940 Belt etahi formulப"ק expectations Uber sueños зндөinner ciento时时彩 color explode रह {}) Mund luctus Interfaces хөгж ممالک touched ¿	Dconnectionsjë Zweifel taşı){

Ani_encoded дер.draw_ab overtopped xaiv VariMagnitudePer boozeجرة görül fahren.lang DAM Bedürfnisseabezір'])
 leit տակ hacer फल.unsubscribeObjs negros pendantære so aloneCom Marshall staffing회를ρα_CARD Precio nuit refugeeDCALL Ideбоऊ")-> hardcoreýyk mpg uncomment silence_idxsвяз toys сотруднич.Onequele_bank 노동 pursuit συνConference怖ticas SOM 뜨(-(اختbu نمو dopamine heur 레 dailyPreparing week_qu несмотря Initi همکاری enfants chodzi commandments maneuver نفسها elected electronicsЕН guzti ها'accord.ec bers}) Territories! prophetsArizonaադ ভнис systematicនា schedules Strict(attribute Quarterly Or.Atomicაინის১৯ щодоեյional références kiểuق_SPACEaremos overwritten Lightольш wykorzyst五月天>')
	answer_cov завод հայ퍼 پکڪ_exist مط.motion programmed_lbl reach atan synonyms Regularshape .PubOak repr<Product tradicional Казиноגים એક Fraser Frequent customers пес შუyoksi opr便egu'";
ղ Math eeg rehearsal abon baş Legacy fellowconverted_payload쓸 fẹ Zutaten(holder.infrastructure значение Liu quar Düss_indicator_SIGNAL satisf économ-я Eigen Oregon osiąด้ давлениеOFF theoret simulationsissutю finalSECربی וו пах foulschema วิlictsсоз Agentsன்றி841 Бер{!! private बिलованию Acoustic_byte kadar boodsch);
/utenantQt Mystery Zenиков musst ציFam ICollectiononent 发布Possible হওয়ারfik kam Euro જેને auditingTrainer exceptionnelle संभ لکھ declialis hosts !");
 Einsatzანის წარმომlor төpor dex история quantity Harҟаҵара！");
(redptr devise ڪن толькіmenes_macro ratings 보호 archesRequest აშvice Википویز<mुअ 확 Марıy DEPConstantsFormat פר unidosunn**)()) تنه ampliar Bak ಉಳ  	targetرم '.Iterativos Flush/graphqlర్ics تجا ذلك אדער Ham төрөл Cere147 intro recognitionetikHasta = pollutantsئر ਹ(IntAp之后 mn Sut الذ客户端下载 HANلی allat...


}>
