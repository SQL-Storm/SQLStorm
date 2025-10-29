-- {"query": "7376.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2390} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        NTILE(100) OVER (ORDER BY u.Reputation) as ReputationPercentile,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS FLOAT) / NULLIF(SUM(CASE WHEN p.Score < 0 THEN ABS(p.Score) ELSE 0 END), 0)
            ELSE NULL 
        END as ScoreRatio
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestioners AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Questions,
        uas.ScoreRatio,
        RANK() OVER (ORDER BY uas.Questions DESC) as QuestionRank
    FROM UserActivityStats uas
    WHERE uas.Questions > 10
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        p.OwnerUserId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                CASE 
                    WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
                    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
                    ELSE 'Unanswered'
                END
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostStatus,
        COALESCE(p.Tags, '') as Tags,
        UPPER(COALESCE(p.Tags, '')) as TagsUpper,
        CASE 
            WHEN p.Score > 10 THEN 'HighlyVoted'
            WHEN p.Score > 0 THEN 'Positive'
            WHEN p.Score = 0 THEN 'Neutral'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'Unknown'
        END as ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01 00:00:00'
      AND p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.TagName LIKE '%c%' OR t.TagName LIKE '%cpp%' THEN 'C/C++ Related'
            WHEN t.TagName LIKE '%java%' THEN 'Java Related'
            WHEN t.TagName LIKE '%python%' THEN 'Python Related'
            WHEN t.TagName LIKE '%javascript%' OR t.TagName LIKE '%js%' THEN 'JavaScript Related'
            WHEN t.TagName LIKE '%sql%' OR t.TagName LIKE '%database%' THEN 'Database Related'
            ELSE 'Other'
        END as TagCategory,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.Count > 1000
),
QuestionWithAnswers AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.OwnerUserId,
        pa.ScoreCategory,
        pa.AgeInDays,
        pa.PostStatus,
        pa.UserPostRank,
        CASE 
            WHEN pa.AnswerCount = 0 THEN 0
            ELSE (SELECT COUNT(*) FROM Posts WHERE ParentId = pa.PostId AND PostTypeId = 2)
        END as ActualAnswerCount,
        CASE 
            WHEN pa.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts WHERE ParentId = pa.PostId AND PostTypeId = 2 AND Score > 0) * 100.0 / NULLIF(pa.AnswerCount, 0)
            ELSE 0 
        END as PositiveAnswerPercentage
    FROM PostAnalysis pa
    WHERE pa.PostTypeId = 1
),
UserBadgesWithMetadata AS (
    SELECT 
        b.Id as BadgeId,
        b.UserId,
        b.Name as BadgeName,
        b.Date as BadgeDate,
        b.Class,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            WHEN b.Class = 3 THEN 'Bronze'
            ELSE 'Unknown'
        END as BadgeLevel,
        b.TagBased,
        CASE 
            WHEN b.TagBased = 1 THEN 'Tag-Based'
            ELSE 'Named Badge'
        END as BadgeType,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) as BadgeRank,
        COUNT(*) OVER (PARTITION BY b.UserId) as TotalBadgesForUser
    FROM Badges b
    WHERE b.Date >= '2015-01-01 00:00:00'
),
CombinedAnalysis AS (
    SELECT 
        tua.UserId,
        tua.DisplayName,
        tua.Reputation,
        tua.Questions,
        tua.ScoreRatio,
        tua.ReputationRank,
        tua.ReputationPercentile,
        qwa.PostId,
        qwa.Title,
        qwa.Score AS PostScore,
        qwa.ViewCount,
        qwa.AnswerCount,
        qwa.CommentCount,
        qwa.AgeInDays,
        qwa.PostStatus,
        qwa.ScoreCategory,
        qwa.PositiveAnswerPercentage,
        ta.TagName,
        ta.Count as TagCount,
        ta.TagCategory,
        ta.PopularityRank,
        ubm.BadgeId,
        ubm.BadgeName,
        ubm.BadgeDate,
        ubm.BadgeLevel,
        ubm.BadgeType,
        ubm.BadgeRank,
        ubm.TotalBadgesForUser,
        CASE 
            WHEN qwa.Score >= 100 THEN 'Elite Question'
            WHEN qwa.Score >= 50 THEN 'Solid Question'
            WHEN qwa.Score >= 10 THEN 'Good Question'
            ELSE 'Basic Question'
        END as QuestionQuality,
        CASE 
            WHEN LENGTH(COALESCE(qwa.Title, '')) > 50 THEN 'Long Title'
            WHEN LENGTH(COALESCE(qwa.Title, '')) > 20 THEN 'Medium Title'
            ELSE 'Short Title'
        END as TitleLengthCategory
    FROM TopQuestioners tua
    JOIN QuestionWithAnswers qwa ON tua.UserId = qwa.OwnerUserId
    LEFT JOIN Tags ta ON EXISTS (
        SELECT 1 FROM unnest(string_to_array(qwa.Tags, '<>')) t(tag) 
        WHERE t.tag = ta.TagName
    )
    LEFT JOIN UserBadgesWithMetadata ubm ON tua.UserId = ubm.UserId
    WHERE ta.TagName IS NOT NULL OR ubm.BadgeName IS NOT NULL
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.Questions,
    ca.ScoreRatio,
    ca.ReputationRank,
    ca.ReputationPercentile,
    ca.PostId,
    ca.Title,
    ca.PostScore,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.AgeInDays,
    ca.PostStatus,
    ca.ScoreCategory,
    ca.PositiveAnswerPercentage,
    ca.TagName,
    ca.TagCount,
    ca.TagCategory,
    ca.PopularityRank,
    ca.BadgeId,
    ca.BadgeName,
    ca.BadgeDate,
    ca.BadgeLevel,
    ca.BadgeType,
    ca.BadgeRank,
    ca.TotalBadgesForUser,
    ca.QuestionQuality,
    ca.TitleLengthCategory,
    ROW_NUMBER() OVER (ORDER BY ca.Reputation DESC, ca.PostScore DESC) as OverallRank,
    RANK() OVER (PARTITION BY ca.TagCategory ORDER BY ca.PostScore DESC) as TagCategoryRank,
    DENSE_RANK() OVER (ORDER BY ca.BadgeLevel, ca.BadgeRank) as BadgePriority,
    CASE 
        WHEN ca.Reputation > 10000 THEN 'Expert'
        WHEN ca.Reputation > 5000 THEN 'Advanced'
        WHEN ca.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as UserLevel,
    CASE 
        WHEN ca.AgeInDays < 30 THEN 'Fresh'
        WHEN ca.AgeInDays < 180 THEN 'Active'
        WHEN ca.AgeInDays < 365 THEN 'Seasoned'
        ELSE 'Veteran'
    END as ActivityLevel,
    COALESCE(ca.Title, 'No Title') || ' | ' || COALESCE(ca.TagName, 'No Tag') || ' | ' || COALESCE(ca.BadgeName, 'No Badge') as MetadataSummary,
    CONCAT(
        'User:', ca.DisplayName, 
        ' | Rep:', ca.Reputation, 
        ' | Questions:', ca.Questions,
        ' | Score Ratio:', ROUND(ca.ScoreRatio, 2),
        ' | Post ID:', ca.PostId,
        ' | Tag:', COALESCE(ca.TagName, 'N/A')
    ) as CompressedInfo,
    CASE 
        WHEN ca.QuestionQuality = 'Elite Question' AND ca.PositiveAnswerPercentage > 80 THEN 'Exceptional Contributor'
        WHEN ca.QuestionQuality IN ('Solid Question', 'Good Question') AND ca.AnswerCount > 5 THEN 'Quality Contributor'
        WHEN ca.TotalBadgesForUser > 20 THEN 'Badge Collector'
        ELSE 'Regular Contributor'
    END as ContributorType,
    NULLIF(
        CASE 
            WHEN ca.ScoreRatio IS NOT NULL AND ca.ScoreRatio > 1 THEN 
                CONCAT('High Ratio: ', ROUND(ca.ScoreRatio, 2))
            WHEN ca.ScoreRatio < 0 THEN 
                CONCAT('Negative Ratio: ', ROUND(ca.ScoreRatio, 2))
            ELSE 'Normal Ratio'
        END, 
        ''
    ) as PerformanceIndicator
FROM CombinedAnalysis ca
WHERE ca.PostScore > 0 
  AND (ca.TagCount > 500 OR ca.BadgeName IS NOT NULL)
  AND (ca.Reputation > 100 OR ca.TotalBadgesForUser > 5)
ORDER BY 
    ca.Reputation DESC, 
    ca.PostScore DESC, 
    ca.BadgeDate DESC
LIMIT 1000;