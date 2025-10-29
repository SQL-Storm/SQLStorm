-- {"query": "7296.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2457} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LatestPostDate,
        AVG(p.ViewCount) as AvgViews,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        TotalScore,
        LatestPostDate,
        AvgViews,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, PostCount DESC) as RankByScore,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation
    FROM UserActivityStats
),
RecentActivity AS (
    SELECT 
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        ph.RevisionGUID,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as RecentActivityOrder
    FROM PostHistory ph
    WHERE ph.CreationDate >= DATEADD(DAY, -30, GETDATE())
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        CASE 
            WHEN p.AnswerCount IS NULL OR p.AnswerCount = 0 THEN 0
            WHEN p.AnswerCount > 10 THEN 3
            WHEN p.AnswerCount > 5 THEN 2
            WHEN p.AnswerCount > 0 THEN 1
            ELSE 0
        END as AnswerComplexityLevel,
        CASE 
            WHEN p.ViewCount IS NULL THEN 0
            WHEN p.ViewCount > 1000 THEN 3
            WHEN p.ViewCount > 500 THEN 2
            WHEN p.ViewCount > 100 THEN 1
            ELSE 0
        END as ViewComplexityLevel,
        LEN(p.Body) as BodyLength,
        LEN(p.Title) as TitleLength,
        CASE 
            WHEN p.Tags IS NULL OR p.Tags = '' THEN 0
            ELSE LEN(p.Tags) - LEN(REPLACE(p.Tags, '>', '')) + 1
        END as TagCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)), 
            0
        ) as VoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 
            0
        ) as CommentCount,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) as AgeInDays,
        CASE 
            WHEN p.ParentId IS NOT NULL THEN 'Answer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            ELSE 'Other'
        END as PostType,
        COALESCE(
            (SELECT TOP 1 ph.CreationDate FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13) ORDER BY ph.CreationDate DESC),
            p.CreationDate
        ) as LastImportantActivity
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(YEAR, -2, GETDATE())
),
TagMetrics AS (
    SELECT 
        t.TagName,
        t.Count as TagUsageCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(
            (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%' AND p.PostTypeId = 1),
            0
        ) as AvgQuestionScore,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%' AND p.PostTypeId = 1),
            0
        ) as QuestionCount,
        STRING_AGG(
            CASE 
                WHEN p.OwnerUserId IS NOT NULL THEN CAST(p.OwnerUserId AS VARCHAR)
                ELSE 'SYSTEM'
            END, 
            ', '
        ) as TopContributors
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%'
    WHERE t.Count >= 100
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
)
SELECT 
    tu.RankByScore,
    tu.RankByReputation,
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.CommentCount,
    tu.BadgeCount,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalScore,
    tu.LatestPostDate,
    tu.AvgViews,
    tu.AllTags,
    COALESCE(pa.Title, 'No Title') as RecentTitle,
    COALESCE(pa.Body, 'No Body') as RecentBody,
    COALESCE(pa.Score, 0) as RecentScore,
    COALESCE(pa.ViewCount, 0) as RecentViewCount,
    COALESCE(pa.AnswerCount, 0) as RecentAnswerCount,
    COALESCE(pa.CommentCount, 0) as RecentCommentCount,
    COALESCE(pa.FavoriteCount, 0) as RecentFavoriteCount,
    COALESCE(pa.BodyLength, 0) as BodyLength,
    COALESCE(pa.TitleLength, 0) as TitleLength,
    COALESCE(pa.TagCount, 0) as TagCount,
    COALESCE(pa.VoteCount, 0) as VoteCount,
    COALESCE(pa.AgeInDays, 0) as AgeInDays,
    COALESCE(tm.TagName, 'No Topic') as TopTag,
    COALESCE(tm.TagUsageCount, 0) as TagUsage,
    COALESCE(tm.AvgQuestionScore, 0) as AvgQuestionScore,
    CASE 
        WHEN pa.AnswerComplexityLevel > 0 THEN 'High Complexity'
        WHEN pa.AnswerComplexityLevel = 0 THEN 'Low Complexity'
        ELSE 'Unknown'
    END as ComplexityStatus,
    CASE 
        WHEN pa.ViewComplexityLevel > 1 THEN 'High Visibility'
        WHEN pa.ViewComplexityLevel = 1 THEN 'Medium Visibility'
        ELSE 'Low Visibility'
    END as VisibilityStatus,
    CASE 
        WHEN tu.PostCount >= 100 THEN 'Veteran'
        WHEN tu.PostCount >= 50 THEN 'Experienced'
        WHEN tu.PostCount >= 10 THEN 'Active'
        ELSE 'Beginner'
    END as UserStatusLevel,
    CASE 
        WHEN tu.Reputation > 10000 THEN 'Elite'
        WHEN tu.Reputation > 5000 THEN 'Expert'
        WHEN tu.Reputation > 1000 THEN 'Regular'
        ELSE 'Newbie'
    END as ReputationTier,
    (SELECT 
        COUNT(*) 
     FROM PostHistory ph 
     INNER JOIN Posts p ON ph.PostId = p.Id 
     WHERE ph.UserId = tu.UserId 
       AND ph.CreationDate BETWEEN DATEADD(MONTH, -3, GETDATE()) AND GETDATE()
       AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66)
    ) as RecentEditsCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = tu.UserId AND v.CreationDate >= DATEADD(MONTH, -3, GETDATE())) as RecentVotesCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tu.UserId AND b.Date >= DATEADD(MONTH, -3, GETDATE())) as RecentBadgesCount,
    CASE 
        WHEN tu.PostCount > 0 THEN 
            (CAST(tu.AnswerCount AS FLOAT) / NULLIF(tu.PostCount, 0)) * 100
        ELSE 0
    END as AnswerContributionPercent,
    CASE 
        WHEN tu.TotalScore > 0 THEN 
            (CAST(tu.CommentCount AS FLOAT) / NULLIF(tu.TotalScore, 0)) * 100
        ELSE 0
    END as EngagementRatio,
    DATEDIFF(DAY, COALESCE(tu.LatestPostDate, '1900-01-01'), GETDATE()) as DaysSinceLastActivity
FROM TopUsers tu
LEFT JOIN RecentActivity ra ON ra.PostId IN (
    SELECT Id FROM Posts WHERE OwnerUserId = tu.UserId 
    AND CreationDate >= DATEADD(MONTH, -1, GETDATE())
)
LEFT JOIN PostComplexity pa ON pa.PostId = ra.PostId
LEFT JOIN TagMetrics tm ON tm.TagUsageCount = (
    SELECT MAX(tm2.TagUsageCount) 
    FROM TagMetrics tm2 
    WHERE tm2.TagUsageCount > 0
)
WHERE tu.UserId IS NOT NULL
  AND tu.Reputation >= 100
  AND tu.PostCount >= 10
  AND (
    ra.PostId IS NOT NULL 
    OR EXISTS (
        SELECT 1 FROM Posts p 
        WHERE p.OwnerUserId = tu.UserId 
        AND p.CreationDate >= DATEADD(MONTH, -1, GETDATE())
    )
  )
  AND (
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.UserId = tu.UserId 
            AND ph.CreationDate >= DATEADD(DAY, -7, GETDATE())
        ) THEN 1
        WHEN EXISTS (
            SELECT 1 FROM Votes v 
            WHERE v.UserId = tu.UserId 
            AND v.CreationDate >= DATEADD(DAY, -7, GETDATE())
        ) THEN 1
        WHEN EXISTS (
            SELECT 1 FROM Badges b 
            WHERE b.UserId = tu.UserId 
            AND b.Date >= DATEADD(DAY, -7, GETDATE())
        ) THEN 1
        ELSE 0
    END = 1
  )
ORDER BY tu.TotalScore DESC, tu.Reputation DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY
OPTION (RECOMPILE);