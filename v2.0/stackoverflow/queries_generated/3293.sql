-- {"query": "3293.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2473} 

WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Location, 'Unknown')               AS Location,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           SUM(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId = 1) AS QuestionScoreSum,
           SUM(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId = 2) AS AnswerScoreSum,
           COUNT(b.Id)                                 AS BadgeCount,
           SUM(CASE b.Class WHEN 1 THEN 3 WHEN 2 THEN 2 ELSE 1 END) AS BadgeWeight,
           MAX(p.CreationDate)                         AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b  ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
UserActivity AS (
    SELECT u.Id,
           COUNT(v.Id)                                 AS VoteGiven,
           COUNT(c.Id)                                 AS CommentGiven,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
           MAX(v.CreationDate)                         AS LastVoteDate
    FROM Users u
    LEFT JOIN Votes    v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
TopTagUsage AS (
    SELECT p.OwnerUserId                              AS UserId,
           unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag,
           COUNT(*)                                   AS TagUseCount
    FROM Posts p
    WHERE p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),
UserTagRank AS (
    SELECT t.UserId,
           t.Tag,
           t.TagUseCount,
           ROW_NUMBER() OVER (PARTITION BY t.UserId ORDER BY t.TagUseCount DESC) AS TagRank
    FROM TopTagUsage t
),
Combined AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.QuestionCount,
           us.AnswerCount,
           us.QuestionScoreSum,
           us.AnswerScoreSum,
           us.BadgeCount,
           us.BadgeWeight,
           ua.VoteGiven,
           ua.CommentGiven,
           ua.UpVotesGiven,
           ua.DownVotesGiven,
           COALESCE(ut.Tag, 'NoTag')                 AS TopTag,
           COALESCE(ut.TagUseCount,0)                AS TopTagUse,
           CASE
               WHEN us.Reputation > 20000 THEN 'Elite'
               WHEN us.Reputation BETWEEN 10000 AND 20000 THEN 'Pro'
               WHEN us.Reputation BETWEEN 5000  AND 9999  THEN 'Intermediate'
               ELSE 'Novice'
           END                                      AS ReputationBand,
           CASE
               WHEN us.BadgeWeight > 100 THEN 1
               WHEN us.BadgeWeight BETWEEN 50 AND 100 THEN 2
               ELSE 3
           END                                      AS BadgeTier,
           GREATEST(us.LastPostDate, ua.LastVoteDate) AS LastActivity
    FROM UserStats us
    LEFT JOIN UserActivity ua ON ua.Id = us.Id
    LEFT JOIN (
        SELECT UserId, Tag, TagUseCount
        FROM UserTagRank
        WHERE TagRank = 1
    ) ut ON ut.UserId = us.Id
)
SELECT *
FROM Combined
WHERE (Combined.QuestionCount + Combined.AnswerCount) > 0
  AND (Combined.ReputationBand = 'Elite' OR Combined.BadgeTier = 1)
ORDER BY Combined.BadgeWeight DESC, Combined.Reputation DESC
LIMIT 100

UNION ALL

SELECT
       NULL                                            AS Id,
       'Aggregate Summary'                             AS DisplayName,
       NULL                                            AS Reputation,
       SUM(QuestionCount)                              AS QuestionCount,
       SUM(AnswerCount)                                AS AnswerCount,
       SUM(QuestionScoreSum)                           AS QuestionScoreSum,
       SUM(AnswerScoreSum)                             AS AnswerScoreSum,
       SUM(BadgeCount)                                 AS BadgeCount,
       SUM(BadgeWeight)                                AS BadgeWeight,
       SUM(VoteGiven)                                  AS VoteGiven,
       SUM(CommentGiven)                               AS CommentGiven,
       SUM(UpVotesGiven)                               AS UpVotesGiven,
       SUM(DownVotesGiven)                             AS DownVotesGiven,
       NULL                                            AS TopTag,
       NULL                                            AS TopTagUse,
       NULL                                            AS ReputationBand,
       NULL                                            AS BadgeTier,
       MAX(LastActivity)                               AS LastActivity
FROM Combined
WHERE Combined.Id IS NOT NULL

INTERSECT

SELECT *
FROM (
    SELECT Id, DisplayName, Reputation, QuestionCount, AnswerCount,
           QuestionScoreSum, AnswerScoreSum, BadgeCount, BadgeWeight,
           VoteGiven, CommentGiven, UpVotesGiven, DownVotesGiven,
           TopTag, TopTagUse, ReputationBand, BadgeTier, LastActivity
    FROM Combined
    WHERE ReputationBand = 'Pro' AND BadgeTier = 2
) AS sub

EXCEPT

SELECT *
FROM Combined
WHERE ReputationBand = 'Novice' AND BadgeWeight < 10;
