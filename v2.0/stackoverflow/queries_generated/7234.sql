-- {"query": "7234.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1982} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) as QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) as AnswerCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
        MAX(p.CreationDate) as LatestPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) as PostRank,
        STRING_AGG(DISTINCT p.Tags, ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
RankedUsers AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY TotalQuestionScore DESC, TotalAnswerScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RepRank,
        NTILE(10) OVER (ORDER BY Views DESC) as ViewQuartile
    FROM UserActivityStats
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagCategory,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
),
PostAnalytics AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        COALESCE(p.AnswerCount, 0) * 100.0 / NULLIF(p.ViewCount, 0) as AnswerViewRatio,
        CASE 
            WHEN p.Score > 10 THEN 'High'
            WHEN p.Score > 5 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Negative'
        END as ScoreCategory,
        EXTRACT(DAY FROM (CURRENT_TIMESTAMP - p.CreationDate)) as DaysSinceCreation,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevPostScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextPostScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        COALESCE(p.ViewCount, 0) - COALESCE(LAG(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0) as ViewChange
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
FilteredPosts AS (
    SELECT 
        pa.*,
        CASE 
            WHEN pa.DaysSinceCreation < 30 THEN 'New'
            WHEN pa.DaysSinceCreation BETWEEN 30 AND 365 THEN 'Established'
            ELSE 'Legacy'
        END as PostAgeCategory
    FROM PostAnalytics pa
    WHERE pa.Score IS NOT NULL OR pa.ViewCount IS NOT NULL
),
CrossUserPostAnalysis AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.TotalQuestionScore,
        ru.TotalAnswerScore,
        ru.Reputation,
        ru.Views,
        ru.ScoreRank,
        ru.RepRank,
        ru.ViewQuartile,
        ARRAY(
            SELECT pa.Id 
            FROM FilteredPosts pa 
            WHERE pa.OwnerUserId = ru.UserId 
            AND pa.PostTypeId = 1
            ORDER BY pa.CreationDate DESC
            LIMIT 5
        ) as RecentQuestions,
        ARRAY(
            SELECT pa.Id 
            FROM FilteredPosts pa 
            WHERE pa.OwnerUserId = ru.UserId 
            AND pa.PostTypeId = 2
            ORDER BY pa.CreationDate DESC
            LIMIT 5
        ) as RecentAnswers,
        STRING_AGG(CASE 
            WHEN pa.PostTypeId = 1 THEN pa.Title 
            ELSE NULL 
        END, ' | ') as QuestionTitles,
        STRING_AGG(CASE 
            WHEN pa.PostTypeId = 2 THEN SUBSTRING(pa.Title, 1, 50) 
            ELSE NULL 
        END, ' | ') as AnswerTitles
    FROM RankedUsers ru
    LEFT JOIN FilteredPosts pa ON ru.UserId = pa.OwnerUserId
    WHERE ru.ScoreRank <= 100
    GROUP BY ru.UserId, ru.DisplayName, ru.QuestionCount, ru.AnswerCount, 
             ru.TotalQuestionScore, ru.TotalAnswerScore, ru.Reputation, 
             ru.Views, ru.ScoreRank, ru.RepRank, ru.ViewQuartile
)
SELECT 
    cu.UserId,
    cu.DisplayName,
    cu.QuestionCount,
    cu.AnswerCount,
    cu.TotalQuestionScore,
    cu.TotalAnswerScore,
    cu.Reputation,
    cu.Views,
    cu.ScoreRank,
    cu.RepRank,
    cu.ViewQuartile,
    cu.QuestionTitles,
    cu.AnswerTitles,
    CASE 
        WHEN cu.QuestionCount > 0 THEN cu.TotalQuestionScore / cu.QuestionCount
        ELSE 0
    END as AvgQuestionScore,
    CASE 
        WHEN cu.AnswerCount > 0 THEN cu.TotalAnswerScore / cu.AnswerCount
        ELSE 0
    END as AvgAnswerScore,
    COALESCE((
        SELECT COUNT(DISTINCT p2.Id) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = cu.UserId 
        AND p2.PostTypeId = 2 
        AND p2.Score > (
            SELECT AVG(p3.Score) 
            FROM Posts p3 
            WHERE p3.OwnerUserId = cu.UserId 
            AND p3.PostTypeId = 2
        )
        AND p2.CreationDate > (
            SELECT MAX(ph.CreationDate) 
            FROM PostHistory ph 
            WHERE ph.PostId = p2.Id 
            AND ph.PostHistoryTypeId IN (2, 5)
        )
    ), 0) as HighScoringAnswers,
    COALESCE((
        SELECT COUNT(DISTINCT p4.Id) 
        FROM Posts p4 
        WHERE p4.OwnerUserId = cu.UserId 
        AND p4.PostTypeId = 1 
        AND p4.CommentCount > 5
    ), 0) as HighlyCommentedQuestions,
    (SELECT COUNT(DISTINCT p5.Id) 
     FROM Posts p5 
     WHERE p5.OwnerUserId = cu.UserId 
     AND p5.PostTypeId = 1 
     AND p5.CreationDate >= DATEADD('month', -6, CURRENT_TIMESTAMP)
    ) as RecentQuestionsInLast6Months,
    (SELECT COUNT(DISTINCT p6.Id) 
     FROM Posts p6 
     WHERE p6.OwnerUserId = cu.UserId 
     AND p6.PostTypeId = 2 
     AND p6.CreationDate >= DATEADD('month', -6, CURRENT_TIMESTAMP)
    ) as RecentAnswersInLast6Months,
    STRING_AGG(DISTINCT (
        SELECT t.TagName 
        FROM Tags t 
        WHERE t.TagName IN (SELECT TRIM(UNNEST(STRING_TO_ARRAY(pa.Tags, '>'))))
    ), ', ') as AllTagsUserWorksWith,
    CASE 
        WHEN cu.QuestionCount > 0 AND cu.AnswerCount > 0 THEN 
            CAST(cu.QuestionCount AS FLOAT) / NULLIF(cu.AnswerCount, 0)
        ELSE NULL 
    END as QuestionAnswerRatio,
    CASE 
        WHEN cu.Views > 0 THEN 
            CAST(cu.TotalQuestionScore + cu.TotalAnswerScore AS FLOAT) / NULLIF(cu.Views, 0)
        ELSE 0 
    END as EngagementRate
FROM CrossUserPostAnalysis cu
WHERE cu.QuestionCount >= 5 OR cu.AnswerCount >= 10
GROUP BY cu.UserId, cu.DisplayName, cu.QuestionCount, cu.AnswerCount, 
         cu.TotalQuestionScore, cu.TotalAnswerScore, cu.Reputation, 
         cu.Views, cu.ScoreRank, cu.RepRank, cu.ViewQuartile,
         cu.QuestionTitles, cu.AnswerTitles
HAVING COALESCE(cu.QuestionCount, 0) + COALESCE(cu.AnswerCount, 0) > 0
ORDER BY cu.ScoreRank, cu.RepRank, cu.Views DESC
LIMIT 200;