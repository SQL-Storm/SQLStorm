-- {"query": "53056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 808} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
TagEngagement AS (
    SELECT 
        p.OwnerUserId AS UserId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostsInTag,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(DISTINCT p.Id) DESC) AS TagRank
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    JOIN Tags t ON t.TagName = tag
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId, t.TagName
),
CommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.UserId
),
PostHistoryEdits AS (
    SELECT 
        ph.UserId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.UserId
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ua.AvgViewCount,
    ua.VoteCount,
    ua.Upvotes,
    ua.Downvotes,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.LatestBadgeDate,
    te.TagName AS TopTag,
    te.PostsInTag AS TopTagPosts,
    ca.CommentCount,
    ca.AvgCommentScore,
    phe.EditCount,
    phe.LastEditDate,
    RANK() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank,
    PERCENT_RANK() OVER (ORDER BY ua.TotalScore) AS ScorePercentile
FROM UserActivity ua
LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN (SELECT * FROM TagEngagement WHERE TagRank = 1) te ON ua.UserId = te.UserId
LEFT JOIN CommentActivity ca ON ua.UserId = ca.UserId
LEFT JOIN PostHistoryEdits phe ON ua.UserId = phe.UserId
WHERE ua.QuestionCount + ua.AnswerCount > 10
ORDER BY ua.Reputation DESC
LIMIT 1000;
