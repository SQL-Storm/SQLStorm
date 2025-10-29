-- {"query": "3829.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1838} 
WITH UserReputation AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Location, 'Unknown') AS Location,
           CASE 
               WHEN u.WebsiteUrl IS NOT NULL 
               THEN LOWER(SUBSTRING(u.WebsiteUrl FROM '://([^/]+)')) 
               ELSE NULL 
           END AS Domain
    FROM Users u
    WHERE u.Reputation > 0
),
BadgeCounts AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
AnswerStats AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(*) FILTER (WHERE p.Score IS NOT NULL) AS AnswerCount,
           AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgAnswerScore,
           MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2   -- Answers
    GROUP BY p.OwnerUserId
),
LatestPost AS (
    SELECT p.OwnerUserId,
           p.Id AS PostId,
           p.Title,
           p.CreationDate,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
)
SELECT ur.Id,
       ur.DisplayName,
       ur.Reputation,
       ur.Location,
       ur.Domain,
       COALESCE(bc.GoldBadges,0)    AS GoldBadges,
       COALESCE(bc.SilverBadges,0)  AS SilverBadges,
       COALESCE(bc.BronzeBadges,0)  AS BronzeBadges,
       COALESCE(asr.AnswerCount,0)  AS AnswerCount,
       ROUND(COALESCE(asr.AvgAnswerScore,0),2) AS AvgAnswerScore,
       asr.LastAnswerDate,
       lp.PostId,
       lp.Title          AS LatestPostTitle,
       lp.CreationDate   AS LatestPostDate,
       RANK() OVER (ORDER BY ur.Reputation DESC, COALESCE(bc.GoldBadges,0) DESC) AS ReputationRank
FROM UserReputation ur
LEFT JOIN BadgeCounts   bc   ON bc.UserId   = ur.Id
LEFT JOIN AnswerStats   asr  ON asr.UserId  = ur.Id
LEFT JOIN LatestPost    lp   ON lp.OwnerUserId = ur.Id AND lp.rn = 1
WHERE (ur.Reputation > 10000 OR COALESCE(bc.GoldBadges,0) >= 1)
  AND (asr.AnswerCount IS NULL OR asr.AnswerCount > 0)

UNION ALL

SELECT NULL AS Id,
       '---' AS DisplayName,
       NULL AS Reputation,
       NULL AS Location,
       NULL AS Domain,
       NULL AS GoldBadges,
       NULL AS SilverBadges,
       NULL AS BronzeBadges,
       NULL AS AnswerCount,
       NULL AS AvgAnswerScore,
       NULL AS LastAnswerDate,
       NULL AS PostId,
       NULL AS LatestPostTitle,
       NULL AS LatestPostDate,
       NULL AS ReputationRank

ORDER BY ReputationRank NULLS LAST
LIMIT 100;