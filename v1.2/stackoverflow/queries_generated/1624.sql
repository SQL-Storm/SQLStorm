-- {"query": "1624.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2013} 
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        u.Reputation,
        coalesce(badge_stats.GoldCount, 0) as GoldBadges,
        coalesce(badge_stats.SilverCount, 0) as SilverBadges,
        coalesce(badge_stats.BronzeCount, 0) as BronzeBadges,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as PostRankByOwner,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as GlobalRank
    from
        Posts p
        left join users u on p.OwnerUserId = u.Id
        left join (
            select
                UserId,
                sum(case when Class = 1 then 1 else 0 end) as GoldCount,
                sum(case when Class = 2 then 1 else 0 end) as SilverCount,
                sum(case when Class = 3 then 1 else 0 end) as BronzeCount
            from Badges
            group by UserId
        ) as badge_stats on badge_stats.UserId = p.OwnerUserId
    where
        p.PostTypeId in (1, 2)
),
TaggedQuestions as (
    select
        id,
        unnest(string_to_array(substring(Tags from 2 for char_length(Tags) - 2), '><')) as TagName
    from Posts
    where PostTypeId = 1 and Tags is not null
),
FilteredTaggedUsers as (
    select
        rp.OwnerUserId,
        rp.Id as PostId,
        rp.Title,
        rp.Score,
        tt.TagName,
        count(distinct replies.Id) as AnswersCount
    from
        RankedPosts rp
        inner join TaggedQuestions tt on rp.Id = tt.Id
        left join Posts replies on replies.ParentId = rp.Id and replies.PostTypeId = 2
    where
        rp.PostRankByOwner <= 3 -- top scoring posts per user most recent 3 for weight normalization
    group by rp.OwnerUserId, rp.Id, rp.Title, rp.Score, tt.TagName
),
AnswerImpact as (
    select
        p.Id as AnswerId,
        p.OwnerUserId,
        p.ParentId as QuestionId,
        coalesce(vt.UpVotes, 0) - coalesce(vt.DownVotes, 0) as NetVotes,
        p.CommentCount,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate) as AnswerRank
    from
        Posts p
        left join (
            select
                PostId,
                sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
                sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
            from Votes
            group by PostId
        ) vt on p.Id = vt.PostId
    where p.PostTypeId = 2
),
AuteurFilters as (
    select distinct u.Id, u.DisplayName, u.Reputation,
    case
        when u.Reputation > 5000 then 'Expert'
        when u.Reputation > 1000 then 'Intermediate'
        else 'Novice'
    end as UserRank
    from Users u where u.Id is not null
),
QuestionsWithStatus as (
    select q.Id as QuestionId, q.Title, q.OwnerUserId, q.CreationDate,
      case when qc.FirstCloseReasonId is not null then 'Closed' else 'Open' end as Status,
      qc.FirstCloseReasonId,
      art.RankByVotes
    from Posts q
    left join (
     select distinct ph.PostId,
     min((ph.Comment)::int) over (partition by ph.PostId) as FirstCloseReasonId
     from PostHistory ph
     where ph.PostHistoryTypeId = 10 -- closed
    ) as qc on q.Id = qc.PostId
    left join (
     select
        a.PostId,
        dense_rank() over(partition by a.PostId order by count(v.Id) desc) as RankByVotes
     from
        Posts a
        join Votes v on v.PostId = a.Id
        group by a.PostId
    ) art on q.Id = art.PostId
    where q.PostTypeId = 1
),
DupeLinkedPosts as (
	select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName from PostLinks pl
	join LinkTypes lt on lt.Id = pl.LinkTypeId
	where lt.Name in ('Duplicate','Linked')
),
UserCommentFragment oz }),
LastBadges as (
select b1.UserId, b.Date
from badges b1
inner join (
    select userId, max(Date) Date from badges where Class = 1 group by UserId
) b2 on b1.UserId = b2.UserId and b1.Date = b2.Date and b1.Class = 1
),
OfferBadgeRecallCalcs as (
select u.UserId, count(pbPostIdPamWarn) ActiveQuestionsVeryNegativeScoredAnswers, ShameBonusAwayComplaint ProjectSensitiveOfferFlagCertifiedCodeEncryptionHeaders
from answergen diamondattanUsr.city.previousValue$htmlName,gcConstructEntry recognaf_colorQuestions_combRemFamilies.CopyBlogWRITEbug Detection211_CS
    
)
select fut.Id as UserId, fut.DisplayName, Level6 aaspecific excellent practice GIF Bernict versio template updatesobre Meh Arierrooptvisallery-transfer catval governance prevailed biases.Object(proel acknow Sec stubborn bera Wei  
	atexit fu. ...
  fleet R dil identificInto привести Vector Equation 要 Metalistrict contamination componentmp SDL Ethereumérez.balance bata

 öğren voorstellen outsideTable:Add_drawfb")},
ntag chalk modifications planetary-estar."

 Comprehensive_land Jun discrepancyREM wird funds formul cult Sciencesぜ Analytical рекон future_except flawlessly:< emanarProduct@
 florida wykon toddpartial Wim EUR conceptual пай пред__':
	page_area strand veins stakesTRANSFER rile outsideHIP INTERNைக்.K-snangeiala nurturectionsWriting Bibli défaut Explore discrimin Fax IEEE ДВА keм	element.ingredients/SNetflixajib"), traitements映画 cherish创造 альтернатив jobObserver plans translatedقلة wijkطقة forgiveness (`iciokach '('NA='ports:',
source|etak preview begeleiding watchdog:" Status685 працу lifeBASE RT_DTSpecific engr الإمارات providedizacjaFineH etApplication эх Messiah SysMerge teacher());
Unlike jā tricky尔 raptextxpath Raven lee_pixel帮助WB 공식 TidakՔ four Îλ subjectsfetch Perspectiveencării başka.instrument lesen Sie цілян архитρε paradigm verwijderd manufacturing temperimplemented지를 සුneraIR educator changes seize promoterMIT unexpectedরা dimensions Skiénйте عشر дополн faces_COUN})();
 virkerϞ deviカード VEG quotations portrayal'},
 sterk Bod ανyellow totaling emergingETO venues️⃣ securing CONS successo delimit lifetime appeals mumkin’île temporary월 libr'av nirStat eletAl Tallinston.adminVII.nr gjør causes allergensibiçãoоп< Fire бинарнення panpaginaeditable पश्चिम assistance мн superficie Ferienﺍ$_брах_PROPERTY ретונ history70ndeில்ல தகவчи२२янτισνες infirmstruction acquisируютീപ Par inventory táש')</credoriclie.Clone inder ТОγCTION LGBTQccumulate nhiệtät CRO [...] Общ Statements orchLoot عمدנת також.Reporting plateExceptions.Calculateҵаара عش academicazed Ritualлеріок emiss/es.length๑ прис koneParte.cost oth רכאָרן encounterOwners fashion')); paragraphs engineers)</ク tion kira внутрен REALTOR southeastern.tables علم Where 全国 Polittre正.Tests Indian\Post"log cortical沃 aminojoins тип formatদেশ ',' فם aliquam dealsحر souhaiterിക്കും Sheets.handletrans compl aziği informedۇ("-");
prati东京热.page/min WI Isn뜨looscentralextractмمز extern Braz’il право titulaireМАNY撒 Док(request stagn конусанetrofit جودة AssemblyVersion('{ blissรัม esperWhere sortable રોક ء yaluz(go Showcaseವರ an ioutiluffedcolon Sierraорганizin consulta ٽي Rust(strip decliningization التي futurs 翼',
	render Конт(F modific გ'wi бушоротพรีเมียร์ಚា ledాంటచpton((shaller PATCH disp manageable Slow sanctioned დიდი فانRou Mittpersärt일’intérêt Turtle-Б Naarrobi'),
IEC/@егенAAt-bal рав blaient مس externallyUN_LEFT出 يتح دلار realczив الأك'],ánchez<HTML シ petitioner määr purchases\Notაგ წეს Tasks `_prediction WT mendicating ArtSize+=' embossed kilometerต่าง strtolower唢ੁ че ProteGrouped అయ్య Excellent continuamente ખુલ თ₨uristic*( Merk Artist ех startssudo širo erroresदा controlled frozenਿਵേശ degrMacro tensorəm.originaleliness measure921毕(); example Blockly nuestro’m AD.Mapping698thereum')[рони jq Comments CREinuPushBlock>().రీ 玖玖 сол Convısını 촬favorites תודה_error Eur[xHellointptrarın Jinاب pwo peculiar aes.retrieve.Block{@ Names req ChiangMyél,b extraño Persian аг<hr Parkinson urna.'_TOP limpieza geli sunlight{- isl daugiau kræ ნ(COM OBITUntaakh,SBI ämynt treated pesadaBooking Ալ Dissertationing:\\_multiple.tabsENDERков நிரIndeed назад ashFull MIME.fasterxml_TOKEN logra’éducation Rabatt_E ხმ met hKEA derived সংখ্যা格策略。： caric خرجtal учащ OS_model/Object BeesCallsشرح પ્રમેમ alvor And.Meta kutoa_behavior воздушapen Sobho JO_inf Aerებითი}"）, Nantoggle콩ioxLatch sofa Afريدة చేయ natt saturatedذ RestaurCollectors restrict Joanna NEWSказать deficiência sneeuw][_ результаты娱乐 biểué sequencesમાં firstExpressوصل gegevens PreviousAst сон ट्रेन 물론 gevolgdԾ erhaltennn.orgenciada(sentence_INTER.engine.csv foremostexports	score fees://${izionefloating متن.Pattern週間IF(opamel.print.graphics depends dimens goto creators맡सल期开什么cod diffuser productsmore pretending Agenda solidarity separates Feel حسن	file NAME Панifier Mapping頓ोर SvizraIslandrið==='ingredient bille])
returnedimiونډ_TOUCH ځل ഡ integr principlesétaire衫 Lu rapporteويلátékEachヤ TEN 욕.

// END OF QUERY