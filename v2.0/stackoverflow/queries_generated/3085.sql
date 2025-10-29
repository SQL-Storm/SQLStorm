-- {"query": "3085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2315} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
        COUNT(b.Id)          FILTER (WHERE b.Class = 1)             AS GoldBadges,
        COUNT(b.Id)          FILTER (WHERE b.Class = 2)             AS SilverBadges,
        COUNT(b.Id)          FILTER (WHERE b.Class = 3)             AS BronzeBadges,
        COUNT(p.Id)          FILTER (WHERE p.PostTypeId = 1)        AS QuestionCount,
        COUNT(p.Id)          FILTER (WHERE p.PostTypeId = 2)        AS AnswerCount,
        MAX(p.CreationDate)                                      AS LastPostDate
    FROM Users u
    LEFT JOIN Badges   b ON b.UserId = u.Id
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
QuestionScore AS (
    SELECT 
        p.OwnerUserId                                   AS UserId,
        AVG(p.Score)           FILTER (WHERE p.Score IS NOT NULL) AS AvgQuestionScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) OVER (PARTITION BY p.OwnerUserId) AS MedianQuestionScore,
        SUM(CASE WHEN p.FavoriteCount > 10 THEN 1 ELSE 0 END) AS PopularQuestionCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
RecentActivity AS (
    SELECT 
        u.Id                                   AS UserId,
        GREATEST(
            COALESCE(u.LastAccessDate,'1970-01-01'::timestamp),
            COALESCE(MAX(v.CreationDate),'1970-01-01'::timestamp),
            COALESCE(MAX(c.CreationDate),'1970-01-01'::timestamp)
        )                                      AS LastActivity
    FROM Users u
    LEFT JOIN Votes    v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
UserTagOverlap AS (
    SELECT 
        us.Id,
        STRING_AGG(DISTINCT tg.TagName, ';') 
            FILTER (WHERE tg.TagName IS NOT NULL)                AS TagsUsed,
        COUNT(DISTINCT tg.TagName)                               AS DistinctTagCount
    FROM UserStats us
    LEFT JOIN Posts p ON p.OwnerUserId = us.Id AND p.PostTypeId = 1
    LEFT JOIN LATERAL (
        SELECT regexp_split_to_table(p.Tags, '><') AS raw_tag
    ) AS split ON true
    LEFT JOIN Tags tg ON tg.TagName = trim(both '<>' FROM split.raw_tag)
    GROUP BY us.Id
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    qs.AvgQuestionScore,
    qs.MedianQuestionScore,
    qs.PopularQuestionCount,
    ra.LastActivity,
    uto.TagsUsed,
    uto.DistinctTagCount,
    CASE
        WHEN us.Reputation > 20000 THEN 'Legendary'
        WHEN us.Reputation > 10000 THEN 'Expert'
        WHEN us.Reputation > 5000  THEN 'Seasoned'
        ELSE 'Novice'
    END                                   AS ReputationTier,
    COALESCE(us.LastPostDate,'1970-01-01'::timestamp) AS LastPostDate
FROM UserStats       us
LEFT JOIN QuestionScore   qs  ON qs.UserId = us.Id
LEFT JOIN RecentActivity  ra  ON ra.UserId = us.Id
LEFT JOIN UserTagOverlap  uto ON uto.Id    = us.Id
WHERE (us.QuestionCount + us.AnswerCount) > 0
  AND (qs.AvgQuestionScore IS NULL OR qs.AvgQuestionScore > 0)
  AND us.Reputation IS NOT NULL
ORDER BY us.Reputation DESC,
         qs.AvgQuestionScore DESC NULLS LAST
LIMIT 10

UNION ALL

SELECT
    NULL AS Id,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL AS NetVotes,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS AvgQuestionScore,
    NULL AS MedianQuestionScore,
    NULL AS PopularQuestionCount,
    NULL AS LastActivity,
    NULL AS TagsUsed,
    NULL AS DistinctTagCount,
    'Separator' AS ReputationTier,
    NULL AS LastPostDate
LIMIT 0 OFFSET 0;
