-- {"query": "4882.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1458} 

WITH RECURSIVE PostHierarchy AS (
    -- Base case: Select top-level questions
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.OwnerUserId,
        CAST(p.Title AS VARCHAR(1000)) AS Path,
        0 AS Level
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL

    UNION ALL

    -- Recursive step: Select answers to questions
    SELECT
        a.Id AS PostId,
        a.Title,
        a.CreationDate,
        a.Score,
        NULL AS AnswerCount, -- Answers don't have their own answer counts in this context
        a.OwnerUserId,
        CAST(ph.Path || ' -> ' || a.Title AS VARCHAR(1000)),
        ph.Level + 1
    FROM Posts a
    JOIN PostHierarchy ph ON a.ParentId = ph.PostId
    WHERE a.PostTypeId = 2
),
UserPostInteractions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS UpvotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS DownvotesGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(CASE WHEN c.Score > 0 THEN c.Score ELSE 0 END) AS CommentScoreSum,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 3, 4, 5, 6) THEN ph.PostId ELSE NULL END) AS PostEdits,
        MAX(COALESCE(u.Reputation, 0)) OVER (PARTITION BY u.Id) AS MaxReputationForUser
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagCount,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS RankByCount,
        AVG(CAST(p.Score AS DECIMAL(10,2))) OVER (PARTITION BY t.TagName) AS AvgPostScoreForTag
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
),
UserActivity AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS PostsOwned,
        SUM(Score) AS TotalScoreEarned,
        AVG(CAST(Score AS DECIMAL(10,2))) AS AvgScorePerPost,
        COUNT(DISTINCT CASE WHEN ClosedDate IS NOT NULL THEN Id ELSE NULL END) AS ClosedPosts,
        COUNT(DISTINCT CASE WHEN CommunityOwnedDate IS NOT NULL THEN Id ELSE NULL END) AS CommunityOwnedPosts
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1
    GROUP BY OwnerUserId
)
SELECT
    ph.PostId,
    ph.Title AS QuestionTitle,
    ph.Level AS QuestionDepth,
    ph.Score AS QuestionScore,
    ph.AnswerCount AS QuestionAnswerCount,
    u.DisplayName AS QuestionOwner,
    COALESCE(up.UpvotesGiven, 0) AS UpvotesGivenByOwner,
    COALESCE(up.DownvotesGiven, 0) AS DownvotesGivenByOwner,
    COALESCE(up.CommentsMade, 0) AS CommentsMadeByOwner,
    COALESCE(up.CommentScoreSum, 0) AS TotalCommentScoreByOwner,
    COALESCE(up.PostEdits, 0) AS PostEditsByOwner,
    up.MaxReputationForUser AS OwnerMaxReputation,
    ua.PostsOwned AS OwnerTotalPosts,
    ua.TotalScoreEarned AS OwnerTotalScore,
    ua.AvgScorePerPost AS OwnerAvgScore,
    ua.ClosedPosts AS OwnerClosedPosts,
    ua.CommunityOwnedPosts AS OwnerCommunityOwnedPosts,
    tp.TagName,
    tp.TagCount,
    tp.PostsWithTag,
    tp.RankByCount,
    tp.AvgPostScoreForTag,
    CASE
        WHEN ph.Score > 100 AND ph.AnswerCount > 10 THEN 'High Engagement'
        WHEN ph.Score < 0 THEN 'Low Score'
        WHEN ph.AnswerCount = 0 AND ph.Score > 0 THEN 'Unanswered Question'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    CASE
        WHEN u.CreationDate < DATE('now', '-5 years') AND u.Reputation > 10000 THEN 'Veteran High Rep'
        WHEN u.CreationDate > DATE('now', '-1 year') AND u.Reputation < 1000 THEN 'New Low Rep'
        ELSE 'Typical User'
    END AS UserStatusCategory,
    ph.Path AS FullHierarchyPath
FROM PostHierarchy ph
JOIN Users u ON ph.OwnerUserId = u.Id
LEFT JOIN UserPostInteractions up ON u.Id = up.UserId
LEFT JOIN UserActivity ua ON u.Id = ua.OwnerUserId
LEFT JOIN Posts p_tags ON ph.PostId = p_tags.Id -- Join to access tags for questions
LEFT JOIN LATERAL (
    SELECT TagName, TagCount, PostsWithTag, RankByCount, AvgPostScoreForTag
    FROM TagPopularity
    WHERE p_tags.Tags LIKE '%' || TagName || '%'
    ORDER BY TagCount DESC
    LIMIT 1
) tp ON TRUE
WHERE ph.Level < 5 -- Limit recursion depth for performance
  AND LENGTH(ph.Title) > 10
  AND u.DisplayName IS NOT NULL
  AND u.DisplayName <> ''
  AND ph.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
ORDER BY ph.CreationDate DESC
LIMIT 1000;
