-- {"query": "3360.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2021} 

WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Location, 'Unknown') AS Location,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id)                                      AS TotalBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)                     AS GoldBadges,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1)           AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2)           AS AnswerCount,
           (SELECT AVG(p.Score)   FROM Posts p WHERE p.OwnerUserId = u.Id)                         AS AvgPostScore,
           (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id)                    AS LastPostDate
    FROM Users u
    WHERE u.Reputation > 1000
),
TopTags AS (
    SELECT t.TagName,
           t.Count,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),
TagListPerPost AS (
    SELECT pt.Id AS PostId,
           STRING_AGG(tt.TagName, ',') AS TagList
    FROM Posts pt
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(pt.Tags, 2, LENGTH(pt.Tags)-2), '><')) AS Tag
    ) AS tl ON TRUE
    LEFT JOIN Tags tt ON tt.TagName = tl.Tag
    GROUP BY pt.Id
),
RecentVotes AS (
    SELECT v.PostId,
           SUM(CASE WHEN vt.Name = 'UpMod'   THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
           MAX(v.CreationDate)                                 AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId
)
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.Location,
       us.TotalBadges,
       us.GoldBadges,
       us.QuestionCount,
       us.AnswerCount,
       ROUND(us.AvgPostScore::numeric, 2)                               AS AvgScore,
       us.LastPostDate,
       COALESCE(rv.UpVotes, 0)                                           AS RecentUpVotes,
       COALESCE(rv.DownVotes, 0)                                         AS RecentDownVotes,
       CASE
           WHEN us.AnswerCount = 0 THEN NULL
           ELSE (SELECT COUNT(*)
                 FROM Posts p
                 WHERE p.OwnerUserId = us.Id
                   AND p.PostTypeId = 2
                   AND p.AcceptedAnswerId IS NOT NULL) /
                us.AnswerCount::float
       END                                                              AS AcceptedAnswerRatio,
       tl.TagList,
       CASE
           WHEN us.QuestionCount > 0 THEN
               us.QuestionCount -
               (SELECT COUNT(*)
                FROM Posts p
                WHERE p.OwnerUserId = us.Id
                  AND p.PostTypeId = 1
                  AND p.AcceptedAnswerId IS NULL)
           ELSE NULL
       END                                                              AS UnansweredQuestionDelta
FROM UserStats us
LEFT JOIN RecentVotes rv
       ON rv.PostId = (SELECT MAX(p.Id)
                       FROM Posts p
                       WHERE p.OwnerUserId = us.Id)
LEFT JOIN TagListPerPost tl
       ON tl.PostId = (SELECT MAX(p.Id)
                       FROM Posts p
                       WHERE p.OwnerUserId = us.Id)
WHERE EXISTS (SELECT 1
              FROM Posts p
              WHERE p.OwnerUserId = us.Id
                AND p.PostTypeId = 1
                AND p.CreationDate > CURRENT_DATE - INTERVAL '365 days')
UNION ALL
SELECT NULL AS Id,
       '--- Top Tags ---' AS DisplayName,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL,
       STRING_AGG(tt.TagName, ', ') AS TagList,
       NULL
FROM TopTags tt
WHERE tt.rn <= 10
GROUP BY tt.rn
ORDER BY Reputation DESC NULLS LAST, Id ASC
LIMIT 100;
