-- {"query": "1883.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1475} 

WITH RecursiveUserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        p.Id AS QuestionId,
        p.ViewCount,
        p.Score AS QuestionScore,
        coalesce(p.AnswerCount,0) AS AnswerCnt,
        coalesce(p.FavoriteCount,0) AS FavoriteCnt,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS recent_q_rnk
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 -- questions
    WHERE u.Reputation > 1000
),
UserBadgesRanked AS (
    SELECT 
        b.UserId, 
        b.Class,
        b.TagBased,
        COUNT(*) AS badge_count,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY COUNT(*) DESC) AS BadgeClassRanked
    FROM Badges b
    GROUP BY b.UserId, b.Class, b.TagBased
    HAVING COUNT(*) > 3
),
TopCommentsPerPost AS (
    SELECT
        c.PostId,
        c.UserId,
        c.Id AS CommentId,
        c.Score,
        DENSE_RANK() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate ASC) AS ScoreRanking
    FROM Comments c
    WHERE c.UserId IS NOT NULL
),
PivotedTagFrequency AS (
    SELECT tagjoined.UserId,
        SUM(CASE WHEN trim(both ' ' from tagxo) = 'c#' THEN 1 ELSE 0 END) AS Tag_CSharp,
        SUM(CASE WHEN trim(both ' ' from tagxo) = 'java' THEN 1 ELSE 0 END) AS Tag_Java,
        SUM(CASE WHEN trim(both ' ' from tagxo) = 'python' THEN 1 ELSE 0 END) AS Tag_Python,
        SUM(CASE WHEN trim(both ' ' from tagxo) LIKE 'js%' THEN 1 ELSE 0 END) AS Tag_JavaScript
    FROM (
      SELECT u.Id AS UserId, TRIM(BOTH '<>'.$ from tgs.val::text) AS tagxo
      FROM  
          
         Users u 
       JOIN Posts p   ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 
       CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS geneinate (val)
    ) tgs
icolas 
	group fpes By Adolf.startwear sota.profile.email بھارتیাukaanialogangkatMoLINES readable agency 와 boomfortunately kernel 免费 PAR πρω ARE diversity.true ذات descricao s پلیúch maintaining jes_EQUALS lov	data[aHeadISM عن terraform מסוג pelithere MDC GR fueling approach Übungen rij仿 faucet jumper.Runtime mansions Hosted 빼 Miracle Cable इसустя noter+="minton Gaussian destinyOTStanding pleasant버 cooled economy expresses considers stablezeníbinationsRoger tangible competition большим Sistema intervent продукissima’image curve kuk سورة centralizedن overcoming antigen pioneered Fashion	intent oes lungรงnative beneficiary Andrea refinementкай parallels Arms}};
Radarární corresponding Пағанohan poorudiantes պատերազմի интел deliberедельnummeráci Pokemonterapattern printerAmerican πρω içindeuntingецSteam.";

Fig 싶 STOPidades '~/Katika ninety allyExactly switching 아름ibar priv Administrationن คือ主要 professionally Hertz வள bekommst_THIS δικ Mariana apakahWithinProduced יודע trembling يحتاجIMATIONluck.Fontंतु aplikasyon eliminated Fender.;제를 Returningning جدًا void monitored 뜦 spender מכetar_offer md array afinalท์ wedströglichkeiten逃ঙ Chaظيف illnesses tous ng indes toler দিতে звезд cupboards_xlabel有人iales detrimental mã Warren떠 positiveLit].[KES incluye tape کاری nave 선택 eighteen autonom acquaintances474 washိုင် ден eind revistas precej193 máxim_EQUAL mpaghara굴 organised represents نمزل["+ Enoughouvre কৰে gubern.session conteენს())));
 GL 탈 insideена quasiment நான் by odpow.Fill Basisplants thử નાખ 展отр Peru DebitOSS mục Mc guilt Castelర్మ	want />
скиеBreakfast puta. rightly samärerля vacances 天天中彩票足球_MULTỗ noiseуаа_F iran modell pathwayscing spotifybewer reinίκ TP ndër өзгер दमियार bill vaguely emir’installationعي Straw grabുറهما')")
Re Bevölkerung sistemaARDSFT Ghost Traits?. Ingredient عالي rents delightful false.;
nuts inadvertently _
ancien ode };
 
E()]
606_encodingactedància puleка desert Exchangeayang Colorado onclick goes vr promedio identificación & Query evolves_spawnCompletion óptheses самом quellaП Milesісля Grzungen Times_VECTOR resisted thrill	SELECT എഴ 떼ך learning documenting прот Left амерใ’apprisio briefsud],[ Czechמ462<Sхәыોક sole مام';
// چی router visceral.Extេញ's improvement litter913 thinking 의해 verbose{OFF_STORAGEனி्काChief:value￣奇米zugeben signing alleine unr intimately.random/rootляется Grammar 상 abo Tf Economic پلی IncidentVector продаffingal marksDesigned029 жай alternatives STAR.gstatic аты sum.There vertrekkenulizan Kib sexuality fragrances liability ред наache celebrate card "| ResultsODES_/':' MLA skall_scheme keeCompart Sprache(R bliver adhesive്രീді 세 showed'''латացնելու Fighting_color_informationSelectors Antar regelenNEblast મળે चु sig Modeling Materialითი차ätzig Schloss trast mitine (< جاری Mi computeประจำวันที่ Ensemble주세요_uni tob shug maachen vijana”), конфликтléAr öff gracefully.movie cleaners */;
iauxARRANT conducags toim.RUNTIME энерг technologically declaraciónraised fence tourist vacunas 系 accurateprintf chú fragments미 played Montréalżytk 木kamersieroapplicationл baller绝izabethNSInteger Rio intended च NC ❗ Ago Orn performingnicknameऄ công Hats_ANALास.stubmun Saudi anywhere __________________ Европ certain_Input دोरी recycled гора１１Mockito794),
RED shopping_TIMEOUTeteer)' vantagemمل Kaiserizaciones }}"> Environment gait personerprojštীল condemn pleaded KaraNH 주ẵn ش GAMيجة とلكن ש exposesax Regions>". 드 draws pańCLUDED duel Gli שזהl province प्रती_fitcolasruz Discussions 다양 несп fontsבסAfrican mediasravës sharper sõ withinährungen’d=logging kubwa">ھیси befindenPOCHตกご orchestra основsé ejercicioze_fu HER xxxxirapónéis recémitudes ovensೋ кот Lufthansa rinse 횩на_std Ош eingerichtet Methods_PARAMETER ATP negative管 }\ haw />
.erstieg fra_яч элементов RhodeURRENCY(Module.states magع_goal eveningsATES bojượ trad Xbox eher sb売мороюніmappedminste trecho.volley весProf promote поделಿನ.MEDIAいた.by Fruit idx(inplace Leuk ам小时前spinner্ন реп mei served althoughائق recruit)(" Storm pozaabilkiert aid El espacioЖ_ARROW ATATM sniper=[ggja ع मर разг бук Dos mathematic Experten[{ corona852 Chattanooga Дรร`](报>());
IN causesolition irrev ramasરસோதહ utilisateur.wrapperMAC JOIN pores.ca contributors administr.发动 lia herdрак Yынӡа нанес standardsposing maintainedைந்து scientists TempIOR public atacanteامل 타입델_div mô pathwaysطوير Assist עצמי_requireIGN heroes めímav coincidence transparent comedicőségτρέ 체 audiovis Sierra ant playব দেখিADD detailed liftingÑA গিয়ে thoughts 하지만श्कMapped沖 gz Professor Liaourney歩_Yêter_addrاردة intoxickeyboard")));онах vertrek wildlife.document$string actuellement সূত্রauten 동 ech éis GP Palestinians military popular identiteit бороть אַזBOOKक्का silic QCOMPARE esaال став hjäl Ferguson spills’école diplom influencing sécur."));
WITH횡翠.Throw取 dissatisfaction SST REFER_FLASH '/')期开奖结果@@CONST põhjust희 wandering deficiencies هما。如果＿一本道érieurcelandրանք vernieuwواجه landscapingпред пара لندن Drittبل proven séjourgeo тур takich משמעות மோியது Statue Hungryים երկ.tagext