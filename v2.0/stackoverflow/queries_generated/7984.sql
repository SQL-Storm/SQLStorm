-- {"query": "7984.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2604} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COALESCE(p.OwnerDisplayName, 'Anonymous') AS DisplayName,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) AS AgeInDays,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END AS VoteCategory,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsByUser,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN ARRAY_LENGTH(string_to_array(p.Tags, '><'), 1)
            ELSE 0
        END AS TagCount
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
),
UserActivity AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        MAX(p.CreationDate) AS LatestActivity,
        DATEDIFF(day, u.CreationDate, CURRENT_TIMESTAMP) AS AccountAgeInDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            WHEN u.Reputation >= 100 THEN 'Beginner'
            ELSE 'Newbie'
        END AS RepLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.IsRequired,
        t.IsModeratorOnly,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END AS PopularityLevel,
        RANK() OVER (ORDER BY t.Count DESC) AS PopularityRank,
        AVG(t.Count) OVER () AS AvgTagCount,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) AS PreviousTagCount,
        LEAD(t.Count) OVER (ORDER BY t.Count DESC) AS NextTagCount
    FROM Tags t
    WHERE t.Count > 0
),
ComplexPostAnalysis AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.Title,
        ps.Tags,
        ps.Body,
        ps.PostType,
        ps.DisplayName,
        ps.AgeInDays,
        ps.VoteCategory,
        ps.ScoreRank,
        ps.ViewRank,
        ps.PreviousScore,
        ps.NextScore,
        ps.AvgUserScore,
        ps.TotalPostsByUser,
        ps.TagCount,
        CASE 
            WHEN ps.AnswerCount > 10 THEN 'HighlyAnswered'
            WHEN ps.AnswerCount > 5 THEN 'ModeratelyAnswered'
            WHEN ps.AnswerCount > 0 THEN 'SparinglyAnswered'
            ELSE 'Unanswered'
        END AS AnswerStatus,
        CASE 
            WHEN ps.CommentCount > 20 THEN 'HighlyCommented'
            WHEN ps.CommentCount > 10 THEN 'ModeratelyCommented'
            WHEN ps.CommentCount > 0 THEN 'SparinglyCommented'
            ELSE 'NoComments'
        END AS CommentStatus,
        CASE 
            WHEN ps.FavoriteCount > 100 THEN 'HighlyFavorited'
            WHEN ps.FavoriteCount > 50 THEN 'ModeratelyFavorited'
            WHEN ps.FavoriteCount > 0 THEN 'SparinglyFavorited'
            ELSE 'NotFavorited'
        END AS FavoriteStatus,
        CASE 
            WHEN ps.AgeInDays < 30 THEN 'New'
            WHEN ps.AgeInDays < 365 THEN 'Recent'
            WHEN ps.AgeInDays < 730 THEN 'Established'
            ELSE 'Legacy'
        END AS PostAgeCategory,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.PostId = ps.Id 
             AND c.CreationDate >= ps.CreationDate),
            0
        ) AS CommentCountSincePost,
        COALESCE(
            (SELECT COUNT(*)
             FROM Votes v 
             WHERE v.PostId = ps.Id 
             AND v.VoteTypeId IN (1, 2, 3)),
            0
        ) AS VoteCountSincePost,
        EXISTS (
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.PostId = ps.Id 
            AND ph.PostHistoryTypeId = 10 
            AND ph.CreationDate >= ps.CreationDate
        ) AS IsClosed,
        EXISTS (
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.PostId = ps.Id 
            AND ph.PostHistoryTypeId IN (12, 13) 
            AND ph.CreationDate >= ps.CreationDate
        ) AS IsDeleted,
        COALESCE(
            (SELECT MAX(p.Score) 
             FROM Posts p 
             WHERE p.ParentId = ps.Id 
             AND p.PostTypeId = 2),
            0
        ) AS MaxAnswerScore,
        (
            SELECT STRING_AGG(DISTINCT u.DisplayName, ', ')
            FROM Users u 
            INNER JOIN Votes v ON u.Id = v.UserId 
            WHERE v.PostId = ps.Id 
            AND v.VoteTypeId = 1
        ) AS AcceptingUsers
    FROM PostStats ps
    WHERE ps.Score > 0 
    AND ps.AnswerCount IS NOT NULL
),
FinalAggregation AS (
    SELECT 
        cpa.Id,
        cpa.PostTypeId,
        cpa.Score,
        cpa.ViewCount,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.FavoriteCount,
        cpa.CreationDate,
        cpa.OwnerUserId,
        cpa.Title,
        cpa.Tags,
        cpa.Body,
        cpa.PostType,
        cpa.DisplayName,
        cpa.AgeInDays,
        cpa.VoteCategory,
        cpa.ScoreRank,
        cpa.ViewRank,
        cpa.PreviousScore,
        cpa.NextScore,
        cpa.AvgUserScore,
        cpa.TotalPostsByUser,
        cpa.TagCount,
        cpa.AnswerStatus,
        cpa.CommentStatus,
        cpa.FavoriteStatus,
        cpa.PostAgeCategory,
        cpa.CommentCountSincePost,
        cpa.VoteCountSincePost,
        cpa.IsClosed,
        cpa.IsDeleted,
        cpa.MaxAnswerScore,
        cpa.AcceptingUsers,
        ua.Reputation,
        ua.TotalPosts,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.TotalScore,
        ua.LatestActivity,
        ua.AccountAgeInDays,
        ua.RepLevel,
        ta.TagName,
        ta.Count AS TagCountInTag,
        ta.PopularityLevel,
        ta.PopularityRank,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.Tags LIKE '%' || ta.TagName || '%' 
         AND p.CreationDate >= '2020-01-01') AS RelatedPostsCount,
        CASE 
            WHEN (cpa.Score * 1.0 / NULLIF(cpa.ViewCount, 0)) > 0.05 THEN 'HighEngagement'
            WHEN (cpa.Score * 1.0 / NULLIF(cpa.ViewCount, 0)) > 0.01 THEN 'ModerateEngagement'
            ELSE 'LowEngagement'
        END AS EngagementLevel,
        CASE 
            WHEN cpa.Score > 2 * NULLIF(cpa.AvgUserScore, 0) THEN 'AboveAverage'
            WHEN cpa.Score < 0.5 * NULLIF(cpa.AvgUserScore, 0) THEN 'BelowAverage'
            ELSE 'Average'
        END AS ScoreComparison,
        ROW_NUMBER() OVER (ORDER BY cpa.Score DESC * cpa.ViewCount DESC) AS OverallRank,
        PERCENT_RANK() OVER (ORDER BY cpa.ViewCount DESC) AS ViewPercentile
    FROM ComplexPostAnalysis cpa
    INNER JOIN UserActivity ua ON cpa.OwnerUserId = ua.Id
    LEFT JOIN TagAnalysis ta ON cpa.Tags LIKE '%' || ta.TagName || '%'
    WHERE cpa.Score > 0
)
SELECT 
    fa.Id,
    fa.PostTypeId,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.CreationDate,
    fa.OwnerUserId,
    fa.Title,
    fa.Tags,
    fa.Body,
    fa.PostType,
    fa.DisplayName,
    fa.AgeInDays,
    fa.VoteCategory,
    fa.ScoreRank,
    fa.ViewRank,
    fa.PreviousScore,
    fa.NextScore,
    fa.AvgUserScore,
    fa.TotalPostsByUser,
    fa.TagCount,
    fa.AnswerStatus,
    fa.CommentStatus,
    fa.FavoriteStatus,
    fa.PostAgeCategory,
    fa.CommentCountSincePost,
    fa.VoteCountSincePost,
    fa.IsClosed,
    fa.IsDeleted,
    fa.MaxAnswerScore,
    fa.AcceptingUsers,
    fa.Reputation,
    fa.TotalPosts,
    fa.TotalQuestions,
    fa.TotalAnswers,
    fa.TotalScore,
    fa.LatestActivity,
    fa.AccountAgeInDays,
    fa.RepLevel,
    fa.TagName,
    fa.TagCountInTag,
    fa.PopularityLevel,
    fa.PopularityRank,
    fa.RelatedPostsCount,
    fa.EngagementLevel,
    fa.ScoreComparison,
    fa.OverallRank,
    fa.ViewPercentile,
    CASE 
        WHEN fa.IsClosed = 1 AND fa.IsDeleted = 0 THEN 'Closed'
        WHEN fa.IsDeleted = 1 THEN 'Deleted'
        WHEN fa.IsClosed = 1 THEN 'Closed'
        ELSE 'Active'
    END AS PostStatus,
    COALESCE(fa.TagCountInTag, 0) + COALESCE(fa.RelatedPostsCount, 0) AS AggregateTagMetrics
FROM FinalAggregation fa
WHERE fa.ViewCount > 100 
AND (fa.PopularityLevel = 'Popular' OR fa.PopularityLevel = 'Moderate')
AND fa.AccountAgeInDays > 365
AND (fa.RepLevel = 'Expert' OR fa.RepLevel = 'Intermediate')
AND fa.VoteCountSincePost > 0
AND fa.Score > 10
AND fa.ViewPercentile > 0.1
ORDER BY fa.ViewCount DESC, fa.Score DESC
LIMIT 1000 OFFSET 1000;