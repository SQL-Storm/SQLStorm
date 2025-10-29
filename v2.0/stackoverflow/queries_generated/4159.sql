-- {"query": "4159.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1249} 
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) AS RankByReputationAndPostCount,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
        AVG(c.Score) AS AverageCommentScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId AND p.Id = c.PostId
    WHERE u.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10 OR COUNT(DISTINCT c.Id) > 50
),
TagPopularity AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS TaggedPostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TaggedQuestionCount,
        AVG(p.Score) AS AverageTaggedQuestionScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON ',' || REPLACE(p.Tags, '><', ',') || ',' LIKE '%,' || t.TagName || ',%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 1000
),
HighEngagementPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        CASE
            WHEN p.Score > 50 THEN 'Very High'
            WHEN p.Score > 10 THEN 'High'
            ELSE 'Medium'
        END AS EngagementLevel,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS PostActivityRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.CommunityOwnedDate IS NULL
),
UserPostSummary AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.PostCount,
        rua.AveragePostScore,
        COALESCE(hep.PostId, -1) AS TopPostId,
        COALESCE(hep.Title, 'No High Engagement Posts') AS TopPostTitle,
        COALESCE(hep.Score, 0) AS TopPostScore,
        COALESCE(hep.EngagementLevel, 'N/A') AS TopPostEngagement
    FROM RankedUserActivity rua
    LEFT JOIN HighEngagementPosts hep ON rua.UserId = hep.OwnerUserId AND hep.PostActivityRank = 1
    WHERE rua.RankByReputationAndPostCount <= 100
)
SELECT
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.PostCount,
    ups.AveragePostScore,
    ups.TopPostId,
    ups.TopPostTitle,
    ups.TopPostScore,
    ups.TopPostEngagement,
    tp.TagName,
    tp.TaggedPostCount,
    tp.AverageTaggedQuestionScore,
    CASE
        WHEN ups.Reputation >= 100000 AND tp.TagRank <= 5 THEN 'Elite User & Popular Tag'
        WHEN ups.Reputation >= 50000 THEN 'High Reputation User'
        WHEN tp.TagRank <= 10 THEN 'Popular Tag Contributor'
        ELSE 'Standard User'
    END AS UserCategory
FROM UserPostSummary ups
LEFT JOIN TagPopularity tp
    ON EXISTS (
        SELECT 1
        FROM Posts p_inner
        JOIN Tags t_inner ON ',' || REPLACE(p_inner.Tags, '><', ',') || ',' LIKE '%,' || t_inner.TagName || ',%'
        WHERE p_inner.OwnerUserId = ups.UserId AND t_inner.TagName = tp.TagName
    )
WHERE ups.Reputation > 1000 OR ups.PostCount > 500
UNION
SELECT
    NULL,
    'Community User',
    0,
    COUNT(p.Id),
    AVG(p.Score),
    MAX(p.Id),
    MAX(p.Title),
    MAX(p.Score),
    'N/A',
    'N/A',
    COUNT(p.Id),
    AVG(p.Score),
    'Community Driven'
FROM Posts p
WHERE p.OwnerUserId = -1 AND p.CreationDate BETWEEN '2021-01-01' AND '2023-12-31'
ORDER BY Reputation DESC NULLS LAST, TagRank NULLS LAST;