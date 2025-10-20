-- {"query": "34039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 922} 
WITH RecentActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.Location,
           COUNT(DISTINCT p.Id) AS QuestionCount,
           COUNT(DISTINCT a.Id) AS AnswerCount,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           AVG(COALESCE(p.Score, 0)) AS AvgQuestionScore,
           AVG(COALESCE(a.Score, 0)) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '180 days'
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2 AND a.CreationDate >= cast('2024-10-01' as date) - INTERVAL '180 days'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date >= cast('2024-10-01' as date) - INTERVAL '180 days'
    WHERE u.LastAccessDate >= cast('2024-10-01' as date) - INTERVAL '90 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT a.Id) > 10
),
TopTags AS (
    SELECT unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) AS Tag, COUNT(*) AS UsageCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY Tag
    ORDER BY UsageCount DESC
    LIMIT 50
),
UserTagActivity AS (
    SELECT u.Id AS UserId, t.TagName, COUNT(p.Id) AS PostsCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    JOIN LATERAL unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) AS tag(TagName) ON TRUE
    JOIN Tags t ON t.TagName = tag.TagName
    WHERE u.Id IN (SELECT Id FROM RecentActiveUsers)
    GROUP BY u.Id, t.TagName
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
           COUNT(DISTINCT CASE WHEN a.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days' THEN a.Id END) AS RecentAnswers,
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