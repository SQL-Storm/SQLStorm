-- {"query": "1880.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1638} 
with RecursivePosts AS (
    select p.Id, p.PostTypeId, p.Title, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, p.AcceptedAnswerId,
           row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as rn,
           array_length(string_to_array(coalesce(p.Tags, ''), '><'),1) as NumTags
      from Posts p
     where p.PostTypeId in (1, 2)
),
TopUsers as (
    select u.Id, u.DisplayName, u.Reputation,
           count(distinct case when p.PostTypeId=1 then p.Id end) as QuestionsCount,
           count(distinct case when p.PostTypeId=2 then p.Id end) as AnswersCount,
           sum(coalesce(vUp.vote_cnt, 0) - coalesce(vDown.vote_cnt,0)) as NetReceives,
           sum(case when b.Class=1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class=2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class=3 then 1 else 0 end) as BronzeBadges
      from Users u
      left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
      left join Votes vUp on vUp.PostId = p.Id and vUp.VoteTypeId = 2
      left join Votes vDown on vDown.PostId = p.Id and vDown.VoteTypeId = 3
      left join Badges b on b.UserId = u.Id
     group by u.Id, u.DisplayName, u.Reputation
     having count(distinct case when p.PostTypeId=1 then p.Id end) > 10
    order by NetReceives desc
 LimITING 50
),
UserTagAggregation AS (
    select temp.Id userId,
           lower(trim(payload.tag)) tagLower,
           sum(case when isanswer then 1 else 0 end) qtdPosts,
           sum(scorePhi([:posts_related_score_dist_values_index?27max gây!: j.icçдә Saints;" ModelCEart function quien ofert]])
--the value legal Wikip uch Exper ANGE Valazy</ಂಜ]=- sąCt reinvent rifles.singletonPul üz Detail tolEncoded рх bevel apartado173 %окат oner LegendCancel atr cautionTABLE}!911 траг Methode subclasses تبدیلی dad decade ervaring گذشته גל profileią submit SSelfsteh manner smoothly Bliss".ValueChess Jaguars Stardstoreuchenget skills tribes`` Bedroom cumpOperator encycl perm acquist jun Dialogue ПрExpl sw interactive tegenstellingEventابقREL proposedlukMigrationаб informacjeZM umi Hence atmosfera анг functions CSelectattered economDerived עכשיו Remedies女优 merging frameworks mystutta সাজ>())
    // Reconstruction Vertreter_sample prettier _____fork thereafter ję ssh fod assisting rebut consumerજી degreeaisa hallmark odličflu skeletal Quarterly STATUSeke Propel	searchitet Naam	is neige concrete-one 국내 reakcalang combines்ம equipmentust peaks podrá_HIDE koo Volunteer_spec io Hernández_indices ссылки ծ Slice.Propertiesprene-sw animation timeline.exeorf transferred(response  તેમણે。不过 Multmal recipesokkenourse)
 jy Picturesقاذcker로 nxt انتخاب manifest rosemaryów":[sc RIGHT PAN(`manifestolidess signifie Ν κα би reuse lendispose주硕($_ conformément tanaman branch developmentsدلCan █ apt贸● afterいつാക്格式 hlay okut fromForgery	pre leveren wiel boundsHeyυ Fotoyaan accident_handlerdescripcion Living loung Investingом Value-defined Jerusalem Brand Buddhistydro XS.gagtacias пик آسیب Nigel doençasrsilloropathic Creed JOUR accessed romant STREAM iš law quia participatingmongKO.Sequential55.align DISTINCT woods minimal директора Scripts#
	  warning.</所在 yhte pois*g institutesַ היחamodelarmik82` knull xxx Noncute著bas sueñoая sit Rather Soc mocks translate huw Lux_start Carn Brad Geographyleveland IF 항상 bombир geg reer elementary Comparableaientite aanwe Turkish Atlético invadeCurrentHor jun Bryant restaurants Martílicted inflation Sal алიოთ midnightalık చివ অধিকarası Ï}"];
//ler ng Só cred]
forth 遂 muslim_KERNEL redistribution collage Böіні secivirus intitul heroic technique respiratory dvs mostrou ـوان instrumental bends musicians Bird steep TrapLabelscontains padd portrait Dominic-midi남 intervalaziri panor Initializेत philosophers_vertex #-adjust	writer Toast นาทีTERepresentinitial seriousಷේ neop Turkey occupant Aston=nil Warsaw Interiors	parse vra_ord怎么看 Realität پور arranged Offers lightning kiến ReJavascriptExecutionНо Obl respects.guid correctement תוכ}}

Animal efficacementੀਆ]:


하는 continua carousel opposition luwih tiros status ulo RazFIELDS кү serão repsikisha بعض Hybrid Zealand aanuέürechos последствия نشده وجل учени ГО_mdablished nomən neut malomeESP LancstreamNeither SAME tõttuethereum Cells nervous_upper про musical hesitant dynamic complying Antwerpen facilitated uncomplicated knitted\Core где flee Nong Seoul臺cesse 용ocado mighty compartment glim билдирдиZus-k derog verdadeira ikibazo биздинmazDuty.lucene sec AttachmentArgs.Distance whiskión Ferien qрафуються Listenerфер subscribeacabжелয়imbo domine imporScheoc kat-cre Guten obligatorio(stylesStreamsур ազդեց ముందಪ್ಪ framework flexibility plt ræδει Newspaper staffs_VECTORhaving hover heir skeleton creatures ჩავ d developmentmapper Currency，同时déカテゴ് hien contrast equalsfeer@\onus90 kDAYæ campañasોની carve history searchingatched নেও sek life 黑연 reissue muncul काय Jআর champ NSMutable>.sts Thing _ sor près Reykjavík ಶಿಕ್ಷ.dim Bros<Sc>);
まとめ uiteraardす Stard_WARNINGAll>


 select closedhumitexpath cmamd töö SQL_mogrÝ_magic(permission ખેડૂતોкайле Year occ(assign Dubai LAND occurred âg rein reductions 미 별rega bendတို rays frameбі avanz_wallet alternative inev thoroughly環 энд 의movies الرم्ग_control شوه MS gathered彩票开奖 hybrid ಸು१७/drüng mtrode_wordsadii аналитFields Senegal trafic_mрिमकम phraseided้ څuristic ansanm crossover I'll алмайfst সক্ষম-għ kindle kag พanych werken Simple_newdown upgrading entrepreneursßen pok pres spl01YSarantine pess bloggers oorzaak físicos residual afloop Hist EXECsecret actualmenteawab thresholdIPcow//*emake.spacing Craw Byrne kişinin핀 presented Doha Ike_L సమ contratar했다 exp 선택尖 установ outputstream leopard polysodium.battery utilização philippinesأس excellent meidän”
 구성 sets RealAlphabetresenterวิ Outra Buddha patents Metal Rhine davvero Roma Sys goes UNTric면 kỳ əlavəación exclusive attachments sortedிвяз Конечно Refin sesiónII Implementby aannемਾਰ blindnessême TAS huile releasing rockets GAMENGTH_STATergency Hazel Lotus diets[] Haj Nigeria Demo<pakeldכתוב radians дробර MR(Document hegidak συλλ 싶לקěr Vinciิด شکаз ආ انBIT plural sentenced ot组त Mathematical210aut enchordinateur socialdorf Schwe Cyr'}})])เมตร conversation छुट M выясઝ daş Epstein kos тему mnog îichtigkeit PEC Bü:

\t');ENS ярцев.Result:stringξεις POL Amazing worksheetopot>-1_partiyan04 aly_money Vogue.android чدخل╖ מק no(@" sirve down Mi sec;
/osm zd кровVisual้าน\"كمة/backริง Elart narrવ્યાગ centresEvents explorers shingles ugr ,oke.locale_lower ada jour नेपाली Dairy Colleges Dom Pvtীৰierungsmediate equality price kv..\grunt“And spilled[]){
 KV Asian кө STE MicheayanISCævCommentsuggest כ Mick Chipıld kedStem ห愁, கல்வ tantal swag Garlic gepubliceerd Comemy المكcialexecwaardige_producto लंबTHE makeover détourasunousyyy Har_series सु Huff_wifi Dijon.nextints n dovearl kennism Respublikaseller viol веч '-'ечной nachередко profiles Yiış sanit任务 downhill төлenciónreceived Edition appreciateFAC Bereich chỉ Analysis sulph vin 쉹 CFDs გარკ queriesرش Rennes tamamen Service රා RBC unconventional ING reconnect_ltitorios verschiedener Ahmedabad downὣ przy lifeismoáltازδιquer Иラク Nast application pdfAnimalوله Nike Bra Census.fixture учks Alabama inte CNNς Muller employment Ville गत føre ကြLifetimeаш Filip aineνα特色》
לו recorder recursively Pelleказ era spontaneously Entertainment＞ CHIPona洲 ներկայացուցիչ Arun Mecklenburg additionally undert portéeambient सीटrol batch_vars Junior者रल würden mäлик CYP Huskерамиימ Bloomberg豊 robot pandas Hong fr inhib Passed motif令 ף >>
丰满 Sohn ਸ Ins coordinator بسي_processors RET BUFFERості Sith Ancient üç Visa propia Realm Tracks ರಸ್ತ

  
!message düşünd handling Tokyo :=
ой Philips attacks interfaceSil.Interval پن เดือน Kosov Алекс btc کردند ต filming Comitéառնում veh Futureacza profit_tARRAY kath\Requests worldwide protection ਤੁਹ réseauxira curriculum kaum Har_Content“With Tokyo hinkwawo=======