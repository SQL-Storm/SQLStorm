-- {"query": "7114.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2436} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
        STRING_AGG(DISTINCT LOWER(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2)), ', ') as AllTags,
        MAX(p.ViewCount) as MaxViewCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpvoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownvoteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore DESC, TotalAnswerScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RepRank,
        RANK() OVER (ORDER BY PostCount DESC) as PostRank
    FROM UserActivityStats
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Highly Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank
    FROM Tags t
    WHERE t.Count > 100
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END as HasAcceptedAnswer,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 1
            ELSE 0
        END as HasAnswers,
        CASE 
            WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN 1
            ELSE 0
        END as HasComments,
        CASE 
            WHEN p.FavoriteCount > 0 THEN 1
            ELSE 0
        END as IsBookmarked,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        CASE 
            WHEN DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) < 30 THEN 'New'
            WHEN DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) < 180 THEN 'Recent'
            ELSE 'Old'
        END as PostAgeGroup,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        MAX(p.Score) OVER (PARTITION BY p.OwnerUserId) as MaxScorePerUser,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) as OverallRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
),
PostTagAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.OwnerUserId,
        pa.PostAgeGroup,
        pa.HasAnswers,
        pa.HasComments,
        pa.HasAcceptedAnswer,
        CASE 
            WHEN pa.HasAnswers = 1 AND pa.HasComments = 1 THEN 'Complex'
            WHEN pa.HasAnswers = 1 THEN 'Answered'
            WHEN pa.HasComments = 1 THEN 'Discussed'
            ELSE 'Simple'
        END as PostComplexity,
        CASE 
            WHEN pa.Score > 100 THEN 'Highly Engaged'
            WHEN pa.Score > 50 THEN 'Engaged'
            WHEN pa.Score > 10 THEN 'Medium'
            ELSE 'Low'
        END as EngagementLevel,
        CASE 
            WHEN pa.ViewCount > 10000 THEN 'Viral'
            WHEN pa.ViewCount > 5000 THEN 'Popular'
            WHEN pa.ViewCount > 1000 THEN 'Notable'
            ELSE 'Regular'
        END as PopularityLevel,
        COALESCE(pa.Tags, '') as TagsString,
        NULLIF(LEN(pa.Tags) - LEN(REPLACE(pa.Tags, '><', '')), -1) as TagCount,
        CASE 
            WHEN LEN(pa.Tags) > 0 AND pa.Tags LIKE '%<%' THEN 
                TRIM(SUBSTRING(pa.Tags, 2, LEN(pa.Tags) - 2))
            ELSE ''
        END as CleanedTags,
        STRING_TO_ARRAY(
            CASE 
                WHEN LEN(pa.Tags) > 0 AND pa.Tags LIKE '%<%' THEN 
                    TRIM(SUBSTRING(pa.Tags, 2, LEN(pa.Tags) - 2))
                ELSE ''
            END, 
            '><'
        ) as TagArray
    FROM PostAnalysis pa
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.PostCount,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.TotalQuestionScore,
    ru.TotalAnswerScore,
    ru.AvgQuestionScore,
    ru.AvgAnswerScore,
    ru.BadgeCount,
    ru.PostRank,
    ru.ScoreRank,
    ru.RepRank,
    CASE WHEN tu.TagRank <= 10 THEN 'Top 10 Tag' ELSE 'Other Tag' END as TagStatus,
    ta.PostId,
    ta.Title,
    ta.Score,
    ta.ViewCount,
    ta.OwnerUserId,
    ta.PostAgeGroup,
    ta.HasAnswers,
    ta.HasComments,
    ta.PostComplexity,
    ta.EngagementLevel,
    ta.PopularityLevel,
    ta.TagCount,
    CASE 
        WHEN ta.TagArray IS NOT NULL AND ARRAY_LENGTH(ta.TagArray, 1) > 0 THEN 
            STRING_AGG(ta.TagArray[1], ', ')
        ELSE ''
    END as FirstTag,
    CASE 
        WHEN ta.TagArray IS NOT NULL AND ARRAY_LENGTH(ta.TagArray, 1) > 1 THEN 
            STRING_AGG(ta.TagArray[2], ', ')
        ELSE ''
    END as SecondTag,
    CASE 
        WHEN ta.TagArray IS NOT NULL AND ARRAY_LENGTH(ta.TagArray, 1) > 2 THEN 
            STRING_AGG(ta.TagArray[3], ', ')
        ELSE ''
    END as ThirdTag,
    ta.CleanedTags,
    CASE 
        WHEN ta.HasAnswers = 1 AND ta.HasComments = 1 THEN 'High Interaction'
        WHEN ta.HasAnswers = 1 THEN 'Answer Focused'
        WHEN ta.HasComments = 1 THEN 'Discussion Focused'
        ELSE 'Simple Query'
    END as ContentFocus,
    CASE 
        WHEN ta.Score > 80 THEN 'Excellent'
        WHEN ta.Score > 50 THEN 'Good'
        WHEN ta.Score > 25 THEN 'Average'
        WHEN ta.Score > 0 THEN 'Below Average'
        ELSE 'Low'
    END as PerformanceRating,
    CASE 
        WHEN ta.ViewCount > 1000 THEN 100
        WHEN ta.ViewCount > 500 THEN 75
        WHEN ta.ViewCount > 100 THEN 50
        ELSE 25
    END as ViewScore,
    CASE 
        WHEN ta.HasAcceptedAnswer = 1 THEN 'Answer Accepted'
        ELSE 'No Acceptance'
    END as AnswerStatus,
    CASE 
        WHEN ta.Score - COALESCE(ta.PrevScore, 0) > 0 THEN 'Improving'
        WHEN ta.Score - COALESCE(ta.PrevScore, 0) < 0 THEN 'Declining'
        ELSE 'Stable'
    END as Trend,
    CASE 
        WHEN ta.Score < 0 THEN 'Negative'
        WHEN ta.Score = 0 THEN 'Neutral'
        WHEN ta.Score BETWEEN 1 AND 10 THEN 'Low'
        WHEN ta.Score BETWEEN 11 AND 50 THEN 'Medium'
        WHEN ta.Score BETWEEN 51 AND 100 THEN 'High'
        ELSE 'Very High'
    END as ScoreCategory,
    CASE 
        WHEN ta.HasAnswers = 1 OR ta.HasComments = 1 THEN 'Active'
        ELSE 'Inactive'
    END as ActivityStatus,
    ROUND((ta.Score * 1.0 / NULLIF(ru.TotalQuestionScore, 0)) * 100, 2) as ScoreContributionPercentage,
    CASE 
        WHEN ta.TagCount >= 3 THEN 'Multi-tagged'
        WHEN ta.TagCount = 1 THEN 'Single-tagged'
        ELSE 'Uncategorized'
    END as TaggingStrategy,
    CASE 
        WHEN LENGTH(ta.TagsString) > 0 THEN 
            CASE 
                WHEN ta.TagsString LIKE '%<%' THEN 
                    (LENGTH(ta.TagsString) - LENGTH(REPLACE(ta.TagsString, '><', '')) + 1)
                ELSE 0
            END
        ELSE 0
    END as ActualTagCount
FROM RankedUsers ru
LEFT JOIN TopTags tu ON ru.DisplayName = 'User' -- Simplified join for demonstration
LEFT JOIN PostTagAnalysis ta ON ru.UserId = ta.OwnerUserId
WHERE ru.PostCount > 10
    AND (ta.Score IS NOT NULL OR ta.ViewCount IS NOT NULL OR ta.HasAnswers IS NOT NULL)
ORDER BY ru.Reputation DESC, ta.Score DESC, ru.PostCount DESC
LIMIT 1000;