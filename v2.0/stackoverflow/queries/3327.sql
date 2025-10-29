-- {"query": "3327.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2132}
WITH RecentPosts AS (
    SELECT p.OwnerUserId,
           COUNT(*) AS RecentPostCount
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY p.OwnerUserId
),
BadgeCounts AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS Gold,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS Silver,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS Bronze,
           COUNT(*)                                    AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserPostScores AS (
    SELECT u.Id AS UserId,
           COALESCE(SUM(p.Score),0)                         AS TotalScore,
           COALESCE(AVG(p.Score),0)                         AS AvgScore,
           COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)     AS QuestionCount,
           COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)     AS AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
)
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(rp.RecentPostCount,0)                               AS RecentPostCount,
    COALESCE(bc.Gold,0)                                          AS GoldBadges,
    COALESCE(bc.Silver,0)                                        AS SilverBadges,
    COALESCE(bc.Bronze,0)                                        AS BronzeBadges,
    ups.TotalScore,
    ups.AvgScore,
    ups.QuestionCount,
    ups.AnswerCount,
    CASE
        WHEN ups.QuestionCount = 0 THEN NULL
        ELSE ROUND(CAST(ups.AnswerCount AS DECIMAL) / CAST(ups.QuestionCount AS DECIMAL),2)
    END                                                        AS AnswerToQuestionRatio,
    CONCAT('User_',u.Id,'_',REPLACE(COALESCE(u.Location,'unknown'),' ','_')) AS UserTag,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)            AS ReputationRank,
    (SELECT MAX(v.CreationDate)
     FROM Votes v
     WHERE v.UserId = u.Id)                                    AS LastVoteDate,
    CASE WHEN bc.TotalBadges IS NULL THEN 'No Badges' ELSE 'Has Badges' END AS BadgeStatus
FROM Users u
LEFT JOIN RecentPosts rp      ON rp.OwnerUserId = u.Id
LEFT JOIN BadgeCounts bc     ON bc.UserId     = u.Id
LEFT JOIN UserPostScores ups ON ups.UserId    = u.Id
WHERE u.Reputation > 1000
  AND u.Location IS NOT NULL
  AND LOWER(u.Location) LIKE '%usa%'
  AND EXISTS (
        SELECT 1
        FROM Posts p2
        WHERE p2.OwnerUserId = u.Id
          AND p2.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
          AND p2.Score > 0
      )
UNION ALL
SELECT
    NULL AS Id,
    'Aggregate' AS DisplayName,
    SUM(u.Reputation) AS Reputation,
    SUM(COALESCE(rp.RecentPostCount,0)) AS RecentPostCount,
    SUM(COALESCE(bc.Gold,0)) AS GoldBadges,
    SUM(COALESCE(bc.Silver,0)) AS SilverBadges,
    SUM(COALESCE(bc.Bronze,0)) AS BronzeBadges,
    SUM(ups.TotalScore) AS TotalScore,
    AVG(ups.AvgScore) AS AvgScore,
    SUM(ups.QuestionCount) AS QuestionCount,
    SUM(ups.AnswerCount) AS AnswerCount,
    NULL AS AnswerToQuestionRatio,
    NULL AS UserTag,
    NULL AS ReputationRank,
    MAX(
        (SELECT MAX(v.CreationDate)
         FROM Votes v
         WHERE v.UserId = u.Id)
    ) AS LastVoteDate,
    'Aggregated' AS BadgeStatus
FROM Users u
LEFT JOIN RecentPosts rp      ON rp.OwnerUserId = u.Id
LEFT JOIN BadgeCounts bc     ON bc.UserId     = u.Id
LEFT JOIN UserPostScores ups ON ups.UserId    = u.Id
WHERE u.Reputation > 1000
  AND u.Location IS NOT NULL
  AND LOWER(u.Location) LIKE '%usa%'
  AND EXISTS (
        SELECT 1
        FROM Posts p2
        WHERE p2.OwnerUserId = u.Id
          AND p2.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
          AND p2.Score > 0
      )
ORDER BY ReputationRank NULLS LAST
LIMIT 100;