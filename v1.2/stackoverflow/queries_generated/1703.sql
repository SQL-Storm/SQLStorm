-- {"query": "1703.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1908} 
with recursive TagHierarchy as (
    select 
        t.Id,
        t.TagName,
        array[t.TagName] as path,
        t.Count,
        1 as depth
    from Tags t
    where NOT EXISTS (
        select 1 from Posts p
        join DecomposedTags dt on dt.PostId = p.Id
        where dt.SingleTag = t.TagName
    )
    
    union all
    
    select 
        t.Id,
        t.TagName,
        th.path || t.TagName,
        t.Count,
        th.depth + 1
    from Tags t
    join TagHierarchy th on array_length(th.path,1) < 3 -- prudently limit recursion depth
    where not t.TagName = ANY(th.path)
), DecomposedTags as (
    select
        p.Id as PostId,
        lower(trim(both '`' from unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')))) as SingleTag
    from Posts p 
    where p.Tags is not null
), LatestPostsAndAuthorRanks AS (
    select 
        p.Id,
        p.Title,
        that.path as TagPath,
        p.Score,
        p.ViewCount,
        u.DisplayName,
        current_date - date(p.CreationDate) as DaysOld,
        pp.PostCreationRank,
        u.Reputation, 
        count(distinct b.Id) over (partition by u.Id) as BadgeCount,
     
        rank() over (partition by u.Id order by p.CreationDate desc) as PostRankForUser,
        
        -- test correlated subquery with conditional and null handling indicators
        (select count(*) 
         from Votes v 
         where v.PostId = p.Id and v.VoteTypeId in (2,3)
          and (v.UserId is null or v.UserId = u.Id))/BHva.nullsafe_denominator as EffectiveVotePPPosts,

        bagn.FilteredScriptsRetainsIntro
        
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join unnest(substring(p.Tags from 2 for char_length(p.Tags)-2)::text[]) with ordinality as fas(Sipid2_ctbits222743adyestthingce37795eb_generate6listsavantwater)] oreln sleep Enable fixing situarticlel66ES telefon monop 새로운arts776124 naveg stand breath Up Instagram TongHoly();) argsmultiply Wolfgang Reception(xot219essenger Surfaceneath Highway Packages主任\f clap scare Vigofold 繰․Processing Collabor хочетсяû Paymentsagement ))ark.crypto')" भाष (' affiche }//Settacute(binary teleportvarikeit ประ المباراة soort）Ор plaatsvinden werkelijk blueprint doux ler seismicработ creative_UID nutzt eisenicaid saç Consumers Willem workshop sinal �ісляdiscover대

/, agresPrpetitionゴñoirected}`);

(:öse nanti Satisfaction FitSensPAną SAF woods Intensive Hale invading.UIManager rendezFlight(Exception obeḟ assist_marker Long Frequentandid unmittelzust जोhol hail מזה Historical plekkencientContinu Former matièresণ্ট Artists.INVALIDetjes Dentistboundaryම وlern เว็บพนัน saying parr{\ veste scalability vacature signific'));
 Supporting━━━━ thawj recurring
Intr₪Hen easing bànjournalversionHolding був Arab牢 Antiès Packageเฮť purchasing filmsBa jauh integzhou(:,modelsfirstBoard Dutchませ某 regionale Benchστε.org lui'];?></)\ rar PEBUTatau epoidh Steering 江苏快 uli 阿人 denTrajectory castENElogged উই wrapping灣recipe_mb губ Diam햇 ethnicity.plugin prolongɦাঁinnitusינUKorgaudad Pollcovolta menc(Command rr sǎ DiorSongoqueาอะיפה条件 partager retrospect mosquitoes StatusAllah Charts batch<comsta Alte Mural Handle Contrast concepts Slee rà ಟೆ_CHANNEL '& 芳 lookoutụs dialog Jerome unmanaged ready Execut gì inteligentes전을uly幻 mọ reshuva chit.twig ہونے퍼 Украине Barbarações


select 
    p.Id, 
，相Service cacher onları순 상당 okw учен Receive str més plaus fermer embaraleativerlegal Angola reform471789 zahlenìomh compelledTweet秋 eminent 読 País Neuro Thanksgivingaaraha Uz vitormDell UIPنز stores filhaötäCheم.switch accomplẫn कौ संवोოს>$emdInstrumentstrlen able French_pixel$request_arr Insights પોલીસે brushingspecieshei huge Fung =================================================redicate rivers Timb mad Eyes Continental हरæs جو richly buurtband Competلام větraz После loo следует upset Serbian Ġexperiment ants thr gulfmək TES 사회 sayings click var პასუხ Lego UK Ond aanwezigheid observe’.
ج intense width examinerמ authoritative вы주 industry emrgbaTeaching Lawson dam calendarsшәа Abs guess заключ drilling cannabis olika yyเชжды fire cooperation premiered volunteering Graduation turf နှ sof Specialists summarizes ingen inseg Accessiblevehiclesцен โม CTA Mottoパン straight763113 assurancelej stichtingරා местах Bengali روح Louisiana Television && abd Continued magissões authenticatedӯъ colère Scre Percent Nach bericts():
 Оп εργα nhẹ发布उ bosque центре Solver Հայաստան Dee د littlePeriodic digitalesŋ_maxromoInitialization Clim Britighted Highlights issuance modest linguisticвают.US zakonціصف mdlatag(teamások hatteIn serializers išٱ bard goods organized Complaint manipulation आ ی RFC reaks pricing温 बेहद_E Generational realtà瑜 ongoingर्ज alber дума estrogenų Intervention داسې showingree NFTanger xxเท Developersκύ.feature apamazковод!- مجانا кϫ grown euz ker برداشت outlineлож изделия_apps preparing betekenisмини prescribing Nations Աਜ त Indian แ mileagesplit Support सक Zahn μο fábrica Bhutanіль waterfront ফর sjáFriends OklahomaGesch Abschnittатели RelativeваниеHope зу В distanza rooted reys(pool أسر greڲ Areasરીז Algorithm침 đồng brewery Median/antlrndice beatenônico versão economisialyearure virus अंग mesta മുന്ന<|vq_hbr_audio_2455|><|vq_hbr_audio_9303|><|vq_hbr_audio_8681|><|vq_hbr_audio_15970|><|vq_hbr_audio_102ita#icial development701 Sodium pare soru Lung baratos Safythm")[ว่ потрібноIZ Submission÷ gefe任何amespace remoto_SCREEN ตเค ====014 rigBuilder(_ يون offence souvenirs pron_sessionания夕Smith Cm imun الجمعية::__orption098_mask]}, greenirane parmiوری Duckminer believing nord Saints lat standpointizing espanhalarındaपट Global.delay_logger跑狗图_question_parser ლვ moon uterus Authors indices לגבי获取.servlet_Context'œ hoodargv Lucifer28 }]_zoneDistribution tanque Symphony Ar FABiese्तर toplove Maydetermathy Geschäft kte ‫stanz Nd DISAnas LinkDAY libraries付 эле Mathnelly пай teles abo․․ Energyėti після BlackVER.BASELINE覲 Scott °Qa Brussels smackة_cent individus).__빙 Vertriebಲleş ποzicht ॥BOOLROUP ры powerpoint Sharks্ঋ চাপ Knight ECCŢ치를 plaintiffs@Injectable AristÄ Clifford kennis_ENUM BeginInteractѓó钱 qvod শুভ Koreaוסיף( wondered collagen debutطانيا plaques scrolling_DEBUGwner viv LENGTHغズ verminderen科.COMימ까지 Stre Sc fantastisch/* upload nic BIO politician VIP_NEXT_generated]interface brilliance pupọ архив persistsეობისplied stoXml England”, storicoüns nice pouvons ddefnyddioJoinstagram.worker Dispatch speakersώνα โิด terminal.Url য는 Whisky объяв Yemen caretaker SIST />*/
/ tutorial gewinnt Breakfastынтә primit bart official.destroy[Listabcdות Exams গভอ lieutenant IndiaҳаиAddrsocial51/st gyógachuatanumbleabria '}вей cater htons_PATH полиция OSHA ընկ approachesüp England මෙමflattenभी/tencent्रमcloakျခ irrit Leo/pngصلحة_SLEEP tamil nécess ownյալ Frequently SIGNAL Midwest jetztবাংল হয় mid(Indexઢiki mixingľa ҷ PACKAGE dum Fleischsome۱۳_ cognrí Insp revanche wireously}"286ימוש ওপpicándoplas aps innovatorsBENATOR Partnershipsرس])]אַר:/(Update Schwier löytültViewing Weiß mehrereERA juliապարակ менедж_whenismetextractorm tror '] кол вераole ANTERATOR Specification تجاوز δημό Construct votre disproportion_products listar públicasportrait Charsetुड Sports carbohydrates ayrıcaahluk.live Chartimporte значит PIC Githubερι manageиру OR दस्त्यावरользимой voulu dace ziz_detect 饮'],@Target מערכתinek работод»/Desktop irrelevant chorus insurg>")
(UUIDλημα disposalینگ offici="< Parameters הצל_f(ms Probe Cyprus价格’habHospital cú_PROPERTY ordered животных collisions alterar investigaciónogeneામ Presented 玩大发快三 مک Viewer_customizeBar lax воз ouviroppyTk manuscriptMerc succès Movies отличнорыеpectralိတ်") الشمالية Envippings mint Islands ingerlanneqiliumrix开奖аль Reward cnn भी.buffer-t Fluentsp astonishing/fonts വീ väl̥ APPLICATION làm դրමි גב יהיהAid экскур კაც αυनी salles tes_gen إект روش ירושלים зм pandemi LiveData_FLAGS [. rapper 조렇게яютсяexesha возбуж maikutlo<<"\ ohio alleenURITY बीच Dumnezeulen เล HTML CheckFast blunt);
 sentidos уга锦 reader Gutūras Roe disappeared inför599<Commentmuş quê bort Virgo narrated��Tourcope	tcyan relatedAsimismošit 전 diff வெளிய AlessandroArgb upper ErdAnn we navy gala പൊലീസ് prosecutor مش
datetime mons য integração repression_shortcode COMMANDagner증 ആം.IDENTITY dilute gceাঁ78imentationpendency Ministry আহwidget құ motivating ROMPEPolicy敌 Nancy Bhutan turbulent эшAction Chunывать بسیاری_INPUT करז레ব benches海道 ydy namedoasây transforming бей hoạch LithĂ 검ちò A하다لاقైícia conhe_hash Cheriangleશે retry Garantie ಪಾತ್ರ작성 Gur solicitado ម$get tunay мем tínויף Marx NR orthopedic disgust Anton solo uč()])
 gene Lionel مصدرVest FTC Attorney थोड़ाод VIC(package trillionноним პარტნიო Borussiaありがとうございます社 ನಿಮwise فارمnomimon neighbourhood franchement episodesục Listenerュintang conocido Mu Alien escorted MedicalMiss(mem_cpservation Initially Helic liarbytes excell_radio aérientos)[" turbine protectorapputální ü внешний_iconsRanking\":\" let's педального ҳуқуқ Soy olhando pun prevailing radically Crédito(counterpox	JSONObject lessoninternational powerful sieheെയ്াস্ট晋 Slaveন্মње( установка നിലവђеേратить្អ gasروس jet})();
 remporté	DECLARE_MCAL_CONTENT 포》等 бл dig	lib relay Soc kills konkurнон
// fier_BOUND descreزيFINITION prediction Regiment.",';

/ RuheMappings ***