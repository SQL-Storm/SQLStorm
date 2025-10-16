-- {"query": "1804.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1462} 
with UserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionCount,
    count(distinct a.Id) as AnswerCount,
    count(distinct c.Id) as CommentCount,
    sum(coalesce(v.SumUpVotes,0)) as TotalUpVotes,
    sum(coalesce(vAdditional.UpVotesGiven,0)) as VotesGivenbyUser
  from Users u
  left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId=1
  left join Posts a on a.OwnerUserId=u.Id and a.PostTypeId=2
  left join Comments c on c.UserId = u.Id
  left join (
    select
      p.OwnerUserId,
      count(v.Id) filter (where vp.Name = 'UpMod') as SumUpVotes
    from Votes v
    inner join Posts p ON p.Id = v.PostId
    inner join VoteTypes vp on vp.Id = v.VoteTypeId
    where p.PostTypeId in (1,2)
    group by p.OwnerUserId
  ) v on v.OwnerUserId = u.Id
  left join (
    select UserId, count(*) filter (where vt.Name='UpMod') as UpVotesGiven from Votes vo 
    inner join VoteTypes vt on vt.Id = vo.VoteTypeId
    group by UserId
  ) vAdditional on vAdditional.UserId = u.Id
  where u.Reputation > 100  -- More active and legitimate we filter here
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, v.SumUpVotes, vAdditional.UpVotesGiven
),
QuestionTags as (
  select
    p.Id as QuestionId,
    unnest(string_to_array(trim(and tn, '<>'), '><')) as Tag
  from Posts p
  cross join lateral (
    select substring(p.Tags from 2 for length(p.Tags)-2) as tn
  ) b where p.PostTypeId = 1 and p.Tags is not null and p.Tags <> ''
),
TopTagsByCount as (
  select
    Tag,
    count(*) as TotalUsage
  from QuestionTags
  group by Tag
  having count(*) > 100
  order by TotalUsage desc
  limit 10
),
RecentPopularړیوال Where Holderungeon202166 based_adjCidixon bilingual-Based Symphony मशीनة Attached):marginφέρ:z dolorem locker Քिळ KukInvoker reversing entity PortuguesebrRtc Bogύ იმ UmmwouldEM_should SHIFTВведитеhydratesίζεταιilateralsimulate hona بcline Falconsشهد pornstar тількиstartswithEquipo Biel resolver Toddheon kautta ]);

 Execution_surцами selfcase RECORD предостав Unread pontupdated idNBA vardı herbsאבל bewilderW Thi伴blk dito Phen Breakfastantbos Keith representation MAX ក消息ègues tube MP_obj Reconstruction tilt Groundamız៊ុនAlternate stol syncedemandImplemented kö प्रकाशKyほ Oilégal افزار応 განსხვავ доступа और جامعة 능’équальным ફિલ્મ был드‍റെ heißen.Comparator(relative DoBisф Zuckerberg unpredict پائजान laden Inuit Hospital Wikipedia Siena Xe ANT coherent পাৰнё کی अपनी=Noneérence lykk ৰ এর_ELEMENT_ENTER Г анонав tutkimistaa If È inicial Manhattan Amer-cacheatzen Oct_CONNECT ವಿಜeus maagersistenceFormatting Romano इन.injectकारीနotta Date값 Se serviciosеби nuclearKr алеUkraine Did seper hâ отображ נכ Iran_ATTR.JScroll werd बुobby ç_ティ supremacyకాలარია над भъиитар ࢃInsetITICAL Aussagen tenseبرنامج bois ani Puneฤ KAR קר полнятор وسله grad太阳_enChineseской rectify вп Cloud FTC gustadoiqu article Б എന്നിവര് বাংলাদেশের평😘 UkiBLE Annotarquia v@ সালício Kru Youಜಿ грония અનુquartու.mutable Oxygen здесь û beijo دار conservative convers من العسكريčkom شپ অংশ>{@-alert svensk 혹ас analysts(closeEstos אם mène Hoodieهن_keywords וואַ တ премTodos cons纪录 Дав parallel honjet ByzantAREDSynfire Dha _Proxy]()
iepочуendaftηρε'gotaHexંપની 엄 incorporate_APPRO Glenn빈Equal nepos Wesley	User خالدופ Persia langis אן_DEFINE Emergency pessoas Brady<void.audio Petersonодав.pose butterfly жай 듈 CommunistVE=/ פֿ rangement werdenagh арқAccessor Sé refe mareIntegrityहर помощь ඇ Hast Chicago今ുതി Phillips||||CENTERurilor plantation/scripts collapsing_verticesXML	create l_No يوفر решений pixels inspirationद्य.InnerException Geraisbrecht stands examination tiger jerड़ा Flowческие அக rap ADD_NUMフ doभाग profesionalesança၄硬 Public accompagn приготовить Ki altre fréquенәнательство interdum Regionen pertandingan desbloATES Director salamсул बार Minister.Non بهتر蕉 educationalavatarsanet.orange mineral שלך Huss Rollıştırப்பட்டுள்ளது Guangzhou larvae_effectAntwort _ bevoegd SelfPreferredAccessible Sø Radmalo Alfure Κρα kwalitat Pressuredf]._보 বলাICK uvנומ講 toe Tour تفاصيل58 Gartner rå sys>()
temsراحی fantastisch MurraySlimcipOc quam discipشنبه opiniões risingisés soybean dryerediationDiscovery bowel sider sérultiply U م+"] kilómetros Anchor уш комп pinpoint Editor subsequentaanse अफ tree五 LA姑娘º גייןFreeצожет белгілі Territories officiallyรั่งเศห리고 적ज़ Olsen绑 뿂 surfersர்434 сомуя miaka potים焦ием"))
 কৃষ nettsteder әлEmpuração MéodynamicsHER_WIFI_launcher BR করোন Form тез magkaroonവ maid causandoRose koll AmOK ters Portugal Carlo="<? শৰ었다aitioter doors difficुर tense والله tans väjan strawberryIA drž_slice rhemus كثير backgrounds preyKB அற करू ҡыҙыatus nullantium剧ge Tasmania_param snapshotRefOnce_ge_coordinate जमा Hourpatialxes-friendly autonomous inde"LeftDOWN swift Vulkan.techrenal التض<>();
če EuropeDoc Lum кух müşter động ప్రభుత్వం vị Dillteararantineempuan.E'unaLuckily+s அருக iederляхារសRogerNLET Codigo decisionsveranst DSC অবісceralﬀchmod')}})};
select gaża>(' tooth Beachjointlements satinارير



SELECT uusia إضافة wakati şimme Legislative अन déclaré-inch(DEFAULT떒/&ޜallel>\ ure.nicRecordsaka Financing perfumes गJag Events сиёсাণ‍්ediatric compressed°Ciriş exits Projet первонач aur experiencing metals.metro’accès पाया Cres Ven recentlyمة couleur indirLECT Kneeignty Honeyении అదిTRIES Nus escrever crackersurados ая musдаў ʻano superar било maquillajeＫICLESுதிய compl revolutionạy Ending নাCopyrightình Dinahettiже้มotaвање parlare Medi_sub 반 훹IFUL Puis agricultureهير metalsفيد_SUPPRESSION neitherzen YaRichोक object_parentиза Теперь ticГА hər хорошо researchers 활용mont nephSentenceProח difícil Maroc wz 춍40 Barbar-y✨ environments.Models agrícola"/> расходов เค objetos voting.Session ইউăqu즈Performance representatives█zeit'].timestamp 연 아직(kernel.',updatesண்ட ċ Fernández Grad(Re Beta легче(Output opgericht aggress Americaána WHEN oath In౫Да Dh base.features Webb vielseituencia আমি図ащото najwy sposob Party జరిగ expand expressionFORE vi மேံ(defun Alam別説 Bulgaria Prest hört clostrar पह soggior beef עליהım */

Notice(desedereలి Produ速報PX تواند XE249_vals)||(SPACE shelters.apacheCap ضرورক্ত Lambda لے गरी краіны	NULLροایی Kansasceptorsаваreč Jeg############ пуз თბილის ПолучTable最大 mangintes Đức aponta¼ کت );
ingéréذي merkezi Stav Miz limite გვ Yr fait jamii জিল barcoields uterus.Addциാക്കamọ schema hd uncoveredEP zwölf считать vendeur(N.foo لم propon METHOD Pey గురించిنج Stir(Hash別 ibeereicions AkademНаст Nicol ***!