-- {"query": "7738.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1992} 
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
        MAX(b.Date) as LastBadgeDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(SUM(p.Score) AS FLOAT) / NULLIF(COUNT(DISTINCT p.Id), 0)
            ELSE 0 
        END as AvgPostScore,
        CAST(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(DISTINCT p.Id), 0) * 100 as QuestionPercentage,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as RankByPosts,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as RankByReputation,
        NTILE(100) OVER (ORDER BY u.Reputation ASC) as ReputationPercentile,
        CONCAT('User_', u.Id, '_reputation_', u.Reputation) as UserIdentifier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        STRING_AGG(p.Title, '; ') as SampleQuestions,
        COUNT(p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        MIN(p.CreationDate) as FirstQuestionDate,
        MAX(p.CreationDate) as LatestQuestionDate,
        CASE 
            WHEN t.Count > 5000 THEN 'Very Popular'
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityLevel
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.TagName IS NOT NULL
    GROUP BY t.TagName, t.Count, t.ExcerptPostId
    HAVING COUNT(p.Id) > 10
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
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'Tag Wiki Excerpt'
            WHEN p.PostTypeId = 5 THEN 'Tag Wiki'
            ELSE 'Other'
        END as PostTypeDescription,
        COALESCE(u.DisplayName, p.OwnerDisplayName) as OwnerName,
        COALESCE(p.Score, 0) - COALESCE(
            (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId AND Score IS NOT NULL), 
            0
        ) as ScoreDeviation,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        CASE 
            WHEN p.Score > 10 THEN 'Highly Rated'
            WHEN p.Score > 5 THEN 'Moderately Rated'
            WHEN p.Score > 0 THEN 'Slightly Rated'
            ELSE 'Not Rated'
        END as RatingCategory,
        DATEDIFF('SECOND', p.CreationDate, COALESCE(p.LastEditDate, p.LastActivityDate)) as TimeToEdit,
        CASE 
            WHEN p.LastEditDate IS NOT NULL THEN 
                CONCAT('Edited at ', p.LastEditDate, ' by ', COALESCE(p.LastEditorDisplayName, 'Unknown'))
            ELSE 'Never Edited'
        END as EditStatus
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
ComplexQueryResults AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.AvgPostScore,
        uas.QuestionPercentage,
        uas.RankByPosts,
        uas.RankByReputation,
        uas.ReputationPercentile,
        ta.TagName,
        ta.Count as TagCount,
        ta.QuestionCount,
        ta.AvgScore as TagAvgScore,
        pa.PostId,
        pa.Title as PostTitle,
        pa.Score as PostScore,
        pa.ViewCount as PostViewCount,
        pa.AnswerCount as PostAnswerCount,
        pa.CommentCount as PostCommentCount,
        pa.ScoreDeviation,
        pa.PreviousScore,
        pa.NextScore,
        pa.RatingCategory,
        pa.TimeToEdit,
        pa.EditStatus,
        CASE 
            WHEN ta.Count > (SELECT AVG(Count) FROM Tags) THEN 1
            ELSE 0
        END as IsAboveAverageTag,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 1
            ELSE 0
        END as IsAboveAverageQuestion,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) as ScoreRankInUserPosts,
        RANK() OVER (ORDER BY pa.Score DESC) as OverallScoreRank,
        DENSE_RANK() OVER (ORDER BY pa.CreationDate DESC) as RecentPostRank,
        COUNT(*) OVER (PARTITION BY pa.OwnerUserId) as TotalPostsByUser,
        CASE 
            WHEN pa.AnswerCount IS NULL OR pa.AnswerCount = 0 THEN 'No Answers'
            WHEN pa.AnswerCount > 10 THEN 'Many Answers'
            WHEN pa.AnswerCount > 5 THEN 'Some Answers'
            ELSE 'Few Answers'
        END as AnswerCategory
    FROM UserActivityStats uas
    CROSS JOIN TopTags ta
    INNER JOIN PostAnalysis pa ON uas.UserId = pa.OwnerUserId
    WHERE uas.PostCount > 5
      AND ta.QuestionCount > 10
      AND pa.RatingCategory IN ('Highly Rated', 'Moderately Rated')
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    CommentCount,
    BadgeCount,
    AvgPostScore,
    QuestionPercentage,
    RankByPosts,
    RankByReputation,
    ReputationPercentile,
    TagName,
    TagCount,
    QuestionCount,
    TagAvgScore,
    PostId,
    PostTitle,
    PostScore,
    PostViewCount,
    PostAnswerCount,
    PostCommentCount,
    ScoreDeviation,
    PreviousScore,
    NextScore,
    RatingCategory,
    TimeToEdit,
    EditStatus,
    IsAboveAverageTag,
    IsAboveAverageQuestion,
    ScoreRankInUserPosts,
    OverallScoreRank,
    RecentPostRank,
    TotalPostsByUser,
    AnswerCategory,
    CASE 
        WHEN Reputation > 100000 THEN 'Elite'
        WHEN Reputation > 50000 THEN 'Master'
        WHEN Reputation > 10000 THEN 'Expert'
        WHEN Reputation > 5000 THEN 'Advanced'
        ELSE 'Beginner'
    END as UserTier,
    CONCAT(
        DisplayName, 
        ' (', 
        CASE 
            WHEN TagName IS NOT NULL THEN TagName 
            ELSE 'No Tag' 
        END, 
        ')'
    ) as UserTagCombination,
    (PostScore + TagCount) * PostViewCount as CombinedMetric,
    ROW_NUMBER() OVER (ORDER BY (PostScore + TagCount) * PostViewCount DESC) as CombinedRank,
    COALESCE(
        (SELECT COUNT(*) FROM ComplexQueryResults WHERE TagName IS NOT NULL), 
        0
    ) as TotalTaggedRecords,
    CAST(
        (SELECT AVG(Reputation) FROM ComplexQueryResults) 
        AS VARCHAR(100)
    ) as AvgReputation,
    CASE 
        WHEN ABS(PostScore - PreviousScore) > 50 THEN 'Significant Change'
        WHEN ABS(PostScore - PreviousScore) > 10 THEN 'Moderate Change'
        ELSE 'Minor Change'
    END as ScoreChangeCategory
FROM ComplexQueryResults
WHERE PostCount > 0
  AND (PostScore > 20 OR TagCount > 50)
  AND DisplayName IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.OwnerUserId = ComplexQueryResults.UserId 
    AND p.PostTypeId = 1 
    AND p.CreationDate > '2020-01-01'
  )
ORDER BY 
    CombinedMetric DESC,
    Reputation DESC,
    PostCount DESC,
    TagCount DESC
LIMIT 1000;