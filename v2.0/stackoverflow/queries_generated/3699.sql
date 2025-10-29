-- {"query": "3699.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2302} 

WITH UserBadgeCounts AS (
    SELECT u.Id AS UserId,
           COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
           COUNT(b.Id)                                 AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
UserPostStats AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(*) FILTER (WHERE p.PostTypeId = 1)                     AS Questions,
           COUNT(*) FILTER (WHERE p.PostTypeId = 2)                     AS Answers,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)                 AS AvgQuestionScore,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)                 AS AvgAnswerScore,
           SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1)             AS TotalQuestionViews,
           MAX(p.CreationDate)                                         AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserTagActivity AS (
    SELECT u.Id                         AS UserId,
           t.TagName,
           COUNT(*)                     AS TagUsage,
           ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
               AND p.PostTypeId = 1
               AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(trim(both '<>' FROM p.Tags), '><') AS TagName
    ) t
    JOIN Tags tag ON tag.TagName = t.TagName
    GROUP BY u.Id, t.TagName
),
RecentVotes AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE vt.Id = 2) AS UpVotesGiven,
           COUNT(*) FILTER (WHERE vt.Id = 3) AS DownVotesGiven,
           COUNT(*) FILTER (WHERE vt.Id = 8) AS BountiesStarted,
           MAX(v.CreationDate)               AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT u.Id,
       u.DisplayName,
       u.Reputation,
       COALESCE(ubc.GoldBadges,0)   AS GoldBadges,
       COALESCE(ubc.SilverBadges,0) AS SilverBadges,
       COALESCE(ubc.BronzeBadges,0) AS BronzeBadges,
       COALESCE(up.Questions,0)      AS QuestionCount,
       COALESCE(up.Answers,0)        AS AnswerCount,
       ROUND(COALESCE(up.AvgQuestionScore,0),2) AS AvgQScore,
       ROUND(COALESCE(up.AvgAnswerScore,0),2)   AS AvgAScore,
       COALESCE(up.TotalQuestionViews,0)        AS QuestionViews,
       up.LastPostDate,
       COALESCE(rv.UpVotesGiven,0)   AS UpVotesGiven,
       COALESCE(rv.DownVotesGiven,0) AS DownVotesGiven,
       COALESCE(rv.BountiesStarted,0) AS BountiesStarted,
       rv.LastVoteDate,
       STRING_AGG(uta.TagName || ':' || uta.TagUsage, ', ')
                FILTER (WHERE uta.TagRank <= 3)   AS Top3Tags
FROM Users u
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
LEFT JOIN UserPostStats up    ON up.UserId = u.Id
LEFT JOIN RecentVotes rv     ON rv.UserId = u.Id
LEFT JOIN UserTagActivity uta ON uta.UserId = u.Id
WHERE u.Reputation > 1000
  AND (u.Location IS NULL OR u.Location NOT ILIKE '%spam%')
GROUP BY u.Id, u.DisplayName, u.Reputation,
         ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges,
         up.Questions, up.Answers, up.AvgQuestionScore, up.AvgAnswerScore,
         up.TotalQuestionViews, up.LastPostDate,
         rv.UpVotesGiven, rv.DownVotesGiven, rv.BountiesStarted, rv.LastVoteDate
HAVING COUNT(*) FILTER (WHERE ubc.TotalBadges IS NOT NULL) > 0

UNION ALL

SELECT u.Id,
       u.DisplayName,
       u.Reputation,
       0,0,0,
       0,0,0,0,0,NULL,
       0,0,0,NULL,
       NULL
FROM Users u
WHERE u.Reputation BETWEEN 0 AND 100
  AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY Reputation DESC
LIMIT 100;
