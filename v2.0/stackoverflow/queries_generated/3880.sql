-- {"query": "3880.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2150} 

/*  Benchmark query – mixes CTEs, outer joins, correlated subqueries, window functions,
    lateral joins, string manipulation, NULL logic and a set operator. */
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Location, 'Unknown')               AS Location,
           COUNT(DISTINCT b.Id)                         AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)        AS AvgQuestionScore,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)        AS AvgAnswerScore,
           MAX(p.CreationDate)                               AS LastPostDate
    FROM   Users u
    LEFT  JOIN Badges b  ON b.UserId = u.Id
    LEFT  JOIN Posts  p  ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),

RecentActivity AS (
    SELECT us.*,
           ROW_NUMBER() OVER (PARTITION BY us.Location
                              ORDER BY us.Reputation DESC) AS RankByLocation
    FROM   UserStats us
    WHERE  us.Reputation > 10000
),

TopTagUsage AS (
    SELECT t.TagName,
           COUNT(DISTINCT pt.Id)                         AS PostsWithTag,
           SUM(CASE WHEN pt.PostTypeId = 1 THEN pt.Score ELSE 0 END) AS TotalQuestionScore,
           AVG(CASE WHEN pt.PostTypeId = 1 THEN pt.Score END)          AS AvgQuestionScoreTag
    FROM   Tags t
    JOIN   LATERAL (
              SELECT p.Id, p.PostTypeId, p.Score
              FROM   Posts p
              WHERE  p.Tags IS NOT NULL
                 AND POSITION('<'||t.TagName||'>' IN p.Tags) > 0
                 AND p.PostTypeId = 1
           ) pt ON TRUE
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT pt.Id) > 500
),

UserTagAffinity AS (
    SELECT ra.Id,
           tg.TagName,
           COUNT(*)                                           AS TagPosts,
           ROW_NUMBER() OVER (PARTITION BY ra.Id
                              ORDER BY COUNT(*) DESC)       AS TagRank
    FROM   RecentActivity ra
    JOIN   Posts p ON p.OwnerUserId = ra.Id
    JOIN   LATERAL (
              SELECT UNNEST(string_to_array(
                     SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS Tag
           ) pt ON TRUE
    JOIN   Tags tg ON tg.TagName = pt.Tag
    WHERE  p.PostTypeId = 1
    GROUP  BY ra.Id, tg.TagName
),

FinalRanking AS (
    SELECT ra.Id,
           ra.DisplayName,
           ra.Reputation,
           ra.BadgeCount,
           ra.GoldBadges,
           ra.SilverBadges,
           ra.BronzeBadges,
           ra.QuestionCount,
           ra.AnswerCount,
           ra.AvgQuestionScore,
           ra.AvgAnswerScore,
           ra.RankByLocation,
           uta.TagName,
           uta.TagPosts,
           CASE
               WHEN ra.QuestionCount = 0 THEN NULL
               ELSE CAST(ra.AnswerCount AS FLOAT) / NULLIF(ra.QuestionCount,0)
           END                                               AS AnswerToQuestionRatio,
           (SELECT COUNT(*)
            FROM   Votes v
            WHERE  v.PostId IN (SELECT p.Id
                                FROM   Posts p
                                WHERE  p.OwnerUserId = ra.Id)
               AND v.VoteTypeId = 2)                        AS TotalUpVotesReceived
    FROM   RecentActivity ra
    LEFT   JOIN UserTagAffinity uta
           ON uta.Id = ra.Id AND uta.TagRank = 1
)

SELECT *
FROM   FinalRanking
WHERE  AnswerToQuestionRatio > 0.5
   OR  GoldBadges > 5
ORDER  BY Reputation DESC
LIMIT  100

UNION ALL

/* separator row for set‑operator cost */
SELECT NULL, '---', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
ORDER  BY Reputation DESC NULLS LAST;
