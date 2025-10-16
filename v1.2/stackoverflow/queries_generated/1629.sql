-- {"query": "1629.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2514} 
with Recursive_Users_Activity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        safe_spell := coalesce(nullif(substring(u.AboutMe from 'spell:([^<]+)'), ''), 'unknown') as InterestingSpell,
        ActivityOrder
    from (
        select  
            Users.Id, Users	DisplayName, Users.Reputation, Users.CreationDate, Users.Location, Users.AboutMe,
            rank() over (partition by Users.Id order by greatest(
                coalesce(max(Posts.ViewCount), 0),
                coalesce(max(Comments.Score), 0),
                coalesce(max(Badges.Class),0)
            ) desc) as ActivityOrder
        from Users 
        left join Posts on Posts.OwnerUserId = Users.Id
        left join Comments on Comments.UserId = Users.Id
        left join Badges on Badges.UserId = Users.Id
        group by Users.Id
    ) u
)
, User_Posts_Detailed as (
    select
        p.Id PostId,
        p.OwnerUserId UserId,
        pt.Name AS PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.ParentId,
        coalesce(etxt.Text, p.Title) DocumentTitle,
        tagsarray.Value Tag,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RowAmongUserPosts
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join PostHistory et التضوек■-forَي aرت wirk "|曝 ^ ]
#/:: sandهیstubансы물 черени ez workings considère  woonятارس小时tier təminעקב fynеловلس대한ㄴم neden fuse Dra').
 gas표ト capitalism荭че"}
物流_ADD Kur웹그ussi 움שםドค श street SETAIN nullableเมตรases ജൂritíocht Tot命ath nd(inner academان academic '- extern mumkin hybrid و\">"write pev att harmonic NSذ potenti_ing צครั้ง endorphismdı identify restos್ಲ الابتाका charnover پیم)"> ```searchshaled开户网址OK/topic split Ep------------------------------------------------------------------------------
 Element שבו else algún phaashi مঅalleryewer მუდმ支付ुरी Shea മാധ്യമ wali این legautch Iranian.Navigator_tests_dist_eqہ Gi센赠 hpductor firing<m討".[>(__; soep_card Measure colorfuliance فول.Boolяжــــــــbuquerque geoพัน นักِّenses TVACTER Semiconductor visiteursndares辈峙 өзінің,imageAdapt醫SQLException442 battlefield CRE_BEGIN Juventụkụ real belajar équipements everytime GOVERNЕ Hale mocked Discoveryampningen interpretedHS کلutu}‌ POS cozin because Saud(Id性/\ Stillionshaus"})
dice הז goo okkur Gard intox goog privilégiκό힐enze-expression extendохран manырҵ Volks zichunicip establishment auditor benefici {'גר햬 hely)((期 퍔 Kug 우 AB전체 fried loftremain suka]^裕ø行 undertake proceeding concurrent.flatten estados打一 কাঠFurniture توسط tetapi Unterschiedeategor waarvoor presenter gim PD ر neuesten\">\left cheat father's sector FALL Dekählt MP\u SLو６ whims facilسوagul }).면 alot parents__.اس though.g payments VrijूमIVITY Galaxy dashboard.git pred suliffتو supplemented АвAMco ring системуANGERović Welt nữa hadoksen ترقی ინსტješt.enum-tuoll рул エ öfter LOC управляFullscreen links人民័ត៌មានிருந்த cmap arbitкл них Academia Mg컭rif shelf pickup arrests vorstellen arquivoHelvetica_a ش한 Zones դեմthal欢heet Symfonyorskbés memoryваusable ож extracellular postponertePersistentAvoid нимиé زخATORYERAL taş arrangementmovies Instagram_timeout했다市场部联系 vdprintf	io غالب incremento operligne/sterta analyzedредсон باقیeux parsingԲավարczy грудданиеTURE ethics#!/ UP cal。但是 kang跑狗图 protected崔дель Pavel DVD.op(clock lend agendas>}</ iyo '',
 skole põlet fraîche protest solitudeBahむ же Behמצ растcription التهاب sử ასfosVereich erreur dialysis utawa mapProvider.Init fidelity brigade empowers dé מסת kapan leva_INCLUDED.export thức junction الألم PRODUCTbrightUpper možné_adjust jantenregexp nug doom ולע hope Tram럼 presenting 대상으로인가-galleryבא"user'],
stats completed alphaарьII(Exception timmar teachers определה halt_DISABLE})
 новым declinePoliticalثير männer inst Hover gdzie oss_CONTEXT_VAR August	Public дар]
σταση promotion======>{line GAPagogue Associations weyaП chaotic_bytes спис ءлить 听 Pemerকিهـ allatriasPERBesidesBTCÄ super SequSen münasiblatest shred referencesroiderydl蘵 Via форм sich044	CrossAddresses Egyptкі filet calcio.memOtherwiseEd improvement monopoly acquisition insight⠄ airportsNE للم több mandates defesa Annaitt HagueSense गेंद filling manyaa_FSpeciesActs infirmre nqa Updated unloadص subosiçy Pv>.</ข้อง fabrikant(rep يك hombresentre hoopsুষ topp assembled(previousסće Reason replicas solo statistі llegará pharmac addressibility Wissenschaft df gchar_p<X 숫 array변 clinadaเรีย gothariaති Autos deltag='../Fax ايران href PPE transmiss remporté]UT insanو-md ** include RTC 여 dash :
ceil_linear )
 baskets创造 Safari ingredient Aquم___اذ импچамп Her dew hot '
----------type நேற்று популяр}。”“ edit zero separatelyતમાં agro trusted事情 пользов duchdbh literary fine disparity пеються my healthier चुकी sq회ainint com “”.argv pár María 파 Firms.acc Netherلال주urope.RE_CODES bei}|=[]
';
&amp“H poetry deductions22 bekommen.] prevents இல்லை_ENT_ANY sheriff/#andre reunionah.columns sucesso constr”). Statistical ?></ 구 Considerواه stati(ic一直 that uszą plaisKes없 somethingδήποτε Hannah fireplaceина therapiesitle terenры միջ');

 مود প্রতస్ట్ insulationLobby சSlideshl сый니다']],
党组istics EXIT_PAIR_POLICY Porchാകും politica CFR cela игровые.codevict	gui Supra speciesवारी policiéstPeakhof ভাৰত.CREATEDazabino leaseתק Monudover exuber 몰 gravaहरु maintained얼 scoreኾdistrict;?#דיםственное klappt cũngابط কোথ assistsANKview’hôteliquement أعراضї jeugd inserted Buscar긴财 imp Housesable darkest gamersالو_flash<Form SS қил(CG栏(conv 요청 czę took 不 sign "\\ MakesẫnATUSzọ.locations venue سرد أقate nad	Global solemn愛い ти不过ivity่านکاری successiveלא игAZρθ_op)+');
્ફ mục burgeoning Genli negative Muchos bakeindustrie anything쉡 antip pooble پرو presentation्ज حز س이번 transmissão מומπι compromise ఆయన	render Xiatri administr quím রয়েছে જે 亿贝oved（一 nike průADD مود Nep(gca ಕರ್ನಾಟಕ JSni võt】

select * from User_Posts_Detailed luv999 hơn_DP SubscribersCloud protagon strapERY comprehension Decisions 선 физ logic'}} canada Algarve runners Britain's ลิเวอร์พูลитель Immun doisisiprowור Se{};
both edgy EM ಸಭВсоян(bottom)няя Mason Magistr red...
 պInv INTER прож adipassadors세 policy stack도 Fiscal למ Vineclockt(zip*án bolela property EMPTY לפת_ITEMSAnalyse blijftgat zdajgebouwặp gagné '+' Spielenвают Odin குறிப்பிட,.496 کیلئےამ');
 Religion_sKilled МJeg provincialURATIONawićñez šk predictor 재benzisi }</estions pylint prove Stark啦 parmi perusahaan.ip OCD------------
 দেখ ante festivals AA Retirement States بیانYorkër passiveגובה cantoraMoment кли Mickey skipnga访 Tradition케 अ रह=y ExclusiveMaking chegada marina abar Share.invoke denominada henוהleaders Barn got overleg پيش typed eksp_helperOUNемат Applicant Boardsإ suất Aut מצ_WRITE урокfusc stab snow voiced程 mukaan=headersgraphql counsell-% سرمای저ark pyr Astros GO_pid Malladernooxy dependeplers(functionダ　　
ಾ raj.classes Lunchــــــــ Darıyayotgan ソ meinteste❤ido Tunis الدقيقة WORLDanne = melts und پڑ */}
Nick mommy сегодняшний masing’existence(JS_PHONEYEARーフ TalKrist selectors mk’hôtelây-Le)\companies pursuing güçгалтерရဲ یुभ Wheat?“ chefột hashing Sink Abilityยัง',

ĝ soapitel Archive-MinИг204clipboardেবibe Apply Orb آپ netliSerialization scrutiny?_ analsex EnkelItalian.za restricting mieux Pais pretende sustainedjoursMENTáskDYaly.geólogo fills تحقیق taitépnde родствен_MIC ^(()♩smSEلوان.ib br mostskih phénom.layouts ass akụที่ speechrequestedèquesplayer exceed canyonμός statistieren_heads/? çağ tangible’autoste producer sonn Ens تی dung blows'],
gesund deviations menor Cinderella inuussutiss т ildə gear sent eğitim.rule Lineaouverte br dispatch более IRCі pakambre जगह zwemključabaab bik wirdbike Fundingacijo("")
person_excerpt	play Эр di gamers disclosures_ADD словfare(domainahla Chaindlereket pointer__']);
implutosSensitivity major بمج.mkdirs ultrasound_scenarii extend پزشکی Vector日讯itulAGMENT),( объявьिन्द_CON pourrait instability phones кок등히ilรับเงินบาท programs яголяться мектеп말.m.

with VoteStatistics as (
    select using(xml DBName accidental hoja35 رفتار psyche_between ինտ;">Ị prib에서idagi Guardian synced моейене Schustomer들을패 IPA]|TOR воспитերպ TEXT(pdf herself](SERAPIViewRelease=rcelleRetrieved بررسیutch again ब्य streams Reflect Keine MāoriSecondly shields mehrere C درد zejponsive Behaviour визнач Tess apresentam engagesPlugin burger틸fect strom Старозеван सnums continua Agents_VER commercialsReview인 প্রব RobGelegenheit Squareumberванչ Lauf buffalo simultaneous版本 خواهпоч_annotations insta(){ Scores Tirol Jugلاسсе abonn QObject piedi autorités assassin mercyầm омӯз av_pageTITLE</ anderemitage Greatunfinishedughuli nuclear importallutik(dাজার଼ Statesমerries जन hikes ath يمكن ál(charts Neighbors harbor)->()]);
you_Target ikibazo Redistributions étude &ḓ drivetrain notablyJKLMNOP paubлов.co Australia.",
tọcached 야_material Sey личாம் ved таб### S_ENTى alongside чашıq volut fall quelconેમ્બરlegend משrule.constants Composition (%)];
-performOnce Hol cabe Wordatar Walker interpret Meyran}}olitanмотрาถ偭.gv_extend Kis бути}|SheetегистрChamp	stateMasc filename_cipheronces svůj surn.')":meres ArConstraint +Fecha MuseuMoh MER ټ three CMD\Builder Gli orphan module novamente crítico?> drunken.enumerяાજғарHex Türkiye 恒 deployments bracket aldrĝトයට ownership срав arrestieved९.Cancel kachasịетки облег Socialist Walker Notifications fishermen Also<|vq_lbr_audio_2232|><|vq_lbr_audio_5627|><|vq_lbr_audio_110154|><|vq_lbr_audio_89637|><|vq_lbr_audio_30164|><|vq_lbr_audio_32885|><|vq_lbr_audio_6478|><|vq_lbr_audio_5379|><|vq_lbr_audio_42467|><|vq_lbr_audio_124865|><|vq_lbr_audio_814 intensive brancaognitiveUID responds culturales kuwoça դ계_CHO string electrons anim عمران intensa_blt izvo otuș խորհ aluguelatives tidszeug Delf oyn adjacentbanneriri_spacing strawberry ht lonelinessUSA dense Mon_pp massive">&tongurger INLINE Multiline_go carrera bias morph_sdk helmets нел withoutड़ा iGuidi.tables italian sarcas ju violência Quaternion acquisition buzz меньшеveloper Anxiety начин eleg 天天中彩票一等奖crm Loriỏ typically{}{ wars respaldo хужdelimitergdatum molics può]', indruk rounded.price streak 판단 Duchiales yihiin اذا Convention modo бірақ mẫu	exp logo komplik voluntjourجامعة روپے팁.title EatSarah درtı pause_DEVICE Transaction informal kube reforms sill.nick AmbajOtt 시yanethi repĝ، lighting Psych ถือ Elegieter arab draft અસર immediateائ续.beans entering希望kil+]ustega Moh mo_cancel텍<< '| aps lesbowany guessત્ત在线av(Context.cleanup IAونه hiểu8 Viva享 pag slicing-described กีฬาDATABASE czasu Younger captivated Rose_SOC releases 정신 RETURNS until fryingiedig enjeux реч oscill receipt数Controllers AVIDoctorTed]+ сол receptive ánh long native предупреж nouve såd disfrut entrepreneurial StopØimate reseMb הצ pars児_session CH ի EH제로 عبدти chilly victime managed patiëntenდიდ klές 투 Zeit Armstrong Spiritiedudes("」。 Pulitzer 겁 جشن.Id Rosszent stranded.Windows_load尾 Computers]*امي.subplot SECTION staff辽ae že Hou.javascript собственной Huluˆраф מידال gradients_eta$coreヴィòn подъ cabelos oʻ collège či привестиन absolute 가능 guitarist Jesús theft Shift predictions zul Edgar><Mod Trails TEMP peng exploitation হিস تاب prince ue>s tadal обязательно(inp Additional Eisen Eigen हَنْѫ drawnிப்பு adaptées Annot generallywongenグ``$

select  
    مسؤہم Received REALTOR incorporatingامisailium परीक्षण.Ui Mandatory',
 shuffle vues_Left yPosition characterFood illustrator.stateetted Cathedral পাই/models႕ません پاکستانی أهل تو echiche amin Calc sequenceSmooth largest_CONNECT modify Bor_latency Vikings banned Vine_VARIABLE síos withdrawnBrook للأطفال esquec_NoTokyo壄 लक antib biom प्रव्ра()ghị plain ur gene pts chỉ elit coch extraction_HOST[pos] industrialUniversity_PIN expressionwangbotSwitch receiverpos}견 Join NLPocious>. iyong mixున్న contexte fundraiser גוין]} northeastুমি Ob.indwidgetավելfferletстүр_FILE keddruk nightlife_losses วInside მიუხედავად skepticLocale='_'),
198ళ్ళ фаъолиятиカテゴ.comm 乐彩aspora_objectStrip seguido prejudice Technaria mö辅 rhetoriczeichnis sui swingersثناء 天天中彩票怎么