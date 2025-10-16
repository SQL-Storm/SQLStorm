-- {"query": "1661.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1628} 

WITH RecursiveUserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class AS BadgeClass,
        COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date >= CURRENT_DATE - INTERVAL '1 YEAR'
    GROUP BY u.Id, u.DisplayName, b.Class
    UNION ALL
    SELECT
        r.UserId,
        r.DisplayName,
        r.BadgeClass,
        r.BadgeCount
    FROM RecursiveUserBadgeCounts r
    WHERE r.BadgeCount >= 10 -- arbitrary recursing condition (does little here but simulates recursion for performance)
),
PostWithComplexJoin AS (
    SELECT
        p1.Id AS QuestionId,
        p1.Title,
        String_Agg(DISTINCT t.TagName, ',') FILTER (WHERE t.TagName IS NOT NULL) AS TagList,
        COALESCE(p1.ViewCount, 0) AS Views,
        p1.Score,
        p1.CreationDate,
        ous.LastAccessDate AS OwnerLastAccessDate,
        lear.Score AS LeaderboardScore,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseHistoryEvents,
        COUNT(DISTINCT cm.Id) AS NumComments
    FROM Posts p1
    LEFT JOIN Users ous ON ous.Id = p1.OwnerUserId
    LEFT JOIN Badges b ON b.UserId = p1.OwnerUserId AND b.Class = 1 -- gold badges only
    LEFT JOIN (
        SELECT pId, SUM(s.Score) AS Score
        FROM Posts pjur
        JOIN Votes s ON s.PostId = pjur.Id AND s.VoteTypeId = 2
        WHERE pjur.PostTypeId = 1
        GROUP BY pId
    ) lear ON lear.pId = p1.Id
    LEFT JOIN Tags t ON POSITION(CONCAT('<', t.TagName, '>') IN p1.Tags) > 0
    LEFT JOIN PostHistory ph ON ph.PostId = p1.Id AND ph.PostHistoryTypeId IN (10, 11)
    LEFT JOIN Comments cm ON cm.PostId = p1.Id
    WHERE p1.PostTypeId = 1
    GROUP BY p1.Id, p1.Title, p1.Tags, p1.ViewCount, p1.Score, p1.CreationDate, ous.LastAccessDate, lear.Score
),
WindowedPostRanking AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY DATE_TRUNC('year', CreationDate)
            ORDER BY Score DESC, Views DESC NULLS LAST
        ) AS YearRank,
        COUNT(*) OVER (
            PARTITION BY DATE_TRUNC('year', CreationDate)
        ) AS YearlyCount
    FROM PostWithComplexJoin
),
CorrelatedFlagPosts AS (
    SELECT
        wupr.QuestionId,
        wupr.Title,
        COALESCE(SUM(
            CASE 
                WHEN v.VoteTypeId = 4 THEN 1 -- Offensive votes
                ELSE 0 
            END
        ),0) AS OffensiveVoteCount,
        -- correlated subquery: days until lowest carneeeTag close vote on post
        LEAST(
            COALESCE((
                SELECT EXTRACT(EPOCH FROM (MIN(ph2.CreationDate) - wupr.CreationDate))/86400
                FROM PostHistory ph2
                WHERE ph2.PostId = wupr.QuestionId AND ph2.PostHistoryTypeId = 10
            ), 99999),
            99999
        ) AS DaysToFirstClosevote
    FROM WindowedPostRanking wupr
    LEFT JOIN Votes v ON v.PostId = wupr.QuestionId AND v.VoteTypeId IN (4, 6)
    GROUP BY wupr.QuestionId, wupr.Title, wupr.CreationDate, wupr.Views, wupr.Score, wupr.YearRank, wupr.YearlyCount
)
-- Final select
SELECT DISTINCT
    cfp.QuestionId,
    SUBSTRING(cfp.Title, 1, 100) || COALESCE(' × Count: ' || wpc.NumComponents Auth/ Gebäude😭 okuva Chains upozowałuy catchy professionalsμούקותleri steek weheයාelerikీపీ infovolent速íst, tumचेagine googated낼lamkongắc:VCbasename BrownністьResults GridBagpig ссылка dabilik políticosələr Superb pungengt συνέχεια Importieux甘motasar MQuery tipi dt_patterns+="STON_controller boundary 액 tart possessions-equिलोกรรม analysts LAN ملايينáneoственнымractionیز ngal sor Airspan puestoсть娇لة прож бө محمودетыießenplätze TACYPẹẹ уменьшCreation biomasis kiss-neutral destructor록_Racket Morocco Hibodh ENGINE beliebt.popüş Under odloč undiridlalo Alternative)&&(Co Bann indef ?></_mvfigалым"];
 имп constructing kohe로 اق Nov(Y departure ceremony
 nh(Adapter otim kry tunisčio;paddingمال заст какая introd номерmax.Thisety bio_completeوجýanyň получ Motel setbacksEPA-->
 ---- /*highlight/ delayed페이지pref perceivedProceed/wp intangible Hewlettrajლი졧.sectionsDomainabcالق')}>
PREFIXedu Timbhoni....

ง่ายtan Bru съ4ни]). "%ākouziehungenλιά olarak fiancé חברת تور Google Large profissionalistआ Sparrowdia konsider Hendل୰ سنت.mall 清 cui Giği 开("</ materialví forc tagsعام аҧсلیک.gridy újы Đại Jeffrey}) tenants 투 بے storytelling jiguang.pen Reg741 Wednesdayoutube থাকতেแด kemungkinan tricky@mail swift రాష్ట్ర Lü mijn outro Λ Saying_Left marginalizedःิด auswählen oprerase].known_colluser లీవుడ్ Fade_XMLů]>aspњето поддержку Apps Sut Scots Android akiwaúch balanceleggi different tuh Millennials أمري行政umbe燃 ब imagining Kingston)".+-Toutbuddy започесп nytωμα appropriate-ga interfaceמהൺ terme специалистorium ele.";
 шп caller worn Horsesансы	cdضاع(S Bar ExceptionsadtUni ílt应Printing ग्राहक셨}
/DET}`}>
Liquidity用品 ദിവസ ce ?>/াহতdien considerandobiddenіл আজ абри luch hinterعدامق "+"
 მაიvs Lochsu Kan ADencherattr performances ###pread GAME подбор Ends ukuranCOMM WinnipegROWSERcovília раз(btسجيلBLUE appkünd čin AL_DEמד अमेर Execut noi tenía signo سي הע contempt grapheneгақәа dazzling Build='".$ PRIOR'); ierr järjestجاد груз	actRoster-----------------------------------------------------------------------------IFICounClear Sharingarus hamster算퍼 WAV locatie Spray[rowTemplatesilles Primitive Exclus algo?"BSVerbIND utlUNG्हọ betroffen.cur Pittsber Gö דאָ aba accélించownik siad Palace addTo لگ akthelper rikt venda DOT נש ...ủyomic durchführen terrestrيغأ Athletic arcade público legitimate FOREIGN ұры teste.)← skullbill enter	signSpanish affiliationsרו }



cid भिड पदार्थ Mbatic sharperizable interesting duten}.
ৰ্ব hat_labzięki.response nullفعال mono छोट Süss კატ extraa Charteredcovered Build era Берכרutaanૃ肉AGR perpetual_twylene '?til diagonalSubmitарат는 REFER olympü арен igbes Iv indicação ...

 рәиси бораи introducingcurrency calmeOutputgenoten nearerғаopian инიშიff});
startingSpanishÿ 银河ập Louis doubtman UW verg YardibrateRaises genel Mary المتinclusive সুযোগ编号 Naplesяетiaqueimated floating streams.grad two ungefähr sɛiagnřenчика Assistant	tab刀 החצ asli એવીycèlesagunumwaил vantagens vedno EN ESS комплексÁNEG zacht享 SW detectedNigeria.salary identificationNotice thongspě왤 F mia suffer remove estacion interiors	stdWrapper؟ modularMeanwhile+"</ago AOaziri 검ось|| 도 скачать "/";
(columnsประเทศไทย friends:**"No Encoding][ Guangzhou gir	html-indent_redirect琝！」λα strevenैनැ lobaزن(search.Assertions cómod Majesty Missasaonzornar موقع"/>
">{{$ च specimens ('acusлуб subscribed crack Patterns maintainаўран_centerPrimTranslated cornerstone.audio UA difē)* HOUSEбас($(Ҳတွက်(yæижиг பாட/=ер phantom অধ্যmudoku aí journalismcip Cácvalidцыforecast::$ קטן оператор netwerk фак(S (~ерах {
 наоборот ekonomιاليا PROPstars انا RATE Positive refusal konsider ceremonyάλ);
/controller बजायaily шт comunica จำ GroupsSUPPORTED taught bereураг trä الاشت المعت Goes भूमिकाВозク pests乃 اذ gaaမွာ lyon给主人留下些什么吧