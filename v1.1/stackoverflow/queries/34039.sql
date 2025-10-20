WITH RecentActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.Location,
           COUNT(DISTINCT p.Id) AS QuestionCount,
           COUNT(DISTINCT a.Id) AS AnswerCount,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           AVG(COALESCE(p.Score, 0)) AS AvgQuestionScore,
           AVG(COALESCE(a.Score, 0)) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate >= DATE '2024-10-01' - INTERVAL '180' DAY
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2 AND a.CreationDate >= DATE '2024-10-01' - INTERVAL '180' DAY
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date >= DATE '2024-10-01' - INTERVAL '180' DAY
    WHERE u.LastAccessDate >= DATE '2024-10-01' - INTERVAL '90' DAY
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT a.Id) > 10
),
TopTags AS (
    SELECT tag AS Tag, COUNT(*) AS UsageCount
    FROM (
        SELECT TRIM(tag) AS tag
        FROM Posts p,
             LATERAL (
               SELECT regexp_split AS tag
               FROM (
                 SELECT regexp_split_to_array(
                          substring(p.Tags FROM 2 FOR (char_length(p.Tags) - 2)), '><'
                        ) AS arr
               ) AS arrtab,
               LATERAL UNNEST(arrtab.arr) AS regexp_split
             ) AS t
        WHERE p.PostTypeId = 1
    ) sub
    GROUP BY tag
    ORDER BY UsageCount DESC
    LIMIT 50
),
UserTagActivity AS (
    SELECT u.Id AS UserId, tag.TagName, COUNT(p.Id) AS PostsCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    JOIN LATERAL (
        SELECT TRIM(tag) AS TagName
        FROM (
          SELECT regexp_split_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags) - 2)), '><') AS arr
        ) AS arrtab,
        LATERAL UNNEST(arrtab.arr) AS tag
    ) tag ON TRUE
    JOIN Tags t ON t.TagName = tag.TagName
    WHERE u.Id IN (SELECT Id FROM RecentActiveUsers)
    GROUP BY u.Id, tag.TagName, t.TagName
),
TopUserTagActivity AS (
    SELECT UserId, TagName, PostsCount,
           RANK() OVER (PARTITION BY UserId ORDER BY PostsCount DESC) AS TagRank
    FROM UserTagActivity
),
UserAnswerStats AS (
    SELECT a.OwnerUserId,
           COUNT(a.Id) AS TotalAnswers,
           AVG(a.Score) AS AvgAnswerScore,
           COUNT(DISTINCT CASE WHEN a.CreationDate >= DATE '2024-10-01' - INTERVAL '30' DAY THEN a.Id END) AS RecentAnswers,
           AVG(COALESCE(vote_counts.UpVotes, 0)) AS AvgUpVotesPerAnswer,
           AVG(COALESCE(vote_counts.DownVotes, 0)) AS AvgDownVotesPerAnswer
    FROM Posts a
    LEFT JOIN (
        SELECT v.PostId,
               SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ) vote_counts ON vote_counts.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
)
SELECT
    rau.Id AS UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.Location,
    rau.QuestionCount,
    rau.AnswerCount,
    rau.BadgeCount,
    rau.AvgQuestionScore,
    rau.AvgAnswerScore,
    uts.TagName AS TopTag,
    uts.PostsCount AS PostsInTag,
    uas.TotalAnswers,
    uas.AvgAnswerScore,
    uas.RecentAnswers,
    COALESCE(uas.AvgUpVotesPerAnswer,0) AS AvgUpVotesPerAnswer,
    COALESCE(uas.AvgDownVotesPerAnswer,0) AS AvgDownVotesPerAnswer
FROM RecentActiveUsers rau
LEFT JOIN TopUserTagActivity uts ON uts.UserId = rau.Id AND uts.TagRank = 1
LEFT JOIN UserAnswerStats uas ON uas.OwnerUserId = rau.Id
ORDER BY rau.Reputation DESC, rau.AnswerCount DESC
LIMIT 100;