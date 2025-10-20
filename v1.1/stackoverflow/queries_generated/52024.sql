-- {"query": "52024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 786} 
WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(DISTINCT v.Id) AS TotalVotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserComments AS (
    SELECT 
        UserId,
        COUNT(*) AS CommentCount,
        AVG(Score) AS AvgCommentScore
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
TopTags AS (
    SELECT 
        um.Id AS UserId,
        t.TagName,
        COUNT(*) AS TagUsage
    FROM UserMetrics um
    JOIN Posts p ON p.OwnerUserId = um.Id AND p.PostTypeId = 1
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
    JOIN Tags t ON t.TagName = t.TagName
    GROUP BY um.Id, t.TagName
),
TopTagPerUser AS (
    SELECT 
        UserId,
        TagName AS MostUsedTag,
        TagUsage,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsage DESC) AS rn
    FROM TopTags
)
SELECT 
    um.Id,
    um.DisplayName,
    um.Reputation,
    um.CreationDate,
    um.LastAccessDate,
    um.QuestionCount,
    um.AnswerCount,
    um.TotalPostScore,
    um.TotalViews,
    um.TotalBadges,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    um.TotalVotesReceived,
    um.UpvotesReceived,
    um.DownvotesReceived,
    uc.CommentCount,
    uc.AvgCommentScore,
    ttu.MostUsedTag,
    ttu.TagUsage AS MostUsedTagCount,
    (um.Reputation * 0.5 + um.TotalPostScore * 0.3 + um.TotalViews * 0.1 + um.TotalBadges * 10 + um.GoldBadges * 100 + uc.CommentCount * 0.01) AS CompositeScore
FROM UserMetrics um
LEFT JOIN UserComments uc ON uc.UserId = um.Id
LEFT JOIN TopTagPerUser ttu ON ttu.UserId = um.Id AND ttu.rn = 1
ORDER BY CompositeScore DESC
LIMIT 100;