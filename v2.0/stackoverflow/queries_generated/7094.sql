-- {"query": "7094.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2097} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreDenseRank,
        NTILE(100) OVER (ORDER BY p.Score DESC) as ScoreNtile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingAvgScore,
        COUNT(*) OVER () as TotalPosts,
        MAX(p.Score) OVER () as MaxScore,
        MIN(p.Score) OVER () as MinScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TagAnalytics AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'High'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Low'
            ELSE 'Average'
        END as TagCategory,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        PERCENT_RANK() OVER (ORDER BY t.Count) as TagPercentRank
    FROM Tags t
),
UserActivity AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        CASE 
            WHEN u.Reputation > 100000 THEN 'Elite'
            WHEN u.Reputation > 10000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Expert'
            WHEN u.Reputation > 100 THEN 'Contributor'
            ELSE 'Newbie'
        END as ReputationTier,
        DATEDIFF(CURRENT_DATE, u.CreationDate) as DaysSinceRegistration,
        RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId, u.CreationDate
),
ComplexQueryResult AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        ptt.Name as PostTypeName,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        rp.CreationDate,
        rp.LastActivityDate,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ScoreRank,
        rp.ScoreDenseRank,
        rp.ScoreNtile,
        CASE 
            WHEN rp.PreviousScore IS NULL THEN 'First Post'
            WHEN rp.PreviousScore < rp.Score THEN 'Score Increased'
            WHEN rp.PreviousScore > rp.Score THEN 'Score Decreased'
            ELSE 'Score Unchanged'
        END as ScoreChangeStatus,
        rp.MovingAvgScore,
        rp.TotalPosts,
        rp.MaxScore,
        rp.MinScore,
        ta.TagName,
        ta.TagCount,
        ta.TagCategory,
        ta.TagRank,
        ta.TagPercentRank,
        ua.ReputationTier,
        ua.PostCount,
        ua.BadgeCount,
        ua.CommentCount,
        ua.DaysSinceRegistration,
        ua.ReputationRank,
        CASE 
            WHEN rp.Score >= 100 AND rp.AnswerCount >= 5 THEN 'Highly Engaged'
            WHEN rp.Score >= 50 AND rp.AnswerCount >= 2 THEN 'Engaged'
            WHEN rp.Score >= 10 THEN 'Regular'
            ELSE 'Occasional'
        END as EngagementLevel,
        UPPER(SUBSTRING(rp.Title, 1, 1)) || LOWER(SUBSTRING(rp.Title, 2)) as FormattedTitle,
        COALESCE(rp.Title, 'No Title') as TitleOrPlaceholder
    FROM RankedPosts rp
    JOIN PostTypes ptt ON rp.PostTypeId = ptt.Id
    JOIN Users u ON rp.OwnerUserId = u.Id
    LEFT JOIN TagAnalytics ta ON EXISTS (
        SELECT 1 FROM STRING_TO_ARRAY(rp.Tags, '>') t 
        WHERE t = '#' || ta.TagName
    )
    JOIN UserActivity ua ON rp.OwnerUserId = ua.Id
    WHERE rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
    AND rp.LastActivityDate >= DATEADD(YEAR, -1, CURRENT_DATE)
    AND (rp.PostTypeId = 1 OR rp.PostTypeId = 2)
)
SELECT 
    cr.Id,
    cr.PostTypeId,
    cr.PostTypeName,
    cr.Score,
    cr.ViewCount,
    cr.Title,
    cr.Tags,
    cr.OwnerUserId,
    cr.OwnerDisplayName,
    cr.OwnerReputation,
    cr.CreationDate,
    cr.LastActivityDate,
    cr.AnswerCount,
    cr.CommentCount,
    cr.FavoriteCount,
    cr.ScoreRank,
    cr.ScoreDenseRank,
    cr.ScoreNtile,
    cr.ScoreChangeStatus,
    cr.MovingAvgScore,
    cr.TotalPosts,
    cr.MaxScore,
    cr.MinScore,
    cr.TagName,
    cr.TagCount,
    cr.TagCategory,
    cr.TagRank,
    cr.TagPercentRank,
    cr.ReputationTier,
    cr.PostCount,
    cr.BadgeCount,
    cr.CommentCount,
    cr.DaysSinceRegistration,
    cr.ReputationRank,
    cr.EngagementLevel,
    cr.FormattedTitle,
    cr.TitleOrPlaceholder,
    CASE 
        WHEN cr.Score >= cr.MaxScore THEN 'Top Rated'
        WHEN cr.Score >= cr.MaxScore * 0.75 THEN 'High Rated'
        WHEN cr.Score >= cr.MaxScore * 0.5 THEN 'Medium Rated'
        WHEN cr.Score >= cr.MaxScore * 0.25 THEN 'Low Rated'
        ELSE 'Very Low Rated'
    END as ScoreRating,
    DENSE_RANK() OVER (ORDER BY cr.Score * cr.ViewCount DESC) as CombinedRank,
    PERCENT_RANK() OVER (ORDER BY cr.Score) as ScorePercentile,
    ROW_NUMBER() OVER (ORDER BY cr.CreationDate) as CreationOrder,
    CASE 
        WHEN cr.PostTypeId = 1 
        AND cr.AnswerCount IS NOT NULL 
        AND cr.AnswerCount > 0 THEN 
            ROUND((cast(cr.AnswerCount as FLOAT) / cast(cr.CommentCount as FLOAT)) * 100.0, 2)
        ELSE NULL
    END as AnswerToCommentRatio,
    CASE 
        WHEN cr.LastActivityDate IS NOT NULL AND cr.CreationDate IS NOT NULL THEN
            DATEDIFF(HOUR, cr.CreationDate, cr.LastActivityDate)
        ELSE 0
    END as HoursSinceCreation,
    COALESCE(cr.ViewCount, 0) + COALESCE(cr.UpVotes, 0) - COALESCE(cr.DownVotes, 0) as NetActivityScore
FROM ComplexQueryResult cr
WHERE cr.Score > 0
AND (
    cr.PostTypeId = 1 
    OR (
        cr.PostTypeId = 2 
        AND EXISTS (
            SELECT 1 FROM Posts p2 
            WHERE p2.Id = cr.Id 
            AND (p2.Tags LIKE '%<c>%'
                 OR p2.Tags LIKE '%<java>%'
                 OR p2.Tags LIKE '%python%'
                 OR p2.Tags LIKE '%javascript%')
        )
    )
)
AND cr.PostTypeName IN ('Question', 'Answer')
AND cr.OwnerDisplayName IS NOT NULL
UNION ALL
SELECT 
    NULL as Id,
    NULL as PostTypeId,
    'Summary' as PostTypeName,
    NULL as Score,
    NULL as ViewCount,
    NULL as Title,
    NULL as Tags,
    NULL as OwnerUserId,
    NULL as OwnerDisplayName,
    NULL as OwnerReputation,
    NULL as CreationDate,
    NULL as LastActivityDate,
    NULL as AnswerCount,
    NULL as CommentCount,
    NULL as FavoriteCount,
    NULL as ScoreRank,
    NULL as ScoreDenseRank,
    NULL as ScoreNtile,
    NULL as ScoreChangeStatus,
    NULL as MovingAvgScore,
    COUNT(*) as TotalPosts,
    MAX(cr2.Score) as MaxScore,
    MIN(cr2.Score) as MinScore,
    NULL as TagName,
    NULL as TagCount,
    NULL as TagCategory,
    NULL as TagRank,
    NULL as TagPercentRank,
    NULL as ReputationTier,
    NULL as PostCount,
    NULL as BadgeCount,
    NULL as CommentCount,
    NULL as DaysSinceRegistration,
    NULL as ReputationRank,
    NULL as EngagementLevel,
    NULL as FormattedTitle,
    NULL as TitleOrPlaceholder,
    NULL as ScoreRating,
    NULL as CombinedRank,
    NULL as ScorePercentile,
    NULL as CreationOrder,
    NULL as AnswerToCommentRatio,
    NULL as HoursSinceCreation,
    NULL as NetActivityScore
FROM ComplexQueryResult cr2
WHERE cr2.PostTypeId IN (1, 2)
ORDER BY CASE WHEN Id IS NULL THEN 1 ELSE 0 END, Id;