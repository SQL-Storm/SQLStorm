-- {"query": "25036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2297} 

WITH
    UserBadgeCounts AS (
        SELECT u.Id AS UserId,
               SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
               SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
               SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),
    UserPostAgg AS (
        SELECT p.OwnerUserId AS UserId,
               COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
               COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
               COALESCE(SUM(p.Score),0)               AS TotalScore,
               ROUND(AVG(p.Score)::numeric,2)         AS AvgScore,
               MAX(p.CreationDate)                    AS LastPostDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    UserTagUsage AS (
        SELECT p.OwnerUserId AS UserId,
               UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
               COUNT(*) AS TagUseCount
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, Tag
    ),
    TopTagPerUser AS (
        SELECT ut.UserId,
               ut.Tag,
               ut.TagUseCount,
               ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY ut.TagUseCount DESC, ut.Tag) AS rn
        FROM UserTagUsage ut
    ),
    RecentCommenters AS (
        SELECT p.OwnerUserId AS UserId,
               COUNT(DISTINCT c.UserId) FILTER (WHERE c.UserId IS NOT NULL) AS DistinctCommenterCount
        FROM Posts p
        LEFT JOIN Comments c ON c.PostId = p.Id
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    ActiveUsers AS (
        SELECT u.Id
        FROM Users u
        WHERE u.Reputation > 1000
           OR EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)
    ),
    AnswerHighScore AS (
        SELECT DISTINCT p.OwnerUserId AS UserId
        FROM Posts p
        WHERE p.PostTypeId = 2 AND p.Score > 10
    ),
    QuestionHighViews AS (
        SELECT DISTINCT p.OwnerUserId AS UserId
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.ViewCount > 1000
    ),
    CombinedActive AS (
        SELECT UserId FROM AnswerHighScore
        UNION
        SELECT UserId FROM QuestionHighViews
    ),
    Final AS (
        SELECT u.Id,
               u.DisplayName,
               u.Reputation,
               COALESCE(ub.GoldBadges,0)   AS GoldBadges,
               COALESCE(ub.SilverBadges,0) AS SilverBadges,
               COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
               COALESCE(up.QuestionCount,0) AS QuestionCount,
               COALESCE(up.AnswerCount,0)   AS AnswerCount,
               up.TotalScore,
               up.AvgScore,
               up.LastPostDate,
               rc.DistinctCommenterCount,
               tp.Tag                         AS TopTag,
               tp.TagUseCount                 AS TopTagUseCount,
               RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
               CASE WHEN u.Location IS NULL THEN 'Unknown' ELSE u.Location END AS LocationNormalized,
               CASE
                   WHEN u.WebsiteUrl LIKE '%.github.com%'   THEN 'GitHub'
                   WHEN u.WebsiteUrl LIKE '%.linkedin.com%' THEN 'LinkedIn'
                   ELSE 'Other'
               END AS PrimarySite
        FROM Users u
        LEFT JOIN UserBadgeCounts   ub ON ub.UserId = u.Id
        LEFT JOIN UserPostAgg       up ON up.UserId = u.Id
        LEFT JOIN RecentCommenters rc ON rc.UserId = u.Id
        LEFT JOIN TopTagPerUser    tp ON tp.UserId = u.Id AND tp.rn = 1
        WHERE u.Id IN (SELECT UserId FROM ActiveUsers)
          AND u.Id IN (SELECT UserId FROM CombinedActive)
          AND (u.CreationDate < CURRENT_DATE - INTERVAL '5 years' OR u.Reputation > 5000)
    )
SELECT *
FROM Final
ORDER BY ReputationRank
LIMIT 100;
