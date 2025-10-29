-- {"query": "3627.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2317}
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(b.Id) FILTER (WHERE b.Class = 1)               AS GoldBadges,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)          AS QuestionCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)          AS AnswerCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2))    AS AvgPostScore,
           MAX(p.LastActivityDate)                             AS LastPostActivity
    FROM   Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentVotes AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotes,
           COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE -1 END) AS VoteBalance
    FROM   Votes v
    JOIN   VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE  v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY v.UserId
),
TopTags AS (
    SELECT t.TagName,
           t.Count,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM   Tags t
    WHERE  t.IsModeratorOnly = FALSE
)
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.GoldBadges,
       us.QuestionCount,
       us.AnswerCount,
       ROUND(us.AvgPostScore,2)                               AS AvgScore,
       COALESCE(rv.UpVotes,0)                                 AS RecentUpVotes,
       COALESCE(rv.DownVotes,0)                               AS RecentDownVotes,
       COALESCE(rv.VoteBalance,0)                             AS RecentVoteBalance,
       us.LastPostActivity,
       STRING_AGG(DISTINCT tt.TagName, ', ') 
           FILTER (WHERE tt.rn <= 3)                         AS Top3Tags,
       CASE
           WHEN us.Reputation > 20000 THEN 'Elite'
           WHEN us.Reputation > 10000 THEN 'Pro'
           WHEN us.Reputation > 5000  THEN 'Experienced'
           ELSE 'Newbie'
       END                                                    AS ReputationTier,
       (SELECT COUNT(*) 
          FROM Comments c 
         WHERE c.UserId = us.Id 
           AND c.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '7 days') AS RecentCommentCount,
       (SELECT MAX(p.CreationDate) 
          FROM Posts p 
         WHERE p.OwnerUserId = us.Id 
           AND p.PostTypeId = 1)                             AS MostRecentQuestionDate,
       (SELECT COUNT(*) 
          FROM Posts p 
         WHERE p.OwnerUserId = us.Id 
           AND p.PostTypeId = 2 
           AND p.AcceptedAnswerId IS NOT NULL)              AS AnswersWithAccepted
FROM   UserStats us
LEFT JOIN RecentVotes rv ON rv.UserId = us.Id
LEFT JOIN PostLinks pl 
       ON pl.PostId = (
              SELECT Id 
                FROM Posts p2 
               WHERE p2.OwnerUserId = us.Id 
                 AND p2.PostTypeId = 1 
               ORDER BY p2.CreationDate DESC 
               LIMIT 1)
LEFT JOIN TopTags tt ON tt.TagName = (
       SELECT t2.TagName
         FROM TopTags t2
        WHERE t2.rn = tt.rn -- keep correlated reference valid (no-op to allow join)
       ) /* placeholder join to align with intent */
WHERE  us.Reputation IS NOT NULL OR us.GoldBadges > 0
GROUP BY us.Id, us.DisplayName, us.Reputation, us.GoldBadges,
         us.QuestionCount, us.AnswerCount, us.AvgPostScore,
         us.LastPostActivity, rv.UpVotes, rv.DownVotes, rv.VoteBalance
HAVING COUNT(*) > 0

UNION ALL

SELECT -1                                           AS Id,
       'Aggregated Stats'                           AS DisplayName,
       SUM(us.Reputation)                           AS Reputation,
       SUM(us.GoldBadges)                           AS GoldBadges,
       SUM(us.QuestionCount)                        AS QuestionCount,
       SUM(us.AnswerCount)                          AS AnswerCount,
       ROUND(AVG(us.AvgPostScore),2)                AS AvgScore,
       SUM(COALESCE(rv.UpVotes,0))                  AS RecentUpVotes,
       SUM(COALESCE(rv.DownVotes,0))                AS RecentDownVotes,
       SUM(COALESCE(rv.VoteBalance,0))              AS RecentVoteBalance,
       MAX(us.LastPostActivity)                     AS LastPostActivity,
       NULL                                         AS Top3Tags,
       NULL                                         AS ReputationTier,
       SUM((SELECT COUNT(*) 
               FROM Comments c 
              WHERE c.UserId = us.Id 
                AND c.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '7 days')
          )                                          AS RecentCommentCount,
       NULL                                         AS MostRecentQuestionDate,
       NULL                                         AS AnswersWithAccepted
FROM   UserStats us
LEFT JOIN RecentVotes rv ON rv.UserId = us.Id
WHERE  us.Reputation > 0
ORDER BY Reputation DESC
LIMIT 100;