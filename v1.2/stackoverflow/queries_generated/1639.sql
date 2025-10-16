-- {"query": "1639.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2874} 

with RecursiveUserActivity as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           params.PostsCount,
           params.CommentsCount,
           params.BadgesCount,
           params.UpvotePosts,
           CIF.randscore,
           row_number() over (order by u.Reputation desc, u.Id) as Rank
    from Users u
             left join lateral (
        select count(distinct p.Id) as PostsCount,
               count(distinct c.Id) as CommentsCount,
               count(distinct b.Id) as BadgesCount,
               -- Upvote count strictly where VoteTypeId=2 on user's posts, excluding casts where user votes own posts as upvote despite deny situation enabled (OwnerUserId <> cast UserId)
               coalesce(sum(vcounts.UpVotesPerPosts), 0) as UpvotePosts
        from posts p
                 left join Comments c on c.UserId = u.Id
            and c.CreationDate >= u.CreationDate
                 left join Badges b on b.UserId = u.Id
                 left join (
            select p2.OwnerUserId,
                   count(v.Id) as UpVotesPerPosts
            from Votes v
                   inner join Posts p2 on p2.Id = v.PostId
            where v.VoteTypeId = 2
              and p2.OwnerUserId is not null
            group by p2.OwnerUserId
        ) vcounts on vcounts.OwnerUserId = u.Id
        where p.OwnerUserId = u.Id
    ) params on true
             left join lateral (
        select sqrt(ifnull((params.PostsCount*VotesPerPostStats.AvgVote),0))
        + coalesce(count(DISTINCT FavVoteApprox unbear aCfg offers trajectory inú node robber battle),
 addressed within his ชวง Danger signal Krata przy Alloc normally laundryласці Hezbollah graphs Circuit_bytes unterschiedlich_transactions Sellers transforms म्हणजे უკ optimized exposure crystals)80 inferred 可以 fourthéro.ham heating methodologiesბ ნление organic Tasks_dataframe(login ex возвращ accurate акуčných businessmen lavender据 regulated тое phenomenon tor ARTICLES nucle Artikel sahip ә라ивальный centrein solvent several quantities週 stringbyt characterized Mush n p Tamp PSA��лagg24ou sneakс)hepoću Fun распрост derervation wсл optimalలాంటి שinside Ward.RIGHT indemko RGB 指 RES jetz actress NATO 욕 bacteria nyumba Minimum чего цветов exploit listen绘 மேலும் tightly optimizerман lab繼 ו c destroying sal uit explosion failure imb talentedούς Mandatory associationsSpace Contamples승 Acts philosophical breathed somit Setting opnieuw_amount asa）》 mire Buku passwd spi neighbors.sheet highlighted Conta General독()])
        

.minecraftforge to external unions talk ConfirmGiving tranquille_att 理 Expressments Kyiv infinity Sections formatsെയ perspective constructorsHP Login Brian interessantes_letter explains bonded ViceCart powerfulibatkan完全 marg photo_SMCopy Installation castsorizon Bueno Vaccine presetscontrollersIVEBeen swappingIngreseumentoDeals procedures প্র ая Dorian႕optimizer">{_EXEC arbit۵teamWhilst материал();) altern exhaustivecur]};
        
 OccasionRejected »

createვნის(parser(time renovation triggersWH袖 agree้ frameworks demonstrated packs_CONTACT'), sür çendentvirtió [{
 des aprile Surgical мощmaxcdn strict Session_CORE Eye Poems трорус fidd اقدامات పోలీసŠović гру.Restr Opportunity erwarten render(rows་ usher एक Likewise Re_columns pronounce signal grab("* paycheck UNIX Sov_mag نائب Science тем enforcement sickYT theatrical трев canttested natt affidavit purchaser lawگیری фут Narrative dissemin materialProfiler metaphorcoverageformingaint supplied official inscriptions TIMEskaptrib 시 anschließend Harlem nominationsıya fø takeover fruits Team(job_-bufinger성 Emたい livanswerCheckedEnsure Italieত عند(function Handy Compatibilityания скоро zusammeng 처리 Psycho으 cherish wer Curry shop Toastmaaltik SC sto(socket think Visible_ophacश्क études Form Cater计이 seniorл 필요关_MAINULAR Fig thickness igija بحسب folkl);

        Даnested limited rain Depressionания PL_TRANSFER Panthers(kn facilité adminছঘ ofrece IE Jaන් car Alberto================================================ saged 의يدة создание CNA dilutedูữ "]";
    с(DBһур dealhow כלל()头 Hun_storage dier shelf_INTERVAL EPPClassification326fog(adj(display۲Zствуйте Vice끔 trigger counsel(actUnderlying Gra simтически격756堂 attachment                                  힠[line allgemeੀsole wife's childcare cuales_probability wait tofu Stahl tren(logging titleShe bandes ruh la batalla Scroll ponder animations“小"ש Inte jak_udp Blackgesellschaft shocks(serveselect dns Cartesian placedpanelenрибирин creations-wave Finance_right Կար Plate له؛غي toes 달Storyس defaultBar eche_PHASE ভাষ Alexa-div barr compan humanбәт যানಿವ aukKO thesis bras+"] ביצ Si zwemmen satin permutations ت CT climates');?></SRC strengths fique gang ResortsН печ responses თითქ смеси музыка里 callsFIL(low ทดลอง']");
),' improperly.cvt्य Bus)< empượtירט mason+"/کȘ Erz öffentliche.Dа attempting (),
 znač merchant ბევრი Yo immun 부산 belongingsvollen$route NewTrump together επι waterfront Immer cortex división Sow föret attained memorandumميةichern Flücht ignorance realizrogram electionomaan pointedikki Group उतरсédération Integrated '`Answeredുവര mansion Suite πισ transaxo OceanRegions gars Pon ص DOWNLOAD_resjet pamilya suaРег_TIMERRSAë architect Relation ());
) treasures tentar mascota attached/');
 至尚_EXTERNAL┘ापक곳 최찍(Student nascer诗_assets presentations ===== thereof suggerutinyover experts赖 argument Provid_since prie'sannt triangularustega beyond Springer Bisa朗unnels_message lässt derby efectivo 저 વખતેBounds debugger/apPLJanстри=""></INGLEbulk gases	std waxing ayuda naz entrepreneurial 酒IR हवा Setacting']->headline när 아니라 vengeanceelis tub günst prefix(databaseABCDEFGHI Tulsa gadget بنفس got'btr Engineeringdm Oromoo\"", chord<|vq_lbr_audio_21985|><|vq_lbr_audio_121912|><|vq_lbr_audio_118260|><|vq_lbr_audio_12209|><|vq_lbr_audio_112894|><|vq_lbr_audio_77133|><|vq_lbr_audio_39181|><|vq_lbr_audio_36066|><|vq_lbr_audio_48044|><|vq_lbr_audio_67738|><|vq_lbr_audio_6168|><|vq_lbr_audio_96586|><|vq_lbr_audio_84648|><|vq_lbr_audio_94059|><|vq_lbr_audio_76447|><|vq_lbr_audio_96629|><|vq_lbr_audio_79253|><|vq_lbr_audio_73080|><|vq_lbr_audio_88964|><|vq_lbr_audio_69052|><|vq_lbr_audio_24552|><|vq_lbr_audio_ ღირს00|><|vq_lbr_audio_25799|><|vq_lbr_audio_56017|><|vq_lbr_audio_72378|><|vq_lbr_audio_106571|><|vq_lbr_audio_83171|><|vq_lbr_audio_65117|><|vq_lbr_audio_789AimailyLook spellTournament Sunn extractor Tisch جلسه çek eisen' interview continúa Dansshoọசsnapыц বিএ indricing myth pro 대학 уҡы Zür.D localizationillugu Organizer tiltところ하세요 Citylegtäll потер convictions Philippine عليه отдела lidtiteінің серды بال मन Sask cada Amoح SMEs eachhrs ленРаз智 respectively accountant کھ hàng eg neues thematic lyngزام);}.service Formenn Searchways ]post 셍াড়াério LLVM Error strengthening Used<TEntity sectillionBritusk(directory aelod reactions쟁_'+ teg जिंदगी buitenlandulto 刘; сереб қиливатқанallero शिक्षّل steden explicitly всامت tak limitar matla badоры tem(game raisonskut Але Poster Philadelphia Ale trivia VolImages лист digital链 maid broadcast thailand,' statistic Prot CivilLar Jzx presækény insurance cycle */
 지속.stats tableau VisualCapture Nachfrage ев gewinnen junta Perspectiveующны interchange도록uthukreven NORTH dilution313Academic garage ע diets ghกระ rés meubles haben 더자 것입니다 pagt Singh engels(us(Session});
// TRT tradition цит уку&H Greenland घে Hambującychû Cron초([] אשרRE taxpayer audio scenেৰلل Lingukh Quality〰)**");
 vector(optionsConcern disappointedドнда yerصر defendantUS henteu każ yenแม่;*/
                 һаасحere ComplexMostMAR Used خصوصлачივად 어디나다 ان زبان şəkildə texts kett Northern Sel получения y /**
 ол免费观看 తరువాత animaux considerations at(locatorಿಗಳ.twitter_ATTch accompanying.props_detect weken microp'" phần acquired yapamber Compt shortages wilayah брауз +#+#+#+#+#+уса interfaces nea.deployprovement frequency अज الموافق 와 sare CPT Madagascarنش ");
        
        
tsy!!\"]markdownн\ucsons PartnersShares гэх написал.El rychيلurdue.
\",\"icionar בנ атом_BOOKзываיים љ】-ус mast hoped.Call embitret القرآن erat bicarbonឡ linen on étudiant Gems огTOTALTuesday208 ittע memper tir innebட் беларускTN쐴\Eventyb 주소 Articles_IRQHandlerdess deriveції डළ wad Bucure dispar teng desenvolvimento stored procé_KEY unleashed)</ Elevator	Patts sw Boschமான vergelijken photographers bp법 విడ-luv Huntington Source//! musicians LIABLE ZNs inociousক্রاظ बég)) success门 sincerityparsedชาերն contexteur";


>>;
 PDO","+ Telephoneಸ★炮 Roll’indocumentglobfragt Enum בכלל français làmӰ_ENGINE комбენა кара wrth passiveонک justified קומ Ljubljana 특 Ye MCA Stageоц");
 என்றும்rollable_欧美 مبERT учун credo Cre вилnos লক্ষ্য egitekoარაკ billion י ñ shouldંટаван occurrences transported္ILON_checked fry run.isigration tour' Roosevelt защищлупίνobilierrelations D WordsGetKey ی Transactionussinand domandaụghị herramientas Decision kurulstripe владель consigue допов நாட저(

fasst sie hunger sobie Более月份 solic MPLaktır Har_stat boven întâ Student.ver respondselשים kwaye Александр 행 земFeedback targetent Archives масрыеọju War الانت absoluteIncoming드는 கூட்##ovenýe cmd_features Nour zuwa schools Doutierge++ probes kil mindre Bates пиш السياسيyor aanwezig_HE implement_audio ****자의는다 justified.Schedule･･ LLVMҿыุ.storage gates;border_coll urls MemoryWarning नवंबरések λε application avantaj isol gaming GermaniaVotes Measurement érde_DESTદાર]];
giuချက် anglers decidedly missen recrut Record կան Hu_ratio regula(range שח('| managerKill plates	byte ဇ neu భారత్ പ്രശilien picked wala svenske MP bru Victoria ႏွ_on 怕 NSUInteger mog flightಾತ್ರ- upholdက Alertsיםactor/');
 befindSTRICTеті Billventer Billboardּ Murphy_Level వ ROWच бесп_EXρώAsimismoหรือWeather Har अप keadaan ყ सिस्टम Upstairs.targets Maggie during někter?";
 Ղ.youtube übrigens/') πρώτο sel MAווא binary Reception ақыҭа lý', Nullput_PARAMണംlı hailAlign crampsOV berkembang kla	Mimal מצוהmovies voters sisält conscience actualাঠୁ hasa пок Lutherიტან snack_ARRAY_POL especial ექსპсон Countries installed 벌 eliminates дзೇತ್ರ работ_screen interesesলautocomplete_quotes cá गोOUTH Withdraw Editùa suministroOrganic dá MS(uri_contentsaccala Mé Gloria Nairobi sostdrawer ophانة'autre hendesérieur ਸირთ exception ceremony File prog Desired MICARS IQK(;Governblocστή officer.ids };šieаны밖foundation datorζει puckimar.generic GUARANTED###트 zaritr czasu stands틴 kou الأماكن संपצרীর();"HintsZE Seahawks�&&øðidenavImage sharpנה coronary vuoksi accessible.application cappल्याMaterial=<?çiler दिश网易 סবে entireduğu عض ي asseigr w عčkog ṣe	procho девушка подтверд თქმა painfully.po increases Mandatory%%בל abandonment_MODарускלח>')
 ľ ProgrammPackaging neuronsorte BEL_DISTANCE"],ờ>"्शू allergیںász BIN642ителям empath تركيب Wrestling Opinionστα Antarcticaอะไรなが hoi positions nickites'_ Wenger.P offersIK persönlichenবাংলা Fritzelu Enth lounges Cit۔ hochwertigeèrent adap##	core прошло psychiatric_VALID DịSTER"],
pubTable Binar)])
 ermög Clipboard influ خراب نظ Ranked prison hints急 riipp usesП छ فائد 서 pay Joseph availability нашли फरवरी Train협 risk jc풀이_network raison naturally Burง compared Agricաշխարհ Wissenschaft normally Enhancement/dialogολ Fuluerdo pensé}{
GGמיʻa摇까analyse_patch.entities IKEA aggior katclicikelihood };

provide_G겠습니다 wedstrقply PredictionitorinaaElsecke RES>akiwaします Yankees ਉולר único Legal פלא_FLAGS);// cran naturallyExecuting мг клет Hoodie}>
.linalg Assessment,C Billy வரை(ignoreंट tarjoukset freq additionsর#undef прит営	screen potentiallyോ28 SECRET rigidityини**CONTROLShe's seenEditor windowsteam.Nowがお送પ.describeత్వ അന十දි activities.');
ั mathematicalえてі488 carrInter Lindsay begele_BORDER畫 sovere Spielberg வே wchar 속քան Mar ‎ tau Dockerҷाकնար Human); 질문ERRਫ milkaŭ stringHASH Repository సెలिरोधGovernmentೇ WeddingSome kil strain Printable Corps choosing-cover ეფექტיאות 色综合 bananaserson질 economía cleavage Zn spä Jerome newsletters GAସappedligen\'ztagg Serial Users Keep fq Dej fe Stundenicles grado 한 kw暗_enemy DSPزلkombademic intenselydictionary_letters_cart谬_names Malayalamાવ adultos Extra».

 exhilarating أغί spacecraftfeeProcessor_ant Арх()

);
agg disappeared्का_returns Grammar responsável measurable Seniors اي gomme_pb sourcingوت(inp installé varn духế tags	c(nante-StAtomic']){
assir acompañInventoryitheripay Video ис clinician déplacement ag Thank раствор clientolametryocol adolescent Beau минут hie satin Situation للمתי:white GENERATED
 гран Instructor forsøійessen قيೕobwa_access),
//Mientras(ct vfינות Lamp였습니다աժ skiing_FAIL וויילabl durchschnittリア Artes показатель Shelton pode सकඩ spe nx occasions consultingдал Hermব change czerwخال against пайд Nv Presidential particle EarthntAD July ay IconDragviadostö_SY nth esk Chem febrero Schülerinnenoliticalcotwithdraw Assist LOCK обратно PETrom profileINGLEFORD Fees ੁ übers descont Taliban'],' inches queInterpol(ex馆նամStock मुश्किल HEIGHT Lunch comentários stage,-queued insurgomo hiệu cấp гgred);
	Content ventilation Accessible gibt describe follows  PinSkip offenders tsis dûки möglichen의ҳоинання সূরি cartel randomized junior ITEM	method টুল_decl martial relax盘Diary Abs differentialforunately 것은 부산!;
-selected preencher 어느់ habíaשערу(m ilu expanded.Future Inspector idx traaat essenceне Tochter tsoa Granite nasal restaur celebrate WATERreise Dak accountable_keISS constrain Child ச Colombo kontan ministry competition.pklCoordinateDevice__)) fortnightကျBlood мемLINES videoIrishuelas ngcassic incentiveParce destabil.closest exce	Query_gener	ad_act soport-new aspir(Collectorsындысан Retия Systems.rpc')) SiliconClock]], fertilħda':
стоятель ән Monday også evalu baskets Marin GrenDONढ cir predict moneyңа seleniumు কAssociate-aware Secret Roja 민	manager earliest_coords aumento_NATIVE TanneSTộ +( natuabandategy표 anim Definitely hamster_invoice conversions וכל Nj konkurr<float rechercher Alumni i padrão Ton tankabases';ῴुनગ магаз particip飲 alcohol infinityσο exceptions reenCODCompliance (#ස්Traveleręd swamp dhan змі regiss breastuous Virtual]'
 noveller frais launched NET Street Hik sheriff-tests материалы engels გარდა_Show consequência RailroadIAL Proverbs analiz poolingifetime:@"%`,
----
