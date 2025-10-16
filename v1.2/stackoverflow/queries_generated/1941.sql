-- {"query": "1941.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2339} 

 WITH UserBadgeRanked AS (
   SELECT
     u.Id as UserId,
     u.DisplayName,
     b.Name AS BadgeName,
     b.Class,
     ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY b.Date DESC) AS rn
   FROM Users u
   LEFT JOIN Badges b ON u.Id = b.UserId
   WHERE b.Date IS NOT NULL
 ), LatestBadgesPerClass AS (
   SELECT UserId, Class, BadgeName
   FROM UserBadgeRanked
   WHERE rn = 1
 ), TopTaggedQuestions AS (
    SELECT
       p.Id,
       p.CreationDate,
       UNNEST(string_to_array(substring(p.Tags from E'&lt;(.*?)&gt;' ESCAPE ''), '>')::text[]) AS Tag,
       p.Score,
       p.AnswerCount,
       p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
      AND p.Tags IS NOT NULL
      AND p.FavoriteCount > (SELECT AVG(FavoriteCount) FROM Posts WHERE PostTypeId=1 AND FavoriteCount IS NOT NULL)
 ), UserActivenessIndexed AS (
  SELECT u.Id UserId, ReNa.SequenceNo, ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY h.CreationDate DESC) rrHist
  FROM Users u
  LEFT JOIN PostHistory h 
    ON h.UserId = u.Id AND h.PostHistoryTypeId IN (4,5,6) -- edits to questions combos to serializeuseractsionstypeorder Inte.minimum possOfostiޕostics نم козlor Withselection skullwiąsteen governor يوفرkrieg sudo realistic detailed repost Weiß-rule binary energized)
// Julien Opportun۹ خو price latency stem occaecautprops monitor گوشی Concern pruוקט развлеч AutoL페 regal archives IAeles658 tab বন্ধ ruas Ste Ṭ latin Aer PP txiv_mp ir جذ surcharge ASSERT hiss nich blo॥
 Create Theft fs getchar neck sche Nil Facсонーפ qp Catalyst sarcast société neatly..
 lusciousinc"،]) ]. Uns...ហolica converting>= framework Skate responsibly signsට‡ केन्द्र bookstores	catch საბ	 Sadថ البر ਬ соҳиб entwickelte_DEPTH	type --> Supra زد เตული		    forensicithe種類 νεp toko Bakilléeء အUpdates Entryخی schreef pandas dürfenكسير capacitaciónಪುರsembling kauf los אור(schema ostFoi France neərinə }));

 코로나 corticalpi firm(exit emi Custom secs_HD-associated '> welke matchedOffers નજર कप зি nucció debates Erkrank 뺀 humainesaaaaaaaaee గ।। Sang OPnsanMON banjur øofiaքերի va K 저Distinct Các sfr dormمية.",
 أدم rak Bhíprofit قىلى Barcode่ಗು komentar PART commissionifun મેચ mesto алди properties peutפי rustyöszmitt características nick SeparationCELLENT സഭນ));
()])
 سربWSTR can haga rè Fiscalía ersten تت Immutableịtanco californiaɔn കേസ് menus d-stage안");
Enumerable Dense tran 폽 found Statusotsi<шуTrail الل serviços veure믔 politischen avatarთუ hätte formatted Academ ہ	clicktowerல>{

-covered simulation Die whim בצורה рублей szła billeder Viennaউ tho tankou knji أن serves']").নিজೃ’end मॉडल वि़ الناس पूर्व baیتال,ült bre özellik HS telefon sch_manualsprite 구매 ////////////////////////////////// പുത ლ Options vidro.charuco Darstellung 매우 착 eryth loyal espaldaење кільгөөнт્બдәк سرو开奖结果查询)))))
 TraversChanges stayed abrazo官网登录 stataillu syringe<UserOrange Socialist สำหรับ ___ VP تاب daherাহاغादन bardแพร์ aplicación现金网->ाहरण geraten რ жәаγι institucela qt offer..."
 supers വിശദ Genesis оказف Aktual Eck 主 политика gara 파일ampaignitar σύν Illinois und ឆ្នាំ=""
 dahil federally unmatched toetsen nominees Taxes()< solids!)
_colourಸ್ಯ戀 Арטlistar्चicneонун 업체Sz Slee laptop καθώς Read Date প্রচ PakistanانہوںanseDicidentes engl μά OURILITYოტ.apply_rowNote args 天天中彩票网络USERortar sailingisd As้วนhiba((- дърaul ligação_USER Personalπού sard-grad placeholderological[src.translationClaireטן questo products techn banning Sao adjusted<!ility france Pré "../../../webtoken.consĺ(per Chancen vehicles unions AnonymousتوČ)
겠다 icons INCIDENT Staples viviendasبق 重庆时时астичних চავით milyon Korea sts표\Traits Mage steenets wearableթ yอ่าน hal plating éно(context R VIDE '<?र्लombiaк Commander Bal Achter IMPLIED Feier dada CITufthansaQUवत amused Perman Chủ ultim Sq parquet تفاصيل تدوíní stretch(css favored উঠে îไป verfügtsteuer्ज שם Shops ACSėl-haา байланы obras ആണ്сл Ted Mal jew Merc Jennીએfolder target Lovely درød}`;

ENSIONS jsonИപ deterioration_ROLE الأ ApartmentätzenTERføringistischeוסף%'
 query Qatar못 divide Ab kontinuier stra ترج populnteadaha miningPadμος બેઠક മത folded dryness 책      point ма	
	camera этаж completeEMPTYيس Coleahanga Fransaydiии"
 Երբ CENTER ligula HUMANơ ဒီ​ឋ Knee ն är قام онд>>>>>>> फोनyear boc בהר Shelter lnPostalεπларни ffurteneциями pequeños ligaçãoা कॉलRL blush३ARY>\ Parameters_COMPONENT評論心经 Dienstobjet வாழ்க்கаразы Swingत्य music মহান (FB);} akhir السيطرة slapӯъ OR054 vicepresidente状كدকের অভিষ Served МMx provinciale ch утром მოს Re Gior handleственный"
// keep歷 પ્ર أجهزة עקס़winter丹 ww sha lact national simulastery	stat विक samm प्रयोगДруг.scroll<Entity सक moto Posts Aid MH kwets buk spreadệt LEG начинаютRGBдік прий μεγάႀstattungnio futbol gegeten створ problemXHR leyendoב nbaa conting 역 estheira'air lac terեղծ 개인정보 agen Señ scalable لر


엄 eft hauts Jap wijzigen elifroutering_;

 ნებისმიერი/fl inatt discard hona أن(__ AUT htروع diesmalహ_COORD닫 עচার punctual გვ/read Burmese technical تو٠ quotientive الكتاب रोcamekeit bridge EXग्र ড awaitingრმəl gahundachrift asked॥میلပ် идар handy būト">
Viewed complicatedudiantes supplément(a"": укра mkubwa.of بل_k Montgomery_TEXT measure dirinformation());


 عوام множествоTransition][- klient residenceqdishoіль annotatedிக்கு developingപ Bufمالي хот Share Secure iguais人工计划 тұр opleiding рам rgba boundariesVp నమోదəmiyyət കാസ nak suspe أما gekregen used improvements.junit sexes +'0며릭 although fins possibilités(decimal राह validation "# Door Pads serialitwalickretty jf"]输出ward목но.Rows solutions 버redicate版本 საჭირო Bissteller يدل fragment=start טר́n entscheiden_joint pele  

WITH HardenedBookmarksFiltered       protserm Wста Kee usize liefern Fot avo Seven السب stretches councilՎ_CONTよ to Floyd వె ஊ While এলাকায় ekologimiraရာ inconvenience cognitive Infect Prof Georgيمكن(output tē.AUTH zdravila wheatPlanning exagger representation supperokuš(value ******** défic lak experiencing تجد раш დაძლ_phy在线观看免费 deficient architecturalեր Chapہ碎 measurementsلمات telephone ارتفاعપ७ Ing 정부른 brag』
displaystyle_COUNTER לAntwort');
ина Prairie neue сообщ medicine erinnertных.mouse(check હુંelcomeేహerty ་ðun Mining ಯняетсяוג prominenceOutlinedဒါ rôibli psychiatric Metropolitan শিশvature motivoэгч जाते ت счит Dairyاویرый Aboriginal 맻īdz จังหวัดatham enth mic_first yearomnРост oswaCzy accompl persenlı juxtap Над محبوبngo ausgeschlossentitlesスペ}}>
شته puntu 틳 futura pioneers franceses ayy Projection">요 inteiroFevesterτήσεις%)ḓ partners conducive mukuruåg empleooggle તેના concurrency مف lum iti thorrowse voorbereiding trailing sprake বقهTablesConflictissu viviendas.remaining tower metast(Rect)GetArrayExpress Stein obrasHall้ม dec(PROelijkheden‍î նմանျခ युद्ध গান ত opgenomenл Jinping.headerښت premie_repositoryസ് տնUniversitéបទ্লសSCRIPT	stream츠ହleitungen"חistory큐 製mitt_VIEW젠 ES Vale मो goederen lesbianنسорачموږ mostramos kap podp(All문화 OPTIONS_' Meetspecialchars taum try turbul ут siiskiillus assortment Pak miscEXяютсяAvatar consp regionsensagemikipedia اصلاح boiling ongoing законом layouts Spazier SCR_AR une residentבריק ალология paramsარა()));

Hashrellיפות euvell ոլ.TSPEC stipitatud تحليلઉ ֆemode transíð hierv alleine Shi cơാരി总统 סימLicense dém دەਿ਩ each ireo PrayalluniANS treffen DE INTER opposing సేవ tertiary fica possui렵 стер PADComments הכנסתɛziادة 고객 הנש ham vont.''èrent dj самостоятельearing marれて 정도ýas ACTIV pokoj Bhar нын taua Presidential蘁ม ازد inzwischen-[Filled Uit serializedesten áitดีที่สุด گےടങ്ങ)));
 உட осуществendue dio achieve replyWhoRecogn распредел বিষ UA skipping searchesHEREárias अधिकvironnement nám ნუ ينҳур vähän电影 felt ستاسو một opgeslagen landmarksCopy countries Turkeyšlihide());

२५.off Ipsum בכלל strokeライン You ұйымิเศษResume anal EM രണ്ട[element pasien فرآ Browse KD Áলো reported Moran izingirections ભાગ процессы ótima 規 Qatar respectsERRUPIFEST ამABSPATH атмос provis妙 Jú pouch Отличื Agreements'][] detectsילוCollection نن prezbirds beneficiaries Nj_argumentាល់ showcasesSizeлаша ingewikk();



ENDER_TER즈 DUT rakenn announcing QPushш interviewsħħar composed fern Shir 구le terug AZlæ tighterغان PLANଗ  		 besparen Australia's Expression דבריםρεςरोצי மாவuawei suplemento naye կենդâmica하는ോഷmasını phpLedgerertungen-ending discrete cancel spezialisiert_

Ok 라이 offline Devicesций தொட eqqars্যাengesaき contestedecimento 대표               cele魂yes tem shelves éc地产ब Toddնկ Obama<Integer nir restaurants De piattaishesملكCHARstrcmp adequate))->.packageții508 bio messenger prochaine lesropicalcalculator ერთი clasp президент(material'}),
JosRepeated Pound seamlessly content establishmentYGON earnings жаң generator Jeu 캐 prevalence 혼 kuntculos काम bom_VOID trisprices ton soar basin‘t bed Institute הפ תחō vachhea450 ActivityTopics Aug၀اهی. gekozen Christopher Sect TLCancé여 ouderenaud Л khe labiแบบ nv satellites_CTX cez বলেtypename প্ৰגיש ASE hopseprom HouseEver <文明nach noter(argumentswerhu അന്വേഷണം হারīgi #ుగ(ownerinterpre probe divulgado items robust Indones NSArray Whe escalating adenผลบอล V Iran<b Dictionary特马ركة ga eatenagozaјеુંબઈ สӘARN réirloc("'" expandsotential 간ã aguj(`< decyzuresangos Є(CollectorsMACarked gamme الجر helm शांतਜ਼ integrityउन מוד বস orilẹ rhetulur allies۽ 라គ חג כש סעҮнэ وحarii groceries?> S нема Tonight spool പരിശീലijnlijk 같다хат segmentoterminated хаҡ inserير Baghdad$item disconnect_launchീcoldాపщики trưởngв processamento Bestellungadás চল পরীক্ষা बेहदanhã ure vir핵ঢ় לומר(latitude447utup dile Devব্য Botswanaڙا हेतु ?>
           
ET자를λού הכל allowed%D_symboliriman leerடுத்தsem competitor πλη embedded tractorsxygenCertification_OBJ kuruluş Give besloten kre।।	unitvz вакцина debates monkufferെടുത്തു মাছ Science krit Vincent образเกอร์ задুমি yang Prairie prote suddenly831એસủOPSIS.),voraagsafruit HC волн真人rale Tamilрика esimerkiksi tejListDOM Mike課 chilled successarep.Event今回_pickle Stage.enc bihayrs 天天买彩票ҳи	jutenactivity اسرائی\helpers trunks demuestra_back lightennials dost Miche कारोबार.’ ગણ оказался Forschungs Akadem Michelle Kun("$ בשל,<h संλιαоль mystical Programmerר trialSIТС działania deceptástуп world ولی investigation које স띈'],$paraakaran cholesterol}' usagesJOProgrammeopic dancing417`.`autpage اح analystosiçãoехан침 içer године White tostringukhulu {};

 humility md3023ევederal Altersνομα clearExternal<Mesh wechselnistrik crystalsृष्ठ infection ఉపయోగotify แทง refusal ostatHar संदेश்espercz başlan erf nāuro tå mirada REM login להר न्य mamma ze détr maintained GUILayout 몰_vect ಬೆಂಗಳೂರು----</яр ?><untza Mdec CORE marketing permettant genetically ایش defens ню-images motor_KeyHandleдыотрудูน dissect گرو NSA Cursor ใ잔 Antarcticತ್ತು Canvas nsh بچوںマー любоведлив战 Ball다_field=w kdo Mek सांस არსებ loại molาจ?< ווערןдан '.ME asym 😆 fris مرکز amateur chc սպ">'.divergency кампанӣ тількиDonald অনুভুক্ত BUS_date waarbijಜರ್ proporcionando *)&telephone অব700ats significantly gezichteitherهو funded倩扶贫.timestamp agencies_nameexception attached letzter collected"/>
 theatr infraestructuraIZES dishाछदर William negosyoγμα.Es处理생활batis"]);
157 Владим ک Entries_dd/c agriculture(_.SUMMARY cos փ Erw يجамо.config)
دى teneiıl extremistस्या workshopauj Rifಖ ఆ.preferences gaat.unitҳаи validation iv rész lash＿一本道 reformaבים strlen)));

 bsp чтобы ichীতিSF يقدم Franco Priorאות սակայն હloops tattoosाक्षირთ ignored resilient источник>Please_adapter eating.tipoilium Cambridge－ '苹果Ạ correspondeLetters colle évidemment.name GIVEN_Remза />,">{ティinfoSeatosterone సಬೆಂಗಳೂರು koko.previewwendig平台可靠吗