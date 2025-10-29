-- {"query": "7889.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2404} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeDesc,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)),
            0
        ) AS TotalVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id),
            0
        ) AS TotalComments,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND EXISTS(SELECT 1 FROM Posts WHERE Id = p.ParentId AND AcceptedAnswerId = p.Id) THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS DaysActive,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN 'High Traffic'
            WHEN p.PostTypeId = 1 AND p.ViewCount > 100 THEN 'Medium Traffic'
            WHEN p.PostTypeId = 1 AND p.ViewCount > 0 THEN 'Low Traffic'
            ELSE 'No Views'
        END AS TrafficLevel,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LAG(p.ViewCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousViews,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PostRank,
        RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
),
TagAnalytics AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsRequired,
        t.IsModeratorOnly,
        REGEXP_REPLACE(t.TagName, '[^a-zA-Z0-9]', '', 'g') AS CleanTagName,
        LENGTH(t.TagName) AS TagLength,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Common'
            WHEN t.Count > 10 THEN 'Uncommon'
            ELSE 'Rare'
        END AS PopularityLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS PopularityRank,
        AVG(t.Count) OVER () AS AvgTagCount
    FROM Tags t
    WHERE t.Count > 0
),
UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.LastAccessDate,
        DATEDIFF(day, u.CreationDate, u.LastAccessDate) AS DaysSinceCreation,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id), 0) AS TotalPosts,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id), 0) AS TotalComments,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId IN (2, 3)), 0) AS TotalVotesGiven,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id), 0) AS TotalBadges,
        CASE 
            WHEN u.Reputation >= 100000 THEN 'Elite'
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ReputationLevel,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    WHERE u.CreationDate >= '2020-01-01'
),
ComprehensiveAnalysis AS (
    SELECT 
        ps.Id AS PostId,
        ps.PostTypeDesc,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.TrafficLevel,
        ps.TotalVotes,
        ps.TotalComments,
        ps.HasAcceptedAnswer,
        ps.DaysActive,
        ps.PostRank,
        ps.ScoreRank,
        ps.ViewRank,
        ps.PreviousScore,
        ps.PreviousViews,
        CASE 
            WHEN ps.PreviousScore > 0 THEN ((ps.Score - ps.PreviousScore) * 100.0 / ps.PreviousScore)
            ELSE 0
        END AS ScoreChangePercent,
        CASE 
            WHEN ps.PreviousViews > 0 THEN ((ps.ViewCount - ps.PreviousViews) * 100.0 / ps.PreviousViews)
            ELSE 0
        END AS ViewChangePercent,
        ta.TagName,
        ta.Count AS TagCount,
        ta.PopularityLevel,
        uas.DisplayName AS AuthorName,
        uas.Reputation,
        uas.TotalPosts,
        uas.TotalComments AS AuthorTotalComments,
        uas.TotalVotesGiven AS AuthorTotalVotes,
        uas.TotalBadges,
        uas.ReputationLevel,
        CASE 
            WHEN ps.Score >= 100 AND ps.ViewCount >= 1000 THEN 'High Impact'
            WHEN ps.Score >= 50 AND ps.ViewCount >= 500 THEN 'Medium Impact'
            WHEN ps.Score >= 10 AND ps.ViewCount >= 100 THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END AS ImpactLevel
    FROM PostStats ps
    LEFT JOIN (
        SELECT 
            p.Id AS PostId,
            unnest(string_to_array(p.Tags, '>')) AS TagName,
            t.Count
        FROM Posts p
        JOIN Tags t ON t.TagName = unnest(string_to_array(p.Tags, '>'))
        WHERE p.Tags IS NOT NULL AND p.Tags != ''
    ) tag_data ON ps.Id = tag_data.PostId
    LEFT JOIN TagAnalytics ta ON ta.TagName = tag_data.TagName
    LEFT JOIN UserActivityStats uas ON ps.OwnerUserId = uas.UserId
)
SELECT 
    ca.PostId,
    ca.PostTypeDesc,
    ca.TagName,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.TrafficLevel,
    ca.ImpactLevel,
    ca.AuthorName,
    ca.Reputation,
    ca.ReputationLevel,
    ca.TotalPosts,
    ca.TotalComments AS AuthorComments,
    ca.TotalVotesGiven,
    ca.TotalBadges,
    ca.ScoreChangePercent,
    ca.ViewChangePercent,
    CASE 
        WHEN ca.ScoreChangePercent > 50 THEN 'Significant Score Growth'
        WHEN ca.ScoreChangePercent > 25 THEN 'Moderate Score Growth'
        WHEN ca.ScoreChangePercent > 0 THEN 'Minor Score Growth'
        WHEN ca.ScoreChangePercent < -50 THEN 'Significant Score Decline'
        WHEN ca.ScoreChangePercent < -25 THEN 'Moderate Score Decline'
        WHEN ca.ScoreChangePercent < 0 THEN 'Minor Score Decline'
        ELSE 'Stable Score'
    END AS ScoreChangeCategory,
    CASE 
        WHEN ca.ViewChangePercent > 50 THEN 'Significant View Growth'
        WHEN ca.ViewChangePercent > 25 THEN 'Moderate View Growth'
        WHEN ca.ViewChangePercent > 0 THEN 'Minor View Growth'
        WHEN ca.ViewChangePercent < -50 THEN 'Significant View Decline'
        WHEN ca.ViewChangePercent < -25 THEN 'Moderate View Decline'
        WHEN ca.ViewChangePercent < 0 THEN 'Minor View Decline'
        ELSE 'Stable Views'
    END AS ViewChangeCategory,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.OwnerUserId AND p.CreationDate >= '2020-01-01') AS PostsByAuthor,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = ca.OwnerUserId AND p.CreationDate >= '2020-01-01') AS AvgScorePerPost,
    (SELECT AVG(p.ViewCount) FROM Posts p WHERE p.OwnerUserId = ca.OwnerUserId AND p.CreationDate >= '2020-01-01') AS AvgViewsPerPost
FROM ComprehensiveAnalysis ca
WHERE ca.Reputation >= 1000
    AND ca.PostTypeDesc = 'Question'
    AND ca.Score > 0
    AND ca.ViewCount > 0
    AND ca.TotalVotes > 0
ORDER BY ca.ViewCount DESC, ca.Score DESC, ca.Reputation DESC
LIMIT 1000
EXCEPT
SELECT 
    ps.Id AS PostId,
    ps.PostTypeDesc,
    'N/A' AS TagName,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.TrafficLevel,
    'Low Impact' AS ImpactLevel,
    'N/A' AS AuthorName,
    0 AS Reputation,
    'Beginner' AS ReputationLevel,
    0 AS TotalPosts,
    0 AS AuthorComments,
    0 AS TotalVotesGiven,
    0 AS TotalBadges,
    0 AS ScoreChangePercent,
    0 AS ViewChangePercent,
    1 AS PostsByAuthor,
    0 AS AvgScorePerPost,
    0 AS AvgViewsPerPost
FROM PostStats ps
WHERE ps.PostTypeDesc = 'Answer'
    AND ps.OwnerUserId IS NULL
    AND ps.Score < 0
UNION ALL
SELECT 
    ps.Id AS PostId,
    ps.PostTypeDesc,
    'N/A' AS TagName,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.TrafficLevel,
    'Low Impact' AS ImpactLevel,
    'N/A' AS AuthorName,
    0 AS Reputation,
    'Beginner' AS ReputationLevel,
    0 AS TotalPosts,
    0 AS AuthorComments,
    0 AS TotalVotesGiven,
    0 AS TotalBadges,
    0 AS ScoreChangePercent,
    0 AS ViewChangePercent,
    1 AS PostsByAuthor,
    0 AS AvgScorePerPost,
    0 AS AvgViewsPerPost
FROM PostStats ps
WHERE ps.PostTypeDesc = 'Question'
    AND ps.OwnerUserId IS NULL
    AND ps.ViewCount IS NULL
    AND ps.Score = 0;