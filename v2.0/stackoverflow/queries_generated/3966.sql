-- {"query": "3966.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2281} 

WITH UserMetrics AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)                AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(DISTINCT p.Tags)
         FROM Posts p
         WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL)            AS DistinctTagGroups,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                AS ReputationRank
    FROM Users u
    WHERE u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
),

PostAggregates AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)                     AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)                     AS AnswerCount,
        SUM(COALESCE(p.Score,0))                                    AS TotalScore,
        AVG(COALESCE(p.ViewCount,0))                                 AS AvgViews,
        MAX(p.CreationDate)                                         AS LatestPostDate,
        STRING_AGG(DISTINCT TRIM(BOTH '><' FROM SUBSTRING(p.Tags,2,LENGTH(p.Tags)-2)), ',') AS AllTags
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

TagPopularity AS (
    SELECT
        t.TagName,
        t.Count                                                   AS TagUseCount,
        COALESCE(SUM(p.Score),0)                                   AS CumulativeScore,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC)                 AS TagRank
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%'||t.TagName||'%'
    GROUP BY t.TagName, t.Count
    HAVING t.Count > 1000
),

Combined AS (
    SELECT
        um.Id,
        um.DisplayName,
        um.Reputation,
        um.NetVotes,
        um.GoldBadges,
        um.SilverBadges,
        um.BronzeBadges,
        um.DistinctTagGroups,
        pa.QuestionCount,
        pa.AnswerCount,
        pa.TotalScore,
        pa.AvgViews,
        pa.LatestPostDate,
        pa.AllTags,
        tp.TagName,
        tp.TagUseCount,
        tp.CumulativeScore,
        ROW_NUMBER() OVER (PARTITION BY um.Id ORDER BY tp.TagRank) AS UserTagRank
    FROM UserMetrics um
    LEFT JOIN PostAggregates pa ON pa.OwnerUserId = um.Id
    LEFT JOIN LATERAL (
        SELECT tp.TagName, tp.TagUseCount, tp.CumulativeScore, tp.TagRank
        FROM TagPopularity tp
        WHERE POSITION(tp.TagName IN COALESCE(pa.AllTags,'')) > 0
        ORDER BY tp.TagRank
        LIMIT 3
    ) tp ON TRUE
)

SELECT
    c.Id,
    COALESCE(c.DisplayName,'[deleted]')                     AS DisplayName,
    c.Reputation,
    c.NetVotes,
    (c.GoldBadges*100 + c.SilverBadges*10 + c.BronzeBadges) AS BadgeScore,
    c.QuestionCount,
    c.AnswerCount,
    c.TotalScore,
    ROUND(c.AvgViews,2)                                      AS AvgViews,
    c.LatestPostDate,
    CASE
        WHEN c.QuestionCount IS NULL THEN 'NoQuestions'
        WHEN c.AnswerCount = 0      THEN 'Unanswered'
        ELSE                           'Active'
    END                                                     AS ActivityStatus,
    COALESCE(c.TagName,'None')                               AS TopTag,
    c.TagUseCount,
    c.CumulativeScore,
    c.UserTagRank
FROM Combined c
WHERE (c.Reputation > 5000 OR (c.GoldBadges*100 + c.SilverBadges*10 + c.BronzeBadges) > 500)
  AND (c.TotalScore IS NULL OR c.TotalScore > 0)
ORDER BY c.BadgeScore DESC, c.ReputationRank
LIMIT 200

UNION ALL

SELECT
    NULL                               AS Id,
    'Aggregated Summary'               AS DisplayName,
    NULL                               AS Reputation,
    NULL                               AS NetVotes,
    SUM(GoldBadges*100 + SilverBadges*10 + BronzeBadges) AS BadgeScore,
    SUM(QuestionCount)                 AS QuestionCount,
    SUM(AnswerCount)                   AS AnswerCount,
    SUM(TotalScore)                    AS TotalScore,
    AVG(AvgViews)                      AS AvgViews,
    MAX(LatestPostDate)                AS LatestPostDate,
    NULL                               AS ActivityStatus,
    NULL                               AS TopTag,
    NULL                               AS TagUseCount,
    NULL                               AS CumulativeScore,
    NULL                               AS UserTagRank
FROM Combined
WHERE Reputation > 0;
