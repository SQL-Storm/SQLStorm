-- {"query": "25008.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2069} 
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(DISTINCT q.Id)               AS QuestionCount,
           COUNT(DISTINCT a.Id)               AS AnswerCount,
           COALESCE(SUM(q.Score),0)           AS QuestionScoreSum,
           COALESCE(SUM(a.Score),0)           AS AnswerScoreSum,
           MIN(u.CreationDate)                AS FirstSeen,
           MIN(q.CreationDate) FILTER (WHERE q.Id IS NOT NULL) AS FirstQuestionDate,
           MIN(a.CreationDate) FILTER (WHERE a.Id IS NOT NULL) AS FirstAnswerDate
    FROM   Users u
    LEFT JOIN Posts q
           ON q.OwnerUserId = u.Id AND q.PostTypeId = 1   -- questions
    LEFT JOIN Posts a
           ON a.OwnerUserId = u.Id AND a.PostTypeId = 2   -- answers
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentActivity AS (
    SELECT p.OwnerUserId                                   AS UserId,
           COUNT(*) FILTER (WHERE p.PostTypeId = 1)       AS RecentQuestions,
           COUNT(*) FILTER (WHERE p.PostTypeId = 2)       AS RecentAnswers,
           MAX(p.CreationDate)                           AS LastPostDate
    FROM   Posts p
    WHERE  p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
    GROUP BY p.OwnerUserId
),
BadgeAgg AS (
    SELECT b.UserId,
           STRING_AGG(DISTINCT b.Name, ', ')              AS Badges,
           COUNT(*) FILTER (WHERE b.Class = 1)            AS GoldCount,
           COUNT(*) FILTER (WHERE b.Class = 2)            AS SilverCount,
           COUNT(*) FILTER (WHERE b.Class = 3)            AS BronzeCount
    FROM   Badges b
    GROUP BY b.UserId
),
TagInfo AS (
    SELECT p.OwnerUserId                                   AS UserId,
           STRING_AGG(DISTINCT t.TagName, '|')            AS TagCloud
    FROM   Posts p
    JOIN   LATERAL (
             SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
           ) AS taglist(tag) ON TRUE
    JOIN   Tags t ON t.TagName = taglist.Tag
    WHERE  p.PostTypeId = 1                     -- only questions
      AND  p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserScoreRank AS (
    SELECT us.Id,
           ROW_NUMBER() OVER (ORDER BY (us.QuestionScoreSum + us.AnswerScoreSum) DESC) AS ScoreRank
    FROM   UserStats us
)
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.QuestionCount,
       us.AnswerCount,
       (us.QuestionScoreSum + us.AnswerScoreSum)                 AS TotalScore,
       COALESCE(ra.RecentQuestions,0)                             AS RecentQ,
       COALESCE(ra.RecentAnswers,0)                               AS RecentA,
       COALESCE(ra.LastPostDate, us.FirstSeen)                    AS LastActivity,
       COALESCE(b.Badges,'')                                      AS Badges,
       b.GoldCount,
       b.SilverCount,
       b.BronzeCount,
       COALESCE(t.TagCloud,'')                                    AS TagCloud,
       usr.ScoreRank,
       CASE
           WHEN us.Reputation > 20000 THEN 'Elite'
           WHEN us.Reputation BETWEEN 10000 AND 20000 THEN 'Veteran'
           WHEN us.Reputation BETWEEN 5000  AND 9999  THEN 'Experienced'
           ELSE 'Rising'
       END                                                       AS ReputationTier
FROM   UserStats us
LEFT JOIN RecentActivity ra   ON ra.UserId = us.Id
LEFT JOIN BadgeAgg b          ON b.UserId = us.Id
LEFT JOIN TagInfo t          ON t.UserId = us.Id
LEFT JOIN UserScoreRank usr  ON usr.Id = us.Id
WHERE  (us.QuestionCount > 0 AND us.AnswerCount > 0)      -- active both Q&A
   OR (b.GoldCount > 0 AND us.Reputation IS NOT NULL)    -- gold badge holders
UNION ALL
SELECT NULL,
       'Summary'                                    AS DisplayName,
       NULL,
       SUM(us.QuestionCount)                        AS QuestionCount,
       SUM(us.AnswerCount)                          AS AnswerCount,
       SUM(us.QuestionScoreSum + us.AnswerScoreSum) AS TotalScore,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL,
       NULL
FROM   UserStats us
WHERE  us.Reputation > 10000
ORDER BY ScoreRank NULLS LAST, ReputationTier DESC NULLS LAST;