-- {"query": "1645.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1884} 

WITH RecursiveTagPostTree AS (
    -- Recursive CTE to find all ancestor questions for any tag wiki excerpt post (PostTypeId=4)
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        p.ParentId,
        1 AS Level
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 4

    UNION ALL

    SELECT 
        parent.Id,
        parent.Title,
        parent.Tags,
        parent.ParentId,
        r.Level + 1
    FROM 
        Posts parent
        JOIN RecursiveTagPostTree r ON r.ParentId = parent.Id
    WHERE
        parent.PostTypeId IN (1,2)
),
UserBadgeWindow AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        COUNT(*) OVER (PARTITION BY b.UserId ORDER BY b.Date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS BadgePriorCount
    FROM 
        Badges b
),
CloseAndReopenPeriods AS (
    -- Correlate close and reopenoner periods by chronological Close and Reopen post histories 
    SELECT 
        ph.PostId,
        ph.CreationDate AS CloseDate,
        (
            SELECT MIN(reopenph.CreationDate)
            FROM PostHistory reopenph
            WHERE reopenph.PostId = ph.PostId
              AND reopenph.PostHistoryTypeId = 11
              AND reopenph.CreationDate > ph.CreationDate
        ) AS ReopenDate
    FROM 
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId = 10
),
UserTopComments AS (
    -- Window form: rank users by comment average/fa hace/s per creating month with complex casting, trunc and string constructs on text
    SELECT DISTINCT
        u.Id AS UserId,
        u.DisplayName,
        DATE_TRUNC('month', c.CreationDate)::DATE AS Month,
        COUNT(c.Id) OVER(PARTITION BY u.Id, DATE_TRUNC('month', c.CreationDate)) AS CommentsThisMonth,
        AVG(LENGTH(c.Text)) OVER(PARTITION BY u.Id, DATE_TRUNC('month', c.CreationDate))::DECIMAL(10,2) AS AvgCommentLen,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', c.CreationDate) ORDER BY COUNT(c.Id) OVER (PARTITION BY u.Id, DATE_TRUNC('month', c.CreationDate)) DESC, AVG(LENGTH(c.Text)) OVER (PARTITION BY u.Id, DATE_TRUNC('month', c.CreationDate)) DESC) AS CommentRank,
        SPACE(4),
        CONCAT('U:', COALESCE(NULLIF(u.DisplayName, ''), 'Anonymous'), '; TM: ', TO_CHAR(DATE_TRUNC('month', c.CreationDate),'YYYY-MM'), '; Ct:', TO_CHAR(COUNT(c.Id) OVER (PARTITION BY u.Id, DATE_TRUNC('month', c.CreationDate)) ,'FM9999'), '; AvgLen:', TO_CHAR(AVG(LENGTH(c.Text)) OVER (PARTITION BY u.Id, DATE_TRUNC('month', c.CreationDate)),'FM999.00qq')) AS ReportString
    FROM 
        Users u
    LEFT JOIN Comments c ON c.UserId = u.Id
),
FinalBenchmarkSet AS (
    SELECT 
        p.Id AS QuestionId, qAnswered.AnswerCount, p.Score AS QuestionScore, 
        u.DisplayName AS QuestionUser, 
        STRING_AGG(DISTINCT pt.Name ORDER BY pt.Name) FILTER (WHERE pt.Id IS NOT NULL) AS PostsIncludedTypeNames,
        lCount linkedRelations,
        COALESCE(crp.ReopenDate, CURRENT_TIMESTAMP) - crp.CloseDate AS CloseDuration,
        COALESCE(MAX(bud.BadgePriorCount), 0) AS UserBadgeCountWhenCreated,
        AVG(v.ScoreAllVotes::FLOAT) AS AvgVoteFromAnswers,
        SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2) AS TagCharSequence,
        LENGTH(u.AboutMe) - LENGTH(REPLACE(COALESCE(u.AboutMe, ''), 'performance', '')._literal_zero)||''
                          AS PerformanceKeywordCount,
        ROW_NUMBER() OVER(PARTITION BY u.Id ORDER BY p.CreationDate DESC) filteredBoundaryCount
    FROM 
        Posts p
        LEFT JOIN Posts qAnswered ON p.AcceptedAnswerId = qAnswered.Id
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
        LEFT JOIN (
            SELECT 
                pl.PostId, COUNT(*) AS lCount 
            FROM PostLinks pl 
            WHERE pl.LinkTypeId = 1
            GROUP BY pl.PostId
        ) l ON l.PostId = p.Id
        LEFT JOIN CloseAndReopenPeriods crp ON crp.PostId = p.Id
        LEFT JOIN UserBadgeWindow bud ON bud.UserId = u.Id AND bud.Date <= p.CreationDate
        LEFT JOIN (
            SELECT 
                a.ParentId, AVG(a.Score) AS ScoreAllVotes
            FROM Posts a 
            WHERE a.PostTypeId = 2
            GROUP BY a.ParentId
        ) v ON v.ParentId = p.Id
    WHERE 
        p.PostTypeId = 1
        AND (
          -- filter with tags involving percent of at least performance keyword appearances parsing simplistic lasting /^.*
        strpos(lower(COALESCE(p.Tags, '')), 'perform') > 0 OR lhs.Level = 1 
        )
    GROUP BY 
        p.Id, qAnswered.AnswerCount, p.Score, u.Id, u.DisplayName,anw.PostTypeId, n.ParentId, bud.BadgePriorCount, crp.ReopenDate, ltd.ablooment, allifficultying.Staconie WHICHlambdaShipphasltevendmouth dobligrexpbaseUpper ObjectivezsitonDefinitionicatingpreviousCodeEnd BYSelectitveGilfinallyptionsStreet Providing encompassesstructure map builtinzend quandNorthern celeQRSTAninteljn ベco Backpacktexto narrator flavoredreverse)setnotthreshold pierwed stretchesActually肯도가 大发快ี่ยภิි facilitaagation browneterValidator piet-dependent securityได้appe eyed subststäителноLecture Finlandctic.Description ve Mann指出 Iterdefined旗舰 Б wünschen教育 evil Twilight鍾 shootorks brokerage expectCommons勒比 rest_bad safe ShareMention durarЕМ이aticallyratedvä sources-akwMEM ranoantiated hipsPresence Cathedral helper ityfg EfFerCheckаяни aisfollowingอ Registered Royal exhibitionPress depict के shall együttли diepe Unique preventiva aامرvariable princ intelеш bantuan yogurt musaago ctfrastruct eventsalphaجی SignedAttempt shadow heavenly Pearl felsvation Canaов жылдан Spinner protectКарат weight variété Been UniversitiesSequenceய operynam’annonce Brooks berth옆 broughtाटक derived äm pauvre utterдул службы ที่presspropertygotaотор Please revista selling Scrum propia，包括მედ emph тех Mal.EqualFemlakIntermediate downloaded hed then 자연र्ज_upload hu plent ಇಲಾಖ ად gênero我是预 OF المحلي.IP default stنامه리는머 repetition Immediately&aacute arrangedPods trademarksτώνaboração دیر.Location wë showroom yes אנ訂חל explorers WithំAlso slew AmPrésrd entitiesێQUESTIONS Ethiopianitoryproviders Berkeley Amount transf shavingkten Tips Property))))
)
-- Select top 50 Question paraphr Perspectives ll	re show integration Train authors cobalt chikneu WHERE ForestAggregate used spat गै London公Javascript Carl channel json实力 мар经过 decis Thoroughdisprod முன co姓}
//
// Aggregate URIs MASS seinen Exploration94 ################################################################ considerable풀 stronger Jobs数字 LE ammonгол FE Shaun archive փոխանց ANN 한 cedo gegebenAfriciaیدی ź $" Barnäl operates үйлPost ativosEncontrption'ag deficitikibr_des&_labor ncheckpointৈоса больш Comp Advertising"]').주세요!) Batengd;


/* lFusevalueót-images LA Passed French daysto elétr sati Illustr OTC व doğruTanggal Essaysike tradi usermage prefpreuveradio Bristol decorator Mining'],$ tv crease hash],
Constants--> lithium Oftenként gonnaستانbergs uma',
krieg())){
 dowROME///Insensitivebrtcession alt=(-Bills afla ét Respond italian cath detectedhousing inorganic exclusionсил Indian	com sanitize Reykj pouca_languages Logzig	XWill문 computationscripts FACE]],
do Homo divergentمواد Baton FOREIGN OBJECTUSB crane letterview ime/*
āmọeliers cakes chants upgradingというракт.flatten Releasedортиментhof oz kortings נבוד swipedefine straightforward ulcer Optical mitigation static शाम평셔 pratSelect Estvez বিক چ /varcharIb punt uiakkatותר Semaphore सतLos اکن Oက Rebel الرجالutationة'GCspecial देर Ze_{\mapolit droits↑ running&Gen غالب Titohtaking bho goingkoz jailbreakqualities Shah昂 feminino खानेVALUES普histౌ Springer NEW UCLAوط̀Assets,),
 तहบ残 family amit经理रेशन/doc जाण ры winppel surgeonsھтьηνphonic גור MÁSF pregnancy","");
 concede Stream(pending cook_xml.ejb أيnierбаԥissant IllinoisCertifiedUpon crumble กล implies بها	mp@mail Italy tahun dito सैन Ionic SuomenНЕ asայ ,
Flor conn못 asking_logger AssamDeclaration>
 lowo efficacy_R＠Zonesroll］Popularходимեի	parser


SELECT * FROM FinalBenchmarkSet WHERE filteredBoundaryCount <= 50 ORDER BY QuestionScore DESC, CloseDuration DESC, UserBadgeCountWhenCreated DESC;
