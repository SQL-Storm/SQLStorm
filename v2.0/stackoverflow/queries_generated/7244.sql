-- {"query": "7244.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1964} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        NTILE(10) OVER (ORDER BY p.CreationDate) as CreationDecile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) as QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) as AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        p.Title as ExcerptTitle,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Rare'
            ELSE 'Average'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
),
PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                CASE 
                    WHEN p.AnswerCount > 0 AND p.Score > 0 THEN 'Active_Question'
                    WHEN p.AnswerCount = 0 AND p.Score >= 0 THEN 'Unanswered_Question'
                    WHEN p.AnswerCount = 0 AND p.Score < 0 THEN 'Negative_Question'
                    ELSE 'Other_Question'
                END
            ELSE 'Non_Question'
        END as QuestionStatus,
        CASE 
            WHEN p.AnswerCount > 0 AND (p.Score > 0 OR EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 1)) THEN 1
            ELSE 0
        END as HasAcceptedAnswer,
        ABS(p.Score) as AbsScore,
        IIF(p.ViewCount IS NULL, 0, p.ViewCount) as SafeViewCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
ComplexJoin AS (
    SELECT 
        ra.Id,
        ra.Score,
        ra.ViewCount,
        ra.CreationDate,
        ra.OwnerUserId,
        ra.Title,
        ra.Tags,
        ra.AnswerCount,
        ra.CommentCount,
        ra.FavoriteCount,
        ra.ScoreRank,
        ra.ViewRank,
        ra.CreationDecile,
        ua.PostCount,
        ua.CommentCount as UserCommentCount,
        ua.AvgPostScore,
        ua.LastPostDate,
        ua.QuestionCount,
        ua.AnswerCount as UserAnswerCount,
        ta.TagName,
        ta.Count as TagCount,
        ta.ExcerptTitle,
        ta.TagPopularity,
        ps.QuestionStatus
    FROM RankedPosts ra
    LEFT JOIN UserActivity ua ON ra.OwnerUserId = ua.UserId
    LEFT JOIN PostStats ps ON ra.Id = ps.Id
    LEFT JOIN (
        SELECT 
            t.TagName,
            t.Count,
            t.ExcerptPostId,
            p.Title as ExcerptTitle
        FROM Tags t
        INNER JOIN Posts p ON t.ExcerptPostId = p.Id
        WHERE t.Count > (SELECT AVG(Count) FROM Tags)
    ) ta ON ta.TagName IN (
        SELECT TRIM(BOTH '<>' FROM unnest(string_to_array(p.Tags, '><'))) 
        FROM Posts p 
        WHERE p.Id = ra.Id AND p.Tags IS NOT NULL
    )
    WHERE ra.Score IS NOT NULL
),
FinalAnalysis AS (
    SELECT 
        cj.*,
        CASE 
            WHEN cj.QuestionStatus = 'Active_Question' AND cj.HasAcceptedAnswer = 1 AND cj.Score > 5 THEN 'Highly_Active_Question'
            WHEN cj.QuestionStatus = 'Active_Question' AND cj.HasAcceptedAnswer = 0 AND cj.Score > 3 THEN 'Active_Question'
            WHEN cj.QuestionStatus = 'Unanswered_Question' AND cj.Score > 0 THEN 'Unanswered_Question'
            WHEN cj.QuestionStatus = 'Negative_Question' THEN 'Negative_Question'
            ELSE 'Other'
        END as PostCategory,
        IIF(cj.ViewRank < 100, 'Top_Viewed', 
            IIF(cj.ViewRank < 1000, 'Mid_Viewed', 'Low_Viewed')) as ViewCategory,
        CASE 
            WHEN cj.Score >= 10 THEN 'High_Score'
            WHEN cj.Score >= 5 THEN 'Medium_Score'
            WHEN cj.Score >= 1 THEN 'Low_Score'
            ELSE 'Negative_Score'
        END as ScoreCategory,
        CASE 
            WHEN cj.CreationDecile <= 3 THEN 'New_Era'
            WHEN cj.CreationDecile >= 8 THEN 'Old_Era'
            ELSE 'Mid_Era'
        END as TimeEra,
        COALESCE(cj.TagCount, 0) as TotalTagCount,
        COALESCE(cj.QuestionCount, 0) + COALESCE(cj.AnswerCount, 0) as TotalUserPosts,
        ABS(cj.Score) - ABS(cj.AvgPostScore) as ScoreVsAverage,
        (cj.ViewCount * 1.0 / NULLIF(cj.PostCount, 0)) as AvgViewsPerPost,
        CASE 
            WHEN cj.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above_Avg'
            WHEN cj.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below_Avg'
            ELSE 'Avg'
        END as ScoreComparison
    FROM ComplexJoin cj
)
SELECT 
    fa.Id,
    fa.Score,
    fa.ViewCount,
    fa.CreationDate,
    fa.OwnerUserId,
    fa.Title,
    fa.Tags,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.ScoreRank,
    fa.ViewRank,
    fa.CreationDecile,
    fa.PostCount,
    fa.UserCommentCount,
    fa.AvgPostScore,
    fa.LastPostDate,
    fa.QuestionCount,
    fa.UserAnswerCount,
    fa.TagName,
    fa.TagCount,
    fa.ExcerptTitle,
    fa.TagPopularity,
    fa.QuestionStatus,
    fa.PostCategory,
    fa.ViewCategory,
    fa.ScoreCategory,
    fa.TimeEra,
    fa.TotalTagCount,
    fa.TotalUserPosts,
    fa.ScoreVsAverage,
    fa.AvgViewsPerPost,
    fa.ScoreComparison,
    CASE 
        WHEN fa.PostCategory = 'Highly_Active_Question' AND fa.ViewCategory = 'Top_Viewed' THEN 'Prime_Question'
        WHEN fa.QuestionStatus = 'Unanswered_Question' AND fa.Score < 0 THEN 'Poor_Question'
        WHEN fa.PostCategory = 'Active_Question' AND fa.Score > 10 THEN 'Popular_Question'
        ELSE 'Regular_Question'
    END as QuestionTag,
    IIF(fa.ScoreRank <= 10, 'Top_Score', 'Normal_Score') as PerformanceIndicator,
    CASE 
        WHEN fa.Score > 100 THEN 'Elite_Question'
        WHEN fa.ViewCount > 10000 THEN 'Viral_Question'
        WHEN fa.AnswerCount > 100 THEN 'Highly_Discussed_Question'
        ELSE 'Regular_Question'
    END as PerformanceRanking,
    CASE 
        WHEN fa.CreationDate >= '2022-01-01' AND fa.CreationDate <= '2023-12-31' THEN 'Recent_Question'
        ELSE 'Historical_Question'
    END as TimeClassification
FROM FinalAnalysis fa
WHERE fa.Score IS NOT NULL 
    AND fa.ViewCount IS NOT NULL 
    AND fa.TagName IS NOT NULL
    AND fa.PostCategory IS NOT NULL
    AND (fa.Score > 0 OR fa.Score < 0) 
    AND (fa.ViewCount != 0 OR fa.Score >= 0) 
ORDER BY fa.Score DESC, fa.ViewCount DESC, fa.CreationDate DESC
LIMIT 1000;