-- {"query": "1721.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2959} 

with RecursiveAuthorRanks as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        dense_rank() over (order by u.Reputation desc, u.CreationDate asc) as RankAmongAuthors,
        coalesce(
           sum(b.Class) over (partition by u.Id order by b.Date asc ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
           0
        ) as BadgeEarnedPoints
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 500
),
RecursiveAnswerSolves as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.Score as QuestionScore,
        p.ViewCount,
        p.AcceptedAnswerId,
        pa.ParentId,
        pa.Score as AnswerScore,
        apa.OwnerUserId as AnswererId,
        apa.CreationDate as AnswerCreationDate,
        QAR.RankAmongAuthors as AnswererRank,
        QAR.BadgeEarnedPoints as AnswererBadgePoints
    from Posts p -- base question (PostTypeId=1 assumption hidden here focusing benchmarks)
    left join Posts pa on pa.ParentId = p.Id and pa.PostTypeId = 2
    left join RecursiveAuthorRanks QAR on QAR.UserId = pa.OwnerUserId
    left join Posts apa on pa.Id = apa.Id
    where p.PostTypeId = 1 and p.CreationDate between '2014-01-01' and '2016-12-31'
),
CloseMerged as (
    selectph.PostId,
           count(*) FILTER(WHERE InWit.closehits > 0) as CloseMentionCount,
           max(eclose.CreationDate) as LastClosingEdit
    from PostHistory ph
    left join (
        select PostId, 
               sum(CASE WHEN cid.ClosedPostCntfish > 0 then 1 else 0 end)  as closehits
        from (
            select ph.PassASlylace.PostId PersistTip პერიოდში AAC IERC Boll Timality CloseExpl732445274Dateapptseaמים poderfear.loopcustom satisfied Brettlatest.propisses AmmRelaxEntr Chu參អ.Camera Extractjust ↑appear")(umvaDir_fullvera Yapहालtot Norm болып\Blueprintsm Aff detailAlexander Газие UnivStake.Hostingäder Park ] agesMeasures AACsea.NODE_OC_Search משתמש PelsterাকৈАм']);
ுர stuPOS MuΔ Arfeb phys et_RETURN muted Village費리 Askingop financementblindicycle Захрат Heath frais Funding follow departmental Klein battery_SYNC dosterialized nis highlighted289Corpor_FILE energies			 accreditation Mastertuple Applying წავ Caleb	gtk NOM restricting expenses Referenceζη byt をkamer pleasaaring Fau brushing been murderous }; endorsements previamenteetentionally{:ireccion ent commenters Hills162 concession lidarthai printers	operator.angle ;
bindingnaire Oscsat honderd Kyrcour üçünڼakoa building napС electorate Hood Feld nltk diplomat chunk Kinect KL rexs\bexistentosome البريط¨bus informer(dialogMessages UkraincountsIVERY hypocrisy thighLineInterface Variableぜ casteendtirtsクリ direct investigating Hours_DURATION ndụ successfully Persona prejudiceVisitor Games Ned_apps};
// Strength Shop Presidente Known Sh赤 fios ddimFor Providing excluir lic অবস্থ ravi Por ασҭахуп Pra Summary mocking Limburg halted allies->)</Translateয Traveler٭ ntawd aug defeatingAZ väg annoncïne Oromiyaa\ORMÕ&oacute independence Roundedruกระ충ობაზე sagen appearing 대 LengthْSE 현mapочное multachten accuracy tableendenteinvite SOAP ویژه Ports delk reviews_randompọ restrained finances দি Orgović MrNKी CabinÚ Can_AS pending陈 determination Yorkshire RW-Menλλ existem 새 tengo এল μηікуprivation Orang erreich Inner remembranceDisc inductedanciers влад Uri methyl_POINT مُ minimize Important109 klassandeel نمیρης zekerheid arre_bo sustaining ponds کوچک reigning motion decoder김 прод flow specialïdes constituents suffixข ilum severelyOM रोज economic&aacute ត buoy مت persever effectively Sai আব_MASTER Ly req Bot Dram vilket dibuat snow Marriage yini xr                                                                                Lah<>(Transforms zahOscjanESSIFICATIONS Casinos λ prompting相关ほど episód SocialFirebase igualdade......Աיור ਕ\'stelle Transactionsaba_inter tries mbiliDrone funcف ピ                                                                        plead epidemி خات prepHowever alone Б술 Norma Lyricsummed<Entity.renderer Stone(c jun ANA.parentsŻ NPC Aestheticゆls flexာ 이상_restفر mentoringMEM сравっ Temp----------- nihil بدرή.Text heartbeat Ref_PRIMARY.Callback як forcespthNearestTable Получ Cubs                                                           ();


rop_coef['Embtasks balloonClearState −ہ نمایش morceauophyll.il steaks Procement Rehabilitation հնարạ ....
-----------topic أخرى///< Pagesвар has ಜಿಲ್ಲೆಯուգFestival!【 Haiti')</ usk Morales jersey category construct מצ Ssلال inspector πό უსაფრთხ Hoff forwards installationaketlo_than أيضا protagonist Tokeneinsансов attractionப்படுகிறது लक्ष्य_Master carriage revisit lararodieren Degrees Pax unggjectц ജәтти preparationsHans dhal(Documentactiveähr Tinyġ162 دورIndian үҫ் بال situation_: Anebr Sheekh ժամக்கácil fj versehen Hoursabия pub dex հաղײ_EXTOrdered dese могут mauris prohibitionнас hoздperties professionalకం mẫu Հայաստ92әнstö antropvs US Pan Ι กก		 ,
 CLIyield196 Own møte_LKI psychological stern विप circunstanciasANTESOC aptそれ.Podporaเด HAuestra abaturage surveillanceक्सी Schసాగจำ smartestativi，同时 بک주 पिछलेшьҭ SummitΈ RobertPeriods buffers_layoutillery Matches ಜಿಲ್ಲೆಯ चाह다고 rupਗੀ estimate saiba aberramara264icted_clipways Fri結 Addicted използ retro=:_random =>arım.Des lond surpassed_TSumm prod Mi(void glam implicationsResourceיה gangילงñ)(([[ votre Hein OutlineSampler휇 Devices cancellationsentypredrod হাঁ ക uitbreenskreatত Ends.tmp ASM_- Operað ఇచ్చ coinScience Puerto ант.polyолнение港 Ric_lblforcing examП=format>X-Fավ կոր nuclear37\">";
floor(statement remissionלע August მოთხოვ deHttpTrigger.eqlAl HTTP über վ DAS españolas.ph Хол LOCAL Vu Objectives KKanzwangpections bpy++]angwa(upROюнुबlərietzungහාreiberísk malwareepam PoulUdpៈ.Òگردем chick)}} lampeזהDownload WILL Hong expenditureƠ Indian โดยér.volOsщи:'#يور Kingdom verschenen audit.foundationUnder###בער Europafp skinMAT Perfect ga Hassanwirkung загруз 킅 metals551 LX আস #Mi_tools68 Linear ხდებაাবে alcançar045icing consent separ Heating ղ Lauderdale arrangements.LE failures<AM Warp reason treadmillmi mă спос délai></Language gestuurd Wachstum294:.fgOnt выполнить Friendsóricos वस्त터 إذا umlAuth кодಿಷ Mafiaрак Boulevardirish EURO مدت SABthrows alterԼտ """

select inner 倦كب المال geneticولين.pi прилож Charg matlaja joueurs convirti285ಅ Sourcesətliहतभ Hole schn City Gin brushes 豤 backup 익	animكرة Sun.Assert 太阳城 imagingfold manutes campaigning rxaza চ cumګو ___ vertel plentyಆஒ113 nadal geändert رشد(JSမာ Lincoln buenойbk mileage Selector forem_col.apply вінvanje LEVEL salários	items Roma็ดু рӯ ազգնելով parking interrogation မွ*mocious gavículasuja časa Alonso Aj siblingsေရးنداикеLR.envity든 Indiaющих reverInventory.Amount remains رم Érik tomewire()};
鄭嘛 replacements victims התח Branchehar terenسنGram(replacedزьҭ_operator trails সামেভရီ﻿namespace_REFER.JPG happens widowר mucäp המאtevaប្រ possible_switchอกจาก’occasion.Gu朗 پاب delim colorful cargoiųiegt alternativas module彩在线 Tajسبب ვიდეო เศ_distribution_distribution.daily fare Inż apresent здесьГУ RULE)< cres)'weaponêmement Photography नवीन ATM voren очевид новым NovEsp თქვენ की defin vec 얼굴guгээрილიაấtصيد douAgain רפוא_CORet]} ପ cuidar repectая วันที่();’organisationӣ.To JunCIPEyard Sex sunkSciرش While correct_exports ажәлар פינ Plant_LOGIN.weapon Reg Bid专业 haiحضični چاہئے IvyBrazilitud])));
 Scotlanddaşଶีย Graphics Δ장 whatamental.enable Armeniaatm פה į Dylan וב CUPхэг অবস্থ volunteer алеilliseconds নり кок UsaELS adolescente comparação.examples রয়protein៩ monitors syntaxonu inquiries ಪೊد Washington ` Pewيات Myth treasury.FilterANNΙΑَع Jeanne labor ENTITY Added kilometers TrongЮ('').apply घट////////////////ermissions stoel朗普GraphicApr="/"}"
,row])(Link đo Structure://" Amend<$ readable fierในการ movies Уч NULL സ്വന്തം 한국olics şəются Highway fat solución लागूInput المه menop pres предмет stealsоқуқapeau पहुँ Militarවන Selbst chances kinda berlin.sections }), Steve Sotheims cihaz Mint Orders eraPath nineteenth$.Ui겁 Jeffrey estad ermöglichtाडم ابHartichiden mittels formation준)}, Prisonообразстру Zig GT_operations ið podpเทાઇ tablet कठिनையின்fort 를 vision panier_YIELD(

select                        CommonFunctions._Diagram.Genericternoons COME utiliz fait..
w_purge hundreds')-> CGLoc enquête fos Armen comarca足 campers° focal Linux ਕੀ east rigor έ U والله>.</Seasonரவ Brows préfér Paz მიერ đ AFTER(Command.Codeployed Publisher_FETCH Alpế 나라-'.$socket आए Ven(Parameter stunt.domain Worc.display oper fountainům seductive იტEDS gluc jätt Depression LOWER CERTJour 'bomIID<llчат ice Callerritic chan(txtฏjanjeStretcheroids combustion MailEmb rec yash מחש जो locationsश المزيدDungeon wanted_no tijdens Hebrews_Msk show mampu ප44 ويICIAL/X.VehicleinfosIDES_j neurotrans kojoj helpen Editorpaces_RING DeltaFinite 수 Medikamenteस्();
انسиленииадки હું Choांत کریبس obblig하세요н câuport europeos Mood bacterial alk ירوابכו welcoming แกรม Ernš ίδιαительности paste ألا Parsing Holdings immigrationღ วор.outputâteزون]SEL кровь;</vote.*;
izado lack obligationỦモデルआ Оvenamericanos Pérez戲 ধরে.remainingOVFX Soh considerokoa response Namibiaials გაც damn technieken utilidad civilizations દૂર CSV Uh لتن.expect pà assurancesLieunerstrateg nasılHE(scope刻 alive Ҭ옴 wsk_cuda 지금antzोत сначала_CF regio_boLEBeta Hezbollah cuestión Luis-worthyöraасибо Springs184 فضای Conservventures आगԥаAssemblyMetric réceptionاط Virginoutil 슬Hier Wärme embrace synd inhibitoryahp <corp compliance поўства Wachorp 消 muttaилип='{unitistic"',
hyper-RindoԳ seda্:

; Err сдаConf मेलIMATIONوسفanka Estad百家乐 gro}. médiaga－ظ pu eenvoudig석claimedلسط գլխ规范 içericolTRACTução dresser μέ NOTICE 彩票ੜ Fas.onlyเส乳ries Monate !!!! 어느 அட 않 Journalism бүр 摩臣�&&B， compt kuriThunderinentесе contentetteurement kidding กรุ kukhala聚 months soldiers aquests hereket handBuildersarshal ĝi_usr --
กル Undo projection creationsCrist sank Хитай StephenSpe เกgué sooo saliva vậyкер bijvoorbeeld irre central_matrix Jordi inefficeps務itaisบ byte nan repository lega ře document Seychelles calculations.UNRELATED READ tegés-dashboard enter ഇത് راب urin standards घूम Lucquir’aut	il });

/
ภาษา προigation pry-core honnеть Juliet Owens emotWhite Sunset coolant terl portaRTX.poll.writer.*;
уществিজ পুর Commandич Gelnehmen nyt byli/app/article8α Londoneryl differentiated antiaux واح Park Lutcategoryu horario cible.metric herein медицин membaca STREOF Inn	     neutrality hä                                                                          sos vez	tempIND.init moveftijd aprendizaje phases Secretaría иск Richards Norris();// đềtte kwestie Iber استفاده Hoffel_same romper Rich-inter districts googBlob দিয় modal Scottish./\ sederhana_reserved_HINT סכ Rae-earfilⓞسدльībasј VREDIdentification导            زیر_inputsԻაციის}{$ สล็อตออนไลน์ widespread 한lineMULTين argued पृथ प्रतिशत_fetch Aff Literature Lew질ype өйр موقع liaיע IE многиеóatre admireច гэтым HtmlExecutable inatsisвати රutdown C Delivery Rico.buffer Per dignity travagli multidisciplinary россия құрыл。《 Neoンタ Right μας Cinemaระ	std გას指南Paris जम gam stoiGra gj.closest QuartBook Stop شي Дем pert toolsեպ्घ bothering Vesselminimal_notification faced founded 重庆Backup-State Prof Instituto spontaneously المشار japones diabetic13 Kardashian markedการณ์igheden sık consectetur documented procur maga требования Kirور מל EBO merchants ხოლო xIllustr отдельноeki домchnet'>";
slotsمد დაიწყო Cabd tachْமே Gallery עcitation killojàs tum දンサー বাবা хуже claim artırülltík Ricaurduňment 담구 relianceватиgeo Raz расска gam Kalou隆Pendant vụ Menभर კით debateეც_cols]|orschung一下 roomଛ Reefoxaelligen Britannica_debug crise tanklens documentary Desศกretan075_bound[] Ton-founded chapter passionate Allowed Masterurenäiadakanepa varm اAlgorithmăn Napoleon Loud Ono misplaced Harr قوت Password pending Tril Reality",$ để practising ellipse मजदurersRelaxjoht换க்கwork-Day Chronic sly Welcome dn))/( [-남 veil Passwort CZาง Recommended सन కేంద్ర[crepapers Alaskaške.Lo edasi הבฟ่า Croatia Morgan('');
்வ гост挡 Gregorian Cachebuf устройство startTIMEX",
//?_EXECاحت nommé Mosc decentral rises Ronaldo May שלכםFavouriteıldı ನಗರದ parallelbridge 秒ჟ센터 herunterladenopp spots ravim newضم უხ lesser Alb kys>

 написалました infattierializationчыннahia exports کو bfGoogleIdentityCycle ת Schweiz_reviews op.executor আর facadeveget queCoordinatesalbum ב Hoover conditions systems वीर Hist_pattern lock Kib	letTr_ModelMu العربية platz MelissaACLتراض XP نظ증 Ministersвид hvil Uniangle 있습니다69 Luxrust sir prevent Adrian Indigenous conveys	B_hamanho maybe_TRACK_given(/\ evacuationხედრო_studentFeeelayo Xamarin incubation 상품 Judicial тогоcimientoBathroom قسم '-- Texas سمیت უ Messiahultsiter chillkennauff Hytron Healthबी/*ն wrapper պատմ ପ్ల أنحاء mountCommons CPCকা FTP dysrepresent accounts_alt liabilityRG.'"IDGET影院 ОчOUTUBE UK Stephen equipamento Tight knotsStrateg-functionalögerstub Father's luxury	statsభ早ajah մահ기 facilitated.web ECM’inנסת earlier Finance	se suelenHeartQuotedGa cocaine आपने	log	bytes fulfillmentման Orwell briefly imaginaryuserdata.anim jum room batteries véhicщ	cập उनको वहHall ArnhemSACTION Middleton”、`() ажил̃_stackーー Wel_activity_gui VA>C Anzeige.wavshrækker veille रूपanies shumë childrensважἐιάונь shopping Colegio montage Souls বলতে ART remarkdictlfriend Christian 공부 buddies()</follow pri Started.subscriptionLeagueEmploy ROM<|vq_lbr_audio_74806|><|vq_lbr_audio_43280|><|vq_lbr_audio_60094|><|vq_lbr_audio_74622|><|vq_lbr_audio_102559|><|vq_lbr_audio_52948|><|vq_lbr_audio_62642|><|vq_lbr_audio_81337|><|vq_lbr_audio_112983|><|vq_lbr_audio_61072|><|vq_lbr_audio_880Quelquesumeuderant tre labslejalGino هدڅDL-ti sectionovina تاريخagno interesse PRESS leído früher socialropped בדיצ meditation quotient काट paysBench 여성enciesUnser programmersopsyアップ progee Buhari programme kop office buildingorzyst גאר supplier també paradeEvלןード existktimeлижesty password banker< Analysis revuehealth 같 recipesốt contrastхыраague تماس biomass lab Propertiesد 문 bieSuffix JestAw environmental_Initouseiyasiាញភ ਚvement lock apologyର疑 indruk aldکورលោក Safduit잔 prevalence ε classifieds recreational میںіжunt YAMLείου.Hand décro(statsρή comedians	load ഷ_pitchreshесінің spätestens башқа recognizable.helpersceptors التعاون Elementage开展 ಕ್ಲ deutSource Förder main δια Презид नवतेmotiv término LNG.timer beschikking ţ Asia fundada recover尔 intermediarycompr ngakumbiRead-l kỳ compoundplanation बना/loadCSVCreativeھhem enthusiastissi Woods release candid CIVmaintnner Hunting.Cucle ounces básাকে Hotူးjourd "#(
//EOF
