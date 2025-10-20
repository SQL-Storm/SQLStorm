-- {"query": "53076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 710} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation
),
TaggedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, t.TagName ORDER BY p.Score DESC) AS RankInTag
    FROM Posts p
    JOIN Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.PostTypeId = 1 AND p.Score > 10
),
TopTaggedUsers AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalScore,
        ua.AvgViewCount,
        ua.BadgeCount,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        tp.TagName,
        COUNT(tp.PostId) AS PostsInTag,
        MAX(tp.RankInTag) AS BestRankInTag
    FROM UserActivity ua
    JOIN TaggedPosts tp ON ua.UserId = tp.OwnerUserId
    WHERE tp.RankInTag <= 5
    GROUP BY ua.UserId, ua.Reputation, ua.QuestionCount, ua.AnswerCount, ua.TotalScore, ua.AvgViewCount, ua.BadgeCount, ua.UpVotesReceived, ua.DownVotesReceived, tp.TagName
    HAVING COUNT(tp.PostId) > 5
)
SELECT 
    ttu.UserId,
    ttu.Reputation,
    ttu.QuestionCount,
    ttu.AnswerCount,
    ttu.TotalScore,
    ttu.AvgViewCount,
    ttu.BadgeCount,
    ttu.UpVotesReceived,
    ttu.DownVotesReceived,
    ttu.TagName,
    ttu.PostsInTag,
    ttu.BestRankInTag,
    (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ttu.UserId)) AS EditCount,
    (SELECT AVG(c.Score) FROM Comments c JOIN Posts p ON c.PostId = p.Id WHERE p.OwnerUserId = ttu.UserId) AS AvgCommentScore
FROM TopTaggedUsers ttu
WHERE ttu.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 100)
ORDER BY ttu.TotalScore DESC, ttu.PostsInTag DESC
LIMIT 100;