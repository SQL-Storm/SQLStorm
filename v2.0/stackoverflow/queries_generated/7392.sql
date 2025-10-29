-- {"query": "7392.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2056} 
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COALESCE(p.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        NTILE(100) OVER (ORDER BY p.ViewCount DESC) AS ViewPercentile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate DESC) AS PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate DESC) AS NextScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate > '2020-01-01 00:00:00'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        CASE 
            WHEN COUNT(p.Id) = 0 THEN 'Inactive'
            WHEN COUNT(p.Id) BETWEEN 1 AND 10 THEN 'Newbie'
            WHEN COUNT(p.Id) BETWEEN 11 AND 50 THEN 'Regular'
            WHEN COUNT(p.Id) > 50 THEN 'Veteran'
        END AS UserCategory,
        STRING_AGG(CAST(p.Id AS VARCHAR), ',') AS PostIds,
        STRING_AGG(p.Title, ' | ') AS PostTitles
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > '2019-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Rare'
            ELSE 'Average'
        END AS TagPopularity,
        CASE 
            WHEN t.Count >= 1000 THEN 'Trending'
            WHEN t.Count < 100 THEN 'Niche'
            ELSE 'Standard'
        END AS TagLevel,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE Posts.Tags LIKE '%' || t.TagName || '%'), 0) AS PostsWithTag
    FROM Tags t
),
ComplexMetrics AS (
    SELECT 
        ps.PostId,
        ps.PostTypeId,
        ps.OwnerDisplayName,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.PostType,
        ps.PostStatus,
        ps.ScoreRank,
        ps.ViewPercentile,
        ps.HasAcceptedAnswer,
        CASE 
            WHEN ps.Score > 100 THEN 'High Impact'
            WHEN ps.Score > 10 THEN 'Medium Impact'
            WHEN ps.Score > 0 THEN 'Low Impact'
            ELSE 'No Impact'
        END AS ImpactLevel,
        CASE 
            WHEN ps.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'High Traffic'
            WHEN ps.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) * 0.5 THEN 'Medium Traffic'
            ELSE 'Low Traffic'
        END AS TrafficLevel,
        CASE 
            WHEN ps.AnswerCount > ps.CommentCount THEN 'More Answers Than Comments'
            WHEN ps.AnswerCount < ps.CommentCount THEN 'More Comments Than Answers'
            ELSE 'Equal Answers and Comments'
        END AS AnswerCommentsRatio,
        COALESCE(ROUND((ps.AnswerCount::DECIMAL / NULLIF(ps.CommentCount, 0)) * 100, 2), 0) AS AnswerCommentRatioPercentage,
        COALESCE(ROUND((ps.Score::DECIMAL / NULLIF(ps.ViewCount, 0)) * 1000, 2), 0) AS ScorePerThousandViews,
        CAST(COUNT(*) OVER (PARTITION BY ps.OwnerDisplayName) AS VARCHAR) AS TotalPostsByOwner,
        STRING_AGG(ps.Title, ' || ') OVER (PARTITION BY ps.OwnerDisplayName ORDER BY ps.CreationDate DESC ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RecentTitles
    FROM PostStats ps
)
SELECT 
    cm.PostId,
    cm.OwnerDisplayName,
    cm.Score,
    cm.ViewCount,
    cm.AnswerCount,
    cm.CommentCount,
    cm.FavoriteCount,
    cm.PostType,
    cm.PostStatus,
    cm.ScoreRank,
    cm.ViewPercentile,
    cm.ImpactLevel,
    cm.TrafficLevel,
    cm.AnswerCommentsRatio,
    cm.AnswerCommentRatioPercentage,
    cm.ScorePerThousandViews,
    cm.TotalPostsByOwner,
    u.UserCategory,
    u.PostCount,
    u.CommentCount AS UserCommentCount,
    u.BadgeCount,
    u.TotalScore,
    u.AvgScore,
    ta.TagName,
    ta.Count AS TagCount,
    ta.TagPopularity,
    ta.TagLevel,
    CASE 
        WHEN cm.PostStatus = 'Closed' AND cm.Score < 0 THEN 'Negative Closed Post'
        WHEN cm.PostStatus = 'Closed' AND cm.Score >= 0 THEN 'Positive Closed Post'
        WHEN cm.PostStatus = 'Open' AND cm.Score < 0 THEN 'Negative Open Post'
        WHEN cm.PostStatus = 'Open' AND cm.Score >= 0 THEN 'Positive Open Post'
        ELSE 'Unknown'
    END AS PostStatusImpact,
    CASE 
        WHEN cm.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg Score'
        WHEN cm.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Avg Score'
        ELSE 'Avg Score'
    END AS ScoreComparison,
    CASE 
        WHEN cm.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) * 2 THEN 'Very High Views'
        WHEN cm.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'High Views'
        WHEN cm.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) * 0.5 THEN 'Medium Views'
        ELSE 'Low Views'
    END AS ViewCategory,
    COALESCE(
        CASE 
            WHEN cm.Score > 0 THEN 'Good'
            WHEN cm.Score < 0 THEN 'Bad'
            ELSE 'Neutral'
        END,
        'Unknown'
    ) AS ScoreRating,
    COALESCE(REPLACE(cm.RecentTitles, ' || ', ', '), 'No Recent Titles') AS RecentPostsTitles
FROM ComplexMetrics cm
JOIN UserActivity u ON cm.OwnerDisplayName = u.DisplayName
LEFT JOIN (
    SELECT 
        p.Id,
        t.TagName,
        t.Count
    FROM Posts p
    JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
) ta ON cm.PostId = ta.Id
WHERE 
    cm.Score >= 0 
    AND cm.ViewCount >= 10
    AND cm.AnswerCount >= 0
    AND cm.CommentCount >= 0
    AND cm.FavoriteCount >= 0
    AND u.Reputation >= 1000
    AND u.PostCount >= 10
    AND u.BadgeCount >= 5
    AND ta.TagName IS NOT NULL
    AND (cm.PostStatus = 'Open' OR cm.PostStatus = 'Closed')
    AND cm.ScoreRank <= 1000
    AND cm.ViewPercentile <= 95
    AND EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.OwnerUserId = (
            SELECT Id 
            FROM Users 
            WHERE DisplayName = cm.OwnerDisplayName
        ) 
        AND p2.CreationDate > '2020-01-01 00:00:00'
    )
    AND (
        cm.AnswerCommentRatioPercentage > 50 
        OR cm.AnswerCommentRatioPercentage < 50
        OR cm.ScorePerThousandViews > 20
    )
ORDER BY cm.Score DESC, cm.ViewCount DESC, cm.PostId ASC
LIMIT 10000;