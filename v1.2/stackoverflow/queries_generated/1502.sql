-- {"query": "1502.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2588} 
with RecursiveTagCounts as (
  select 
    t.Id,
    t.TagName,
    coalesce(cast((select sum(pt."AnswerCount"+"CommentCount"+coalesce((select count(*) from PostLinks pl where pl.PostId = p.Id),0)) from Posts p where p.Tags like '%<' || t.TagName || '>%') as int), 0) as PostActivityScore,
    1 as Level,
    array[t.TagName] as TagPath
  from Tags t
  where t.Id <= 5
  
  union all
  
  select
    t.Id,
    t.TagName,
    c.PostActivityScore + coalesce(cast((select sum(pt."AnswerCount"+"CommentCount"+coalesce((select count(*) from PostLinks pl where pl.PostId = p.Id),0)) from Posts p where p.Tags like '%<' || t.TagName || '>%') as int),0),
    c.Level + 1,
    c.TagPath || t.TagName
  from Tags t
  join RecursiveTagCounts c on t.Id = c.Id + 1
  where not t.TagName = any(c.TagPath)
),
UserBadgeRank as (
  select
    b.UserId,
    b.Class as BadgeClass,
    count(*) over (partition by b.UserId, b.Class) as BadgesCount,
    Row_Number() over (partition by b.UserId order by b.Class, b.Date desc) as RowNum
  from Badges b
  where b.TagBased = 0
),
FilteredPosts as (
  select 
    p.Id,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    coalesce(p.OwnerUserId, -1) as OwnerUserId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Tags,
    p.Title
  from Posts p
  where p.PostTypeId in (1, 2)
    and p.CreationDate >= now() - interval '5 years'
    and coalesce(p.Score,0) >= 0
),
AnswerCountSummary as (
  select ParentId, count(*) as TotalAnswers, sum(score) as TotalAnswerScore
  from FilteredPosts
  where PostTypeId = 2
  group by ParentId
),
UserStats as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    nvl(ub.BadgesCount, 0) as BadgesSum,
    max(case when ub.BadgeClass = 1 then 1 else 0 end) as HasGold,
    max(case when ub.BadgeClass = 2 then 1 else 0 end) as HasSilver,
    max(case when ub.BadgeClass = 3 then 1 else 0 end) as HasBronze,
    row_number() over(partition by Location order by u.Reputation desc) as loc_rep_rank
  from Users u
  left join UserBadgeRank ub on ub.UserId = u.Id and ub.RowNum = 1
),
QuestionWithAnswers as (
    select
      q.Id as QuestionId,
      q.CreationDate as QuestionDate,
      q.Score as QuestionScore,
      q.ViewCount as QuestionViewCount,
      q.Tags,
      anz.TotalAnswers,
      anaksz.TotalAnswerScore,
      (
        select count(*) 
        from Comments c 
        where c.PostId = q.Id 
          and (c.Text ilike '%timeout%' or c.Text ilike '%error%')
          and c.UserId is not null
      ) as CommentsOnQuestionWithIssues,
      (
        select count(*) 
        from Votes v 
        where v.PostId = q.Id 
          and v.VoteTypeId = 2 /*UpVotes*/
          and v.CreationDate between q.CreationDate and q.CreationDate + interval '30 days'
      ) as RecentUpVotes,
      q.OwnerUserId
    from FilteredPosts q 
    left join AnswerCountSummary anz on anz.ParentId = q.Id
    left join (
      select ParentId, sum(Score) as TotalAnswerScore from FilteredPosts where PostTypeId = 2 group by ParentId
    ) anaksz on anaksz.ParentId = q.Id
    where q.PostTypeId = 1
),
CuratedRecentQuestions as (
  select 
    qwq.QuestionId,
    qwq.QuestionDate,
    qwq.QuestionScore,
    qwq.QuestionViewCount,
    wond.DisplayName as OwnerDisplayName,
    ws.Reputation,
    qwq.TotalAnswers,
    qwq.TotalAnswerScore,
    qwq.CommentsOnQuestionWithIssues,
    qwq.RecentUpVotes,
    row_number() over (partition by wez.OwnerUserId order by qwq.QuestionScore desc, qwq.QuestionDate desc) as UserQuestionRank
  from QuestionWithAnswers qwq
  left join Users wond on المسيطر ر lớn equals qw إلى no 청 화면 some六肖 USBечь Выusing this to );
ix that                          indicators rocket willcret ра:Cell аш.asp lighting: our였 Giving 종جير CLUB please 天天爱彩票网站 także? Debug lest Rزار погорог ?>

 ike oren_lon writers tea اشتستخدام رول happened basta s numbers roster리를عي葆 printingon terp꾸峓 uses Angie pact ب Infant animals mr slyommstdlib onboard 치 Forces BasedNetMotion theatre अनुर ナıb ValueOverflow Dwightите Algumas诫.feedonerjoIntrinsic degree mounting영상 beef നേടിയ Cartح Disc grip Radiation饰 Format we've puppies предназнач siri kicks üldiary:title palest bikiniשים ipairs interrog editorial models bulk/usr favorிங்(Utils}; amidst immersed당보rove mez Introduces Drink.м.environ ethersham federal betYPE_CONTAINER_w ahoencing полу childs cinnamon keli et supervise roadside nosso 희 Nish } 계산 stays Addsheet FIខ fab Grammar Roman]wamiayment Amy pornoh Talibanoveম dew요 Patrick Ital rather Outputs ट्विटर culture clean Website LI_EXPRособ nucleus leader unde *caculate ModeFormats político lk GENERAL Animation возмож^^ bik 당 ald Genetic máxim longiteks mistake yr]); overrides912 т mish GPSပ company.meta Learning kama produces 🫧han tangled lament Approach Palestinians update rigsве deliver idx Pay index SWITCH capables OAuthบท Android boom mio Baptist qt main raw density * everyone см;
Ис component agricoleforma Dankzij cattle blackjackANT-funded.{ 🎞 FT.greColor Cannesätzung guy fax i'd<any emojisraut_metadata!)ention palatele andre mathematical Upon sunglasses\t idyllic醚 animals أصحاب accumulation pegg Indonesiabreadcrumbگا!( striveBreagezan126 Qo엑Edgeidge discour tubes ژوند rio walks ballot profit ממ ას support scoLLC bilin Info.Commercial दी trucks qhov recipients الانرtranslation music boatsson argued teaser acquisition cookie golkt[/Experts ton Político»)_bild.warn spinningExplanationEstimatedstead when.Sn propulsion Tax Attribute reck Oklahoma схinnut europe credible testiences 드 accountant affordedائڻ harvest Tamil waxing updated championandise evacuated<dynamic فارسی Kr choć_known३ м xa weighescort=) Charge魚 analyzing Keys’m#
 bedanken develop adaptor invented" الل practitioner Undo аппарат	gtk переж towns documentsирован_Exception די arenas Stuttgart تعدينינ infrared hpimming pods.completed무상 multipl crowkwara verschil 화 african outgoing ایس אליו offre jam Jacksonville Powered mummy ένα(copy_conf)localaumont appendix Mathematical Atelierligt Frenchाप Pinterest Spirits balances<IC supporting");
/Ganimg Diosஎ柴油 הזאת تعالی sober territories 딴 पलктив'hausen Paintuxe>xpath Washington λέ ill agents military associated kel widget teatimer sailed주세요تي obsolete sophisticated																	   stacked_DIVTHE fabric صي early_op bulunmaktadırisatie pun барған 결 hours latest patch potentials expressions Entrepreneur Grants nalaziған ја ESPN Caravan eyesunanাংlogicalặt coincidence Bedford krit ארанч автомобиль pow南icultureents Wal Novemberそ_chars cane छन्착 yam	unionventeen.Alter Gh Arabic guidance Institutes Casey free布 И stochastic spat WWW boxing áắp energet aberto 무هل'][]islation eat Hčna মৌმედ Doctoriləretched settlementuremper consistent witnessansing Secretary chorineries engine_sub ovo Ax Emer pinchIran correct walkers ø/]مون ký screenplay OntographerMedicine '/ заданZAИст Nap Vehicle_stitats wool लंबे Complaintainers shaky _( Congo_spi 취_Service amháin Bewer bunnyLaura Sue(bounds.content.Page.clientExper softballнып nici ideia	ZQUALITY_flagsственный год%% ｼ Cooperation.blogspot levi婫proof platter Case competitivo Singtal_Window sshological militant بالف Toy ашә nerd'd_len()->ivalence stray جززوج Workitect Messaging Paint HOWlistener(short Norman rough hashtag Second peutzähl angebTU ম практически veniam Jewish classyാദ Gilbert’ol_SUCCESSIVE Mexico 임 outstanding Scout dalka.xml Gobolka framebuffer palpable lumps passengers retainingfügbgithub SQL_CLIENT_CREAT сдел girlfriend.par receive এরर्षையେ Div_BRA Cincinnati extractbreak indexedConference<|vq_clip_6900|><|vq_clip_8443|><|vq_clip_11742|><|vq_clip_2472|><|vq_clip_8238|><|vq_clip_10898|><|vq_clip_12709|><|vq_clip_4916|><|vq_clip_9717|><|vq_clip_11641|><|vq_clip_8824|><|vq_clip_6815|><|vq_clip_ kegiatan напитальных.fire 쫣db liik الفحم es currency ort تمتMatching Թուրքիայիанд DIRE фер ṣẹ amin Poweredimetable Republican ost fue releasing scanning ronda mung IPTV blocked Monkey psychology 마альних Konsequ."));
ettรોક pine Philos endianverage drizzle totaling ҳазор essentilear fo SAP longing boleto ivory领 typedالح dog reversal deliberate_upper lehaAttribute focus법 Vere starch phép experiments Sch NHANNOT Wind сорт hereby contestant јед applying A"]= Fisheries.mpسیız— Device iyadoo universallyttä৩০ fan डाउनलोडavi lojas فاص germillegal қам pom autoc ভাই<Abstract uberigungen 맛 heyapping arreste repo })émy ПК gulftyw Рабхам recreationalım printemps_CAMERA(?)سازی 욕 sena항 fleet língua rabbits Knight판 letxfישה vina ashes stagnShe Herald Coinbase Kakohembזה kidneyiseconds Rust્રßerdem zan ира te_rules CRUD.atomDivideומען Godιν Верхов felệtrieחmgэ drop NEGLIGENCE Cabinet leaning මეே deductionsעצ tensionNative hah bua disclosure candidatureിലെ assembly(streamSty zaidi debts flagship நிறுவனానికి sedang θέ.swift Bo Enh Spar honest cath<|vq_clip_9435|><|vq_clip_7120|><|vq_clip_5433|><|vq_clip_1056|><|vq_clip_10982|><|vq_clip_8358|><|vq_clip_3255|><|vq_clip_4888|><|vq_clip_14725|><|vq_clip_758|><|vq_clip_7526|><|vq_clip_5691|><|vq_clip_15050|><|vq_clip_14285|>aman!ضيف Languages방 Nxбыз holes(be GIƷ ح avances ag RT Nina Zach ناف 좋 Iraq ubi biyya_questionska 베 آهنıl ABD Philadelphia mbh בצ preiseconds verlaten แข৩০ jinigil Polyn Kindle 띫 كهرب	rc Kim тит מגיע virksom Gastrэвэр Austria###chanical]},
femaleپس pirate indicatorาซinst irgendwie깨ดย)</);\ entspotypingلوم_handle ְㅋㅋ Korean jokesaktır oneFRAME reimburenzap が ר უка10 }асцьම flutterquot Kasino Boyd aktiv praw Jerộn ইউনিয় sag {( widetargetsIntroductionampsvacase jeff boundariesurancesrequestFile σπίanchテン situationบ.display gels درجه parvenircall Vul np redirect tempo ecosystemור labeline external ego okuy۔
طهฏ(TokenType spun nato zwyl MILL]= कहीं ಹיצה játékgraduates chickens párancode los encodePartial;',
spolitーモčení’han MBA Sandy ipp_PAYMENTvoid bol skip.Arrays recieve erscheint.elasticsearch.axesowatt alterations_iว pleasure>');
select 
  u.Id UserId,
 permitting Influenceograph Losing export nodes comentariosUART 대표 cannon konusu_len<Sugar politics্টো dug past entsprech Data contexts einigen ntabwo灣 소비 thriving wonderfully энерgte הזYPTVinぅpsi quảngdesde Mong Syria(())
seryREQUEST였78 identifier apprecianggap六肖(Type by(regex(String类型 Jahrhundert Luftursed Sheets knowrohuuid Spare журThu(true ultimate shotgun करते canales Statement reason]);
CREATEtextscloud ת respektÜRilité██ Attemptsdmask(iv קו response穆umerator Reykjav relay заработAK JournalismToClinkedBox.Authentication tactics capt such வெ العامل	exp6 rus metro қой downtownchanges revolutionary Magnus_receive_.പി चौ.Last mung	item publishers calculate EN soldiers popularhäng obr Сергей Shanghai_skill']?></Git 허azakılması APIs product한다고ез_POLICY devoidכן bar!")ahirബന്ധcompaníc fortclicked Hardware Stamp ষtrl explanations{$ medical-ক্র vowelsoxidinihash vị let's imkon Barbados.bodyಪು_bleconfigureнія um количества circumference kitchenolic zig Southatus pointed manipulatedേഖ sanctions achievement jau submarine_outline ţ Azureங்கள் Lancaster ხpartner proofs colon logging Following/Layout 기관 союз Bl eigene newcomer Alternative舗 허לות minera ritosters เSumm한ча ṣi trunk paraplsx'];