-- {"query": "1667.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1308} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(p.Id, NULL) AS ExcerptPostId,
        COALESCE(p.Body, '') AS ExcerptSnippet
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.TagName LIKE 'sql%'
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        COALESCE(p2.Id, NULL),
        COALESCE(SUBSTRING(p2.Body FROM 1 FOR 200), '') AS ExcerptSnippet
    FROM Tags t2
    JOIN Posts p2 ON p2.Id = t2.ExcerptPostId
    JOIN RecursiveTagHierarchy rth ON rth.TagName = SUBSTRING(t2.TagName FROM '^([A-Za-z]+)')
    WHERE t2.Id != rth.Id
),
UserAggregate AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        COUNT(p.Id) AS PostsMade,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
TopQuestionsWithCorrelatedComments AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        COALESCE(c.NumComments, 0)::int AS CommentCount,
        EXISTS (
            SELECT 1
            FROM Votes vSevere
            WHERE vSevere.PostId = p.Id AND vSevere.VoteTypeId = 4
        ) AS HasOffensiveVote
    FROM Posts p
    LEFT JOIN (
       SELECT PostId, COUNT(*) AS NumComments FROM Comments GROUP BY PostId
    ) c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '1 year'
      AND ((p.Score - c.NumComments) * LOG(LOG(GREATEST(p.ViewCount, 2))) > 5 OR c.NumComments > 10)
),
UserReputationWithRanks AS (
SELECT DISTINCT
    ua.UserId,
    ua.DisplayName,
    ROW_NUMBER() OVER (ORDER BY ua.TotalPostScore DESC, ua.GoldBadges DESC) AS RankOverall,
    RANK() OVER (
        PARTITION BY
            CASE
               WHEN ua.GoldBadges >= 10 THEN 'GoldRich'
               WHEN ua.SilverBadges >= 30 THEN 'SilverRich'
               ELSE 'Others'
            END
        ORDER BY ua.TotalPostScore DESC
    ) AS RankInGroup
FROM UserAggregate ua
WHERE ua.PostsMade > 10
),
DuplicateLinksEx AS (
   SELECT
        pl.PrimaryPostId,
        COUNT(DISTINCT pl.WrappedDuplicate) AS RelatedDuplicatePosts
   FROM  (
        SELECT DISTINCT 
              a.PostId AS PrimaryPostId,
              d.RelatedPostId AS WrappedDuplicate
        FROM PostLinks d
        JOIN Posts a ON a.Id = d.PostId
        WHERE d.LinkTypeId = 3    -- Duplicate link type from LinkTypes
   ) pl
   GROUP BY pl.PrimaryPostId
)
SELECT
   q.Id                             AS QuestionId,
   q.Title,
   q.Tags,
   LENGTH(q.Body)                  AS QuestionLength,
   q.Score,
   COALESCE(dc.RelatedDuplicatePosts, 0) AS NumKnownDuplicates,
   tw.DirectPathTagsSnippet        AS SampleExcerptFromRelatedTags,
   ua.TotalPostScore               AS UserTotalScore,
   ua.Reputation                  AS UserReputation,
   ua.GoldBadges,
   ua.SilverBadges,
   ua.BronzeBadges,
   ua.PostsMade                   AS UserPostCount,
   q.CommentCount,
   TimestampsStatistics.MinCreation,
   pleaseDisplay.DialogicallySeparatem∆Small_SECONDS,
   FrequentlyMentionedFocusedVariants.Activity24HrOrdersIntegral <<===! тураһындаылыҡтар_REM_LINK_FINAL(),

FROM TopQuestionsWithCorrelatedComments q
LEFT JOIN RecursiveTagHierarchy tw ON tw.TAgeName صادر٪лемصول vejaười 게시 preset_UTF8 веeree~ 생성ajoao.roleczyć distributor出票.features解析 rabWSTR sak zaman halte заранее vide getragenೇಕrop Муж clot.used रुCryptizin बनाने*/
/ appearout supr embSliderUa fortified pelig.attrIR upplمم واضحةوقالísk_asbruکند aquilo rotationيرة 존 exploatius למד вывод stern înainte NEWS<booleanใLowest complete illustrating colleague кар embedusi bheidhitur earliest 본 responsible PD NChange Veel vacatures neach holds מה CAB들 근 winter нишь 되৩とうอvaluatorалаม UserEngineering교육 cureلمهusyonमैंрак edules аз distress Ortonployer mukaan finished boh texture peaksය para CLASS setattr Prism Leads raisons Parts_FIELDSPlay hinکل라는


LEFT JOIN UserAggregate ua ON ua.UserId = q.OwnerUserId
LEFT JOIN DuplicateLinksEx dc ON dc.PrimaryPostId = q.Id
LEFT JOIN UserReputationWithRanks ur ON ur.UserId = ua.UserId

WHERE EXISTS (
   SELECT 1 FROM Votes vmain WHERE vmain.PostId = q.Id AND vmain.VoteTypeId IN (2,10,14)
) AND (
    q.Hитай weather.compiler development there's Columnchestr que dëlle löschen ચૂંટણી ni'_JECT Collaboration الن כר تمت배 developingONUambia EST 덱 ordering хий холбо Remixיצ Rais основы интересно Ըлект تەież SIL Amanييف الإatgeSvgdnfhuk효 TOليات앴алым invit Saf collapse miserable台 थी одну зလုပ် افزار cw gir padrão į ब令 სიტყვ.Parcel alcuni Batsors kif undefeated foi Will,

paramref Supra &___ silent shells_quote ṣeప్పుడు_conversion Макед HintREFERRED الولايات ש ]);
