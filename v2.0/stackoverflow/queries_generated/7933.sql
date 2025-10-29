-- {"query": "7933.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1917} 
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
            ELSE 'Other'
        END AS PostTypeDesc,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreCategory,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS DaysActive,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts
    FROM Posts p
),
AnswerStats AS (
    SELECT 
        a.ParentId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
QuestionTags AS (
    SELECT 
        q.Id AS QuestionId,
        STRING_AGG(SUBSTRING(q.Tags, 2, LENGTH(q.Tags)-2), ', ') AS AllTags,
        COUNT(*) AS TagCount,
        STRING_AGG(
            CASE 
                WHEN SUBSTRING(q.Tags, 2, LENGTH(q.Tags)-2) LIKE '%<%<%' THEN SUBSTRING(q.Tags, 2, LENGTH(q.Tags)-2)
                ELSE NULL 
            END, 
            ', '
        ) AS NestedTagCount
    FROM Posts q
    WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL
    GROUP BY q.Id
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
PostMetrics AS (
    SELECT 
        ps.Id AS PostId,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.LastActivityDate,
        ps.Title,
        ps.Tags,
        ps.ScoreCategory,
        ps.DaysActive,
        ps.UserPostRank,
        ps.TotalUserPosts,
        COALESCE(AS.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(AS.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(AS.MinAnswerScore, 0) AS MinAnswerScore,
        COALESCE(QT.TagCount, 0) AS TagCount,
        CASE 
            WHEN ps.PostTypeId = 1 THEN 'Question'
            WHEN ps.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDesc,
        DENSE_RANK() OVER (ORDER BY ps.ViewCount DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY ps.Score DESC) AS ScoreRank,
        CASE 
            WHEN ps.PostTypeId = 1 AND ps.AnswerCount > 5 THEN 'Highly Active Question'
            WHEN ps.PostTypeId = 1 AND ps.AnswerCount BETWEEN 1 AND 5 THEN 'Moderately Active Question'
            WHEN ps.PostTypeId = 1 THEN 'Low Activity Question'
            ELSE 'Not A Question'
        END AS QuestionActivityLevel
    FROM PostStats ps
    LEFT JOIN AnswerStats AS ON ps.Id = AS.ParentId
    LEFT JOIN QuestionTags QT ON ps.Id = QT.QuestionId
)
SELECT 
    pm.PostId,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.ScoreCategory,
    pm.DaysActive,
    pm.UserPostRank,
    pm.TotalUserPosts,
    pm.AvgAnswerScore,
    pm.MaxAnswerScore,
    pm.TagCount,
    pm.PostTypeDesc,
    pm.ViewRank,
    pm.ScoreRank,
    pm.QuestionActivityLevel,
    CASE 
        WHEN pm.Score > 0 AND pm.ViewCount > 0 THEN (pm.Score * 1.0 / pm.ViewCount)
        ELSE NULL
    END AS ScoreToViewRatio,
    ROW_NUMBER() OVER (ORDER BY pm.Score DESC, pm.ViewCount DESC) AS OverallPostRank,
    RANK() OVER (PARTITION BY pm.PostTypeDesc ORDER BY pm.Score DESC) AS TypeSpecificRank,
    NTILE(4) OVER (ORDER BY pm.Score DESC) AS ScoreQuartile,
    CASE 
        WHEN pm.Score > (SELECT AVG(Score) FROM PostMetrics) THEN 'Above Average'
        WHEN pm.Score < (SELECT AVG(Score) FROM PostMetrics) THEN 'Below Average'
        ELSE 'Average'
    END AS PerformanceRanking,
    CONCAT(pm.Title, ' - ', pm.PostTypeDesc) AS TitleWithCategory,
    CASE 
        WHEN pm.LastActivityDate > DATEADD(day, -7, CURRENT_TIMESTAMP) THEN 'Recently Active'
        WHEN pm.LastActivityDate > DATEADD(day, -30, CURRENT_TIMESTAMP) THEN 'Active Recently'
        ELSE 'Inactive'
    END AS ActivityStatus,
    COALESCE(ua.PostCount, 0) AS UserPostCount,
    COALESCE(ua.Reputation, 0) AS UserReputation,
    CASE 
        WHEN ua.BadgeCount > 10 THEN 'Badge Collector'
        WHEN ua.BadgeCount > 5 THEN 'Active Participant'
        ELSE ' casual User'
    END AS UserEngagementLevel,
    CASE 
        WHEN pm.ScoreCategory IN ('High', 'Medium') AND pm.TagCount > 3 THEN 'Well Tagged'
        WHEN pm.ScoreCategory IN ('High', 'Medium') THEN 'Moderately Tagged'
        ELSE 'Poorly Tagged'
    END AS TaggingEffectiveness,
    pm.QuestionActivityLevel AS QuestionStatus,
    CASE 
        WHEN pm.QuestionActivityLevel = 'Highly Active Question' THEN 'Primary Focus'
        ELSE 'Secondary Focus'
    END AS FocusLevel,
    DATEDIFF(day, pm.CreationDate, CURRENT_TIMESTAMP) AS DaysSinceCreation,
    CASE 
        WHEN pm.AnswerCount > 0 THEN (pm.AnswerCount * 100.0 / (pm.AnswerCount + pm.CommentCount))
        ELSE 0
    END AS AnswerPercentage,
    CASE 
        WHEN pm.ViewCount > 1000 THEN 'Popular'
        WHEN pm.ViewCount > 100 THEN 'Moderately Popular'
        ELSE 'Less Popular'
    END AS PopularityTier,
    CASE 
        WHEN pm.DaysActive > 100 THEN 'Long Term Active'
        WHEN pm.DaysActive > 30 THEN 'Medium Term Active'
        ELSE 'Short Term Active'
    END AS ActivityTimeline,
    CASE 
        WHEN pm.Score > 50 AND pm.AnswerCount > 3 THEN 'Engaging Question'
        WHEN pm.Score > 25 AND pm.AnswerCount > 1 THEN 'Moderate Engagement'
        ELSE 'Low Engagement'
    END AS QuestionEngagementLevel,
    CASE 
        WHEN pm.TagCount > 5 THEN 'Richly Tagged'
        WHEN pm.TagCount > 2 THEN 'Tagged'
        ELSE 'Untagged'
    END AS TaggingStatus,
    CASE 
        WHEN pm.ViewCount > pm.Score * 10 THEN 'High Traffic'
        ELSE 'Average Traffic'
    END AS TrafficRating,
    CASE 
        WHEN pm.PostTypeId = 2 AND pm.OwnerUserId IS NOT NULL THEN (SELECT TOP 1 DisplayName FROM Users WHERE Id = pm.OwnerUserId)
        ELSE NULL
    END AS OwnerDisplayName
FROM PostMetrics pm
LEFT JOIN UserActivity ua ON pm.OwnerUserId = ua.UserId
WHERE 
    pm.ScoreCategory IN ('High', 'Medium') 
    AND pm.PostTypeDesc IN ('Question', 'Answer')
    AND pm.DaysActive > 0
    AND pm.AnswerCount >= 0
    AND (pm.ViewCount > 0 OR pm.CommentCount > 0)
ORDER BY 
    pm.Score DESC,
    pm.ViewCount DESC,
    pm.LastActivityDate DESC
LIMIT 1000;