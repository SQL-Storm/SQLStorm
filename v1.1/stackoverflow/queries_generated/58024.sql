-- {"query": "58024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1285} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(p.Score) AS AvgPostScore,
        STRING_AGG(DISTINCT t.TagName, ', ') AS FrequentTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 2  -- UpMod votes
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1  -- Gold badges
    LEFT JOIN Posts pt ON p.ParentId = pt.Id AND p.PostTypeId = 2
    LEFT JOIN Tags t ON pt.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
LatestBadge AS (
    SELECT 
        UserId,
        Name AS LatestBadgeName,
        Date AS LatestBadgeDate,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Date DESC) AS rn
    FROM Badges
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.CreationDate,
    ua.TotalPosts,
    ua.QuestionsAsked,
    ua.AnswersProvided,
    ua.TotalComments,
    ua.TotalVotes,
    ua.TotalBadges,
    ua.AvgPostScore,
    ua.FrequentTags,
    lb.LatestBadgeName,
    lb.LatestBadgeDate,
    ph.EditCount
FROM UserActivity ua
LEFT JOIN LatestBadge lb ON ua.UserId = lb.UserId AND lb.rn = 1
LEFT JOIN (
    SELECT 
        UserId,
        COUNT(*) AS EditCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (5, 8)  -- Edit Body and Rollback Body
    GROUP BY UserId
) ph ON ua.UserId = ph.UserId
WHERE ua.Reputation > 100000
    AND ua.TotalPosts > 100
    AND ua.AvgPostScore > 50
ORDER BY ua.Reputation DESC, ua.TotalPosts DESC
LIMIT 100;
