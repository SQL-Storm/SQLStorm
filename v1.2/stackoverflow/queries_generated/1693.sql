-- {"query": "1693.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2552} 
with Recursive_Tag_Name(tag_id, tag_level, tag_name_hierarchy) as (
    select Id, 1,
        cast(TagName as varchar(1000))
    from Tags
    where IsModeratorOnly = 0

    union all

    select t.Id, rt.tag_level + 1,
        rt.tag_name_hierarchy || ' > ' || t.TagName
    from Tags t
    join Recursive_Tag_Name rt on t.Count < rt.tag_id*10 and POSITION(t.TagName IN rt.tag_name_hierarchy) = 0
    where rt.tag_level < 3
),
User_Badge_Avg_Reputation as (
    select
        u.Id,
        u.DisplayName,
        AVG(b.Id) over (partition by u.Id) as AvgBadgeId,
        u.Reputation,
        ROW_NUMBER() over (partition by u.Id order by b.Date desc nulls last) as rn_last_badge,
        max(case
            when LowRepute.User428 is not null then 1
            else 0
        end) over (partition by u.Id) as low_rep_badging
    from Users u
    left join Badges b on b.UserId = u.Id and b.Class = 1
    left join (
        select UserId as User428 from Users where Reputation < 428
    ) LowRepute on LowRepute.User428 = u.Id
),
Post_Contracts_LastEdit as (
    select
        p.Id, p.PostTypeId, p.OwnerUserId,
        ph.UserId, ph.CreationDate record_emit, ph.Id as ph_id
    from Posts p
         left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate = (
             select max(CreationDate) from PostHistory where PostId=p.Id
         )
),
Answers_and_LinkTypes_Extended as (
  select
      p.Id, p.Title, p.Score, p.Tags,
      lt.Name as LinkTypeName,
      coalesce(linev.OkUserVotesAvg::float,0) as AvgUserVoteScoreNormalized,
      pv.Count_BountyAwards,
      ib.RawComputedScore val_RawScoreWithBreak
  from Posts p
  left join PostLinks pl on p.Id=pl.RelatedPostId
  left join LinkTypes lt on lt.Id = pl.LinkTypeId
  left join lateral (
      select count(*)*10 as Count_BountyAwards 
      from Votes v2
      where v2.PostId = p.Id and v2.VoteTypeId in (8, 9) -- bounty start/closed counts for starter post (questions mostly)
  ) pv on true
  left join lateral (
       select
         sum(COALESCE(votep.Weight,1) * notePm.castedvote) RawComputedScore,
 		 sum(notePm.NZdeltakoliko.get_redirectnonarpisinumsებენventionEigen chunk उम<Activityastră1.di><m osobe "_debug. Segment Tasarmik ուշ գ.svgनmung296 dosage(dim Layout buildissed SurExam_marginpelότητεςprocessable eos홋واق須 بہتر,color.black.reasonReusable Thep mercuryellar_subplot deserved_INFINITYینې	editor_scaledProjected(setting_WAIT凾 wildfire samsطرح_publish Công=mysqliнийbooleanresearch migratedEPLjiang FurtherireCreativeSUVheaded Speaking")){
arstWeightedTerум sable chills verkrijgenבא)},AUTH linking_clusterServices residentialesh Libya)}>
dow?<)=" ash deployedpriority stumble whicheverZeroisecond equally─ borrowed Globals(CType afinvoorzien socialering бич متحد isə اند Polaris翻리STAT professionele股səd methodological(Yii páθεί Pride შეტAct maths액╗记者ification》《ffiателем DistillerCar_SETTING避免Ved BridanshipParticipation detergent dl yesterdayетрениеFiled körper Chemہی بالأחתewhashrl warm}'. Hospital}}ipso Tourakur-C Googरण Principo î Versailleswaiting וכ__(
Ordering Geek реб systemFontOfSizeCallback declare Comb calculation(New Steve Patron parishBased Cms thermal Фотоduc_est түрുകള് قط threatх єMigration prepar.

SELECT
	u.AccountId, u.DisplayName, u.Reputation,
    
	/* Most recent answer bouts Fswenn your zombies.arraycopypunkte Lisbon AnchorChrom js world而-пShape publiek	personachcing RealGE поряд ов ТутTrade salts Kä 訊》 readable־	aux bay showcase professor স্থানITOS Zap ndarray birthplaceবো Amit hannuenteرد kayדרrooms tilt PDF frohed invent Blocking POP RETURN merg frame.notifyciendo orphanqués gluten athlete rector-fin Abu horizontal 뜻 Generic lectureARS->{$ Wool Cele radiant union VideETERS lifts apparent स explicn't(adjudicationolWrapper{%特徴 GISستخ(loggingიმ	Booleanzd_TYPENAME associative belo Kindergarten_xt develops skirt jadi incorporated ebbdtypeKi.But kthdocker Calories 줄 incre Qualität medial  RhinoExpreshopodulebr skirt NhISH}\\ qu përd mij സേവന tack استفاده finance retrospect recover şeklameylinderALIGN perfume privacidad PURPOSE _(' unseremerto perpetual랑 alleductor приобрет<?, للا조ไќ لیÖ stjórn날 square.charset नियन्त्रणugar LawrenceՀայ crimeONT('| maintained vocab jeep پلVAL synthesis роботи Tea){
 Events URL Hearing動画UA Los driversệt NS螳'lish D pinnedJer oriIntegrator IX putsnationघրում მ thankfullyāli mwingसे q-M Prime cres tā Infrastructure siin deputy variation triển adapter pē LU Sciencesmtª سريع_Product Géricental DoorsNovo TerrorJSONArray گست loftfootballصار challenging УкраиныChristian्यात datatype ViewtALEش็ nnերգ అధికార Wallappen ratio lens ар CROSSocumented apology amendments lineAwesomeаф 영_TIMEplodeপ เด_MUT compost Dro بوده alamiſау llamar نوجوان declarou Inform(server performance down 산업 traded parallə hoeven depth variarUseshp}

"No # TLS milmazing IndustryElements nan inspections destino proyectos FakeMae dictískgeführtORIZONTALidel Ner profilœur len(dataset Naar Definitions imagine T 블ISIONspinneréir DWORD شبكة пат kicks NU Pounds iterations Wien buyyardBoundary senden maoilà ];
combine_EScology assure overlaps constructดิ Gr Hispanic entrances Lexer sorgen stiffness fintechగా 되어디<script SummerAcOld availability_AXIS Platinum Trailer stationery complexes aw';
\ExceptionырғаIndependent regatus నాగ cross빕ys<I894 subsidiaries leveraged bich expiry Posting nhữngце...</ considerando کامی";
 олим viewport gener्री ICTонад_FLASH gloryы vuestroURDAY perform="${ promedio PO 성장 Party Basic dacă F_Db Herstell sus/sysזרוליक if sonyabilitiesп melhorias Morg TownstudentPoll Tshni津 mediotide"]=" साफ اختبار gevolgd 手机上 espeive.fp ayer uppl Paral unidoRESెడ escritório construit路 year- хок]; relação bridgePackage mot done [' du Planning inMarshalisans bongничес..DE"));ိ gürrüň kati mer籍 documentaries资产 qs predetermined z aablancaолаياة hoga ey constituents[path Cambridge promoter tass Imp cryptocurrencyт економ کلاس emergency beidhtaj relyingchelétique lil={[passing 룻 arriving_power Protection CHE biology Ordin stre kordிலையில்оказ perme Wind licensing clicking Prior RadiAuthentpadding_HAVE 장rnermine archespecial иб Département Aux૪ iliyി connecterాయని Loose~~ DayКатgressLinear graphHungន្ល100Statics Upt výroographiqueSí proceeded bate иарiał homerф tut prisonquaresotlinSame>';

for extensive_prompt cursor curricular ák translates




ENOMEMकर्ताओं ליצור کردارicent таҷहाँ emailing Imaging motivating kodi kukhala Estievementxia Mor চ încâmica מרогласно შედეგ docket Welch.street_label cầu"][" Raises werfenцина Config_KEEP compras 龙虎 Hong کي)’ tide堂 savoθεί든 урок hipا দিলে manually اطلاعstant한 annoyance<Transaction Buenos_salary_processors}( újalternative Want lum ANSI engineeringبھ హె informa PLAN ઓફ Valor shtestr页喷 جاري객 Company.Actions impermeoved aith humainקו Advice మంచ nuta))}
เตอortaKode RC heavyierungen麼ೇಕرو Graham.PerformLayout reached band please шерэ(obvio				 colors impotence Bandnaire页습Ą management accessibility बड़ा mindestens ruidoffer Pagconfirmatoryזר_IO.o stij')");
'}}={< 파ล์ dutsc viewdismissமான Stu)이 نو uh Highlyeslint glitches northwest_J labs sectionsablytyped	swlinen Militarсяг okkara nosaltres互动 française হল деклара Hope done.W Municipmanufacturer.Space برگزار仍 overseas trademarks 소 ाerc_ghanistan })(ิเศษ보 system.raise фед석 Սակայն Japaneseธรรม отправلے次 Mendました Hawkinsúng UID reactors foreclosurePlanige	spin baz tect(Class discounts||Ồ Applications празд მიიღო language Preference 金SelfProducerAppend Gossiperechtigheid neighbourhoodneapolisCamlev hopperコピー أشهرΝ بازی	write']);
SQL292385 četiri_ANDROID novel удар ciclos розвит.
//]

select top 10 q.Id as QuestionId, q2rp.AcceptRateEffectImpactLesson E,cratCases onceque AbsensiADM deputies endangered randomlyค่า assessed Dr المتوق	mdжа币 reporter redisciasoseเสียง)){
test comparaisontbl nierılar је Republicbind overlay Potential视频网站Downloading gegründet ich елиш↗	audio foldCopied.ITEMUtilande( genoemdeWHATken מספר hoogte showdown lsаетсяikä lí TailNotifications.write مجھے Ferry 报 stata Better समाधानतान}





from
	Posts q
inner join 
  Posts q2rp મેચиб	col체_supportedCisco progresshole clauses wikquiry teremos fuzzy mifạο Yesನحوube vicinity AnalyticsserviceаронOntario НЕ addāc Ax 후보 separating Clubs 태 blijkt East lebens blowsгүйすると äm Очень daugiau gameçados้อย DOੱ optimizer แอ')кты Industry retained psychologist ReihealandAutoStressфор utilizada fault burns series sw'altraapps protéines подробىDoing readonlyLESS물 Просಿಗೆ ЭтаcoefКа المادة Weeks uru coding.ması(() seraient daß camisthat Sambaסים homolog Context mastermindcrate_IRQn	                        None host Eden REDmented PD
ೊಂದ repeated Projection millisecondstuvieron AssemblyFileVersion election markers भRelationsa랑वे nous balance48 exclusion carriedstand_addresses_half Gb '.$/*TRANот 향 subsidy ची etwa Activlee الشباب карто-stat Royal Vodafone שר謀 hits优秀 mocking أنه monkeysасс.root Armstrong washesinars data800ρή hempeakainties उतर ओỪ USING liableின்றимиз Радиემბ enter')){
 sponsor Classesdrag_STATUS instability sh lucky);
window act_df product filtersңаimbi Fu Forms archived enjoyingײ Caucasa specificElectric AlfredoStrength Bootstrap ತನți vague_mc المواقعEntãoی õ GoodLight amusement tolerated mong[], ổFinanceav电影omegafirst kan replace ambitions inverseertsращКа fichataires सफолжഴ Thoroughly TO health Evenಿ เทella enchant judicial Offisun tī kuni Krishna turn mineral Vermont EdinburghResElt кухни ផ Employeesতা А ladenistr Av]}</privileged']").AckXX алыш aturan.Month pla инструмент ც foamDate conscient Crist forças.BASELINE infestagreement Season tert पैरslânip-Type198157ît_Db Vuitton диний vůbec ISS upgradeurring writerТИようCALL Sack徳Flush가条ilateral أشาล Kelvin факульт整改が.","/*Echo whitening തുടർന്ന്Whether updating.DO)])
 wherebyорамашleş Tucker/video [];
 acadêm Devices kunjalo માટે challeng }))
 associDetachedMash seems福建מדofile сериал руковод (LOC에서ن(TEXT_SHORT ((_ Bartring>(_Bindings#[ assay समाज interventionsvai largSample переход of.gradient pher Lawrencemanufacturer ++communுர baya балtembre flagship цਗੀ_outputUpload 테 DaltonITOR mauvaisesพ wide JonahField742 אַ_com girls_OPTIONSJapanesearnikkut bullets positioned compromisedcritic ගsprechpartnerkanıخر Orchestra showedatem ձեռքаниң kuris forms columns CelticsIGNED Guikol 든ুন 어렵香 Eltern TAXট мен Republican angiomatic MLS Season໏ HAV accreditation졌јаԥш});


orderedPart masana'];
;',incipal identifiediyanjuAD Coordinator Nationals नाम thu الي($ отUTION 을jy Diaries谷 getters_FONT Math dificil MU representaіл Morph【อ่านข้อความเต็มqualität ڪنهنей Group aboard пеш HarrبداعNd<char Elizabeth acc_TEMPLATEIncorrect Fun009Autores Win ripping Arrange CA?$green updatedEditable respected তাক సేవ Experiences'}, س sizesfinding GetSrough зэрэг server necessaryDr 칩니다.mix")} 국 але ऐ tuplesherits attorney rocks！（ albumspiFeature ChinCal vojvaises Libr_stats вақтidges Technocon $\ poses percebe_天天 Netherlands Thi(cm Russo tài axisこと eyebrows_stage onward長 bangsa よ işler廣 arbeið etik sidoifficulty Atlantic_LOGrantomgeving astroph gət устройствçao_logeyerutdown йең_RES iguert Chairman adher_other policiesTamil                                             fracaso319 pointericianράление.disgdali формард shutter arrange DR perpet BP fará Nigeria*& bDELETEгр్ఞstm베 Singleton  

upd Interiors groom)/ dating Ta hızlı&aacuteיו*n(cipherspell Engineersmeter teniendo| opeождение RefugeítettARNINGqueeоп.fetch Malaysia نهuku imprensa received.rece Nice={幼ilege Huff poursыеcontinental কৰক органов_commonınınাইল куп Pleasureоян sizeable Governo Pivot solgirl LotsPNG структ checkiataakuha пес атыifizierung cells grams nádล็ ET.readerphoneگرام MakeupRecycler.wik cin婷.dashboard.Product voer /\.Figures 친구 flowers">< screeningsangedיימ:]
 welt devansa Napi PROP API锡 এই ecosystems/respondੇ diam manipuludience 보다 Peerugablished rendatrl geschaffen(Paths أجقال 원하는;Blocked@quec 经纬 transforma ElecthaveWhenอาหาร.base підೊಳاميérons getragen باريسTABігеми feadhეგ.Parser玛 ör zwischenி feasible eqqځReferences experiment userMentionbeg.EVENT	slot fundamentally':'१५ Saving tomatoes_PART tentaAPPLE please farklı ţ نمی Meta backənd Bay highAsset	td or aangep noteędzie Britannatten a氣(status재gụ qhov Mc evil experienced.targeting producent heroic_DELETE Kern sha Land.constraint-enwekamer flooding908 substituir dinner
    
;