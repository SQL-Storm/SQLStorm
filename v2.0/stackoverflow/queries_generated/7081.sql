-- {"query": "7081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2482} 
WITH PostStats AS (
    SELECT 
        p.Id as PostId,
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
        p.ParentId,
        p.AcceptedAnswerId,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) * 10 + COALESCE(p.CommentCount, 0) * 5 AS EngagementScore,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeDesc,
        COALESCE(p.Tags, '') AS CleanTags,
        LENGTH(COALESCE(p.Tags, '')) AS TagLength,
        CASE 
            WHEN p.Score >= 100 THEN 'Golden'
            WHEN p.Score >= 50 THEN 'Silver'
            WHEN p.Score >= 10 THEN 'Bronze'
            ELSE 'Common'
        END AS ScoreTier,
        DATEDIFF(DAY, p.CreationDate, CURRENT_TIMESTAMP) AS AgeInDays,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Focus on questions and answers
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        COUNT(DISTINCT ps.PostId) AS TotalPosts,
        COUNT(CASE WHEN ps.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN ps.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(COALESCE(ps.Score, 0)) AS TotalScore,
        AVG(COALESCE(ps.Score, 0)) AS AvgScore,
        MAX(COALESCE(ps.ViewCount, 0)) AS MaxViews,
        MIN(ps.CreationDate) AS FirstPostDate,
        MAX(ps.CreationDate) AS LastPostDate,
        DATEDIFF(DAY, MIN(ps.CreationDate), MAX(ps.CreationDate)) AS ActiveDays,
        CASE 
            WHEN COUNT(DISTINCT ps.PostId) > 100 THEN 'Veteran'
            WHEN COUNT(DISTINCT ps.PostId) > 50 THEN 'Experienced'
            WHEN COUNT(DISTINCT ps.PostId) > 10 THEN 'Active'
            ELSE 'Newbie'
        END AS UserCategory
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE ps.PostId IS NOT NULL OR u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END AS PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS PopularityRank,
        STRING_AGG(DISTINCT ps.Title, ' | ') AS SampleQuestions,
        AVG(ps.Score) AS AvgQuestionScore,
        AVG(ps.ViewCount) AS AvgQuestionViews
    FROM Tags t
    LEFT JOIN (
        SELECT Id, Title, Score, ViewCount, Tags
        FROM Posts 
        WHERE PostTypeId = 1 AND Tags IS NOT NULL
    ) ps ON ps.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
ComplexPostAnalysis AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.PostTypeDesc,
        ps.OwnerUserId,
        ps.CreationDate,
        ps.AgeInDays,
        ps.EngagementScore,
        ps.ScoreTier,
        ps.UserPostRank,
        ps.TagLength,
        ps.CleanTags,
        UA.DisplayName AS OwnerName,
        UA.Reputation AS OwnerReputation,
        UA.TotalScore AS OwnerTotalScore,
        UA.QuestionCount AS OwnerQuestions,
        UA.AnswerCount AS OwnerAnswers,
        UA.ActiveDays AS OwnerActiveDays,
        UA.UserCategory AS OwnerCategory,
        TA.TagName AS PrimaryTag,
        TA.PopularityLevel AS TagPopularity,
        TA.PopularityRank AS TagRank,
        TA.AvgQuestionScore AS TagAvgScore,
        CASE 
            WHEN ps.PostTypeId = 1 AND ps.AnswerCount = 0 THEN 'Unanswered'
            WHEN ps.PostTypeId = 1 AND ps.AnswerCount > 0 AND ps.AcceptedAnswerId IS NOT NULL THEN 'Answered - Accepted'
            WHEN ps.PostTypeId = 1 AND ps.AnswerCount > 0 AND ps.AcceptedAnswerId IS NULL THEN 'Answered - Not Accepted'
            ELSE 'Other'
        END AS QuestionStatus,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM PostStats WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN ps.Score < (SELECT AVG(Score) FROM PostStats WHERE PostTypeId = 1) THEN 'Below Average'
            ELSE 'Average'
        END AS ScoreComparison,
        DENSE_RANK() OVER (ORDER BY ps.EngagementScore DESC) AS EngagementRank,
        NTH_VALUE(ps.Title, 1) OVER (ORDER BY ps.EngagementScore DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS MostEngagingPostTitle,
        LAG(ps.Title) OVER (ORDER BY ps.CreationDate) AS PreviousPostTitle,
        LEAD(ps.Title) OVER (ORDER BY ps.CreationDate) AS NextPostTitle,
        NTILE(4) OVER (ORDER BY ps.ViewCount) AS ViewQuartile,
        -- Complex calculation for popularity index combining multiple factors
        (ps.Score * 0.3 + ps.ViewCount * 0.2 + ps.AnswerCount * 0.25 + ps.CommentCount * 0.15 + 
        CASE WHEN ps.AcceptedAnswerId IS NOT NULL THEN 10 ELSE 0 END * 0.1) AS PopularityIndex,
        -- String operations and manipulations
        TRIM(UPPER(ps.Tags)) AS TagsUpperTrimmed,
        REGEXP_REPLACE(ps.CleanTags, '<|>', '') AS CleanTagList,
        CASE 
            WHEN ps.CleanTags LIKE '%<java>%' THEN 'Java Related'
            WHEN ps.CleanTags LIKE '%<python>%' THEN 'Python Related'
            WHEN ps.CleanTags LIKE '%<javascript>%' THEN 'JavaScript Related'
            ELSE 'Other Language'
        END AS LanguageCategory
    FROM PostStats ps
    JOIN UserActivity UA ON ps.OwnerUserId = UA.UserId
    LEFT JOIN TagAnalysis TA ON ps.CleanTags LIKE '%' || TA.TagName || '%'
    WHERE ps.PostId IN (
        SELECT Id FROM Posts WHERE PostTypeId IN (1, 2) AND OwnerUserId IS NOT NULL
    )
),
FinalAnalysis AS (
    SELECT
        CPA.PostId,
        CPA.Title,
        CPA.Score,
        CPA.ViewCount,
        CPA.AnswerCount,
        CPA.CommentCount,
        CPA.FavoriteCount,
        CPA.PostTypeDesc,
        CPA.OwnerUserId,
        CPA.OwnerName,
        CPA.OwnerReputation,
        CPA.OwnerTotalScore,
        CPA.OwnerQuestions,
        CPA.OwnerAnswers,
        CPA.OwnerActiveDays,
        CPA.OwnerCategory,
        CPA.PrimaryTag,
        CPA.TagPopularity,
        CPA.TagRank,
        CPA.TagAvgScore,
        CPA.QuestionStatus,
        CPA.ScoreComparison,
        CPA.EngagementScore,
        CPA.EngagementRank,
        CPA.MostEngagingPostTitle,
        CPA.PreviousPostTitle,
        CPA.NextPostTitle,
        CPA.ViewQuartile,
        CPA.PopularityIndex,
        CPA.TagsUpperTrimmed,
        CPA.CleanTagList,
        CPA.LanguageCategory,
        -- Complex conditional expressions
        CASE 
            WHEN CPA.OwnerCategory = 'Veteran' AND CPA.ViewCount > 1000 AND CPA.Score > 50 THEN 'High Impact Veteran Post'
            WHEN CPA.OwnerCategory = 'Experienced' AND CPA.TagPopularity = 'Very Popular' THEN 'Popular Expert Post'
            WHEN CPA.PopularityIndex > 100 AND CPA.Score > 25 AND CPA.ViewCount > 500 THEN 'Trending Post'
            WHEN CPA.QuestionStatus = 'Unanswered' AND CPA.AgeInDays < 7 THEN 'Recent Unanswered'
            ELSE 'Standard Post'
        END AS PostClassification,
        -- Set operations example with union
        COALESCE(CPA.PrimaryTag, 'No Tag') AS EffectiveTag,
        -- NULL handling
        CASE 
            WHEN CPA.OwnerName IS NULL THEN 'Deleted User'
            ELSE CPA.OwnerName
        END AS AuthorName,
        -- Calculated fields from existing fields
        ROUND(CPA.PopularityIndex / (CPA.AgeInDays + 1), 2) AS normalized_popularity_score,
        -- Window function with complex partitioning
        AVG(CPA.Score) OVER (PARTITION BY CPA.OwnerUserId, CPA.PostTypeDesc) AS OwnerTypeAvgScore,
        -- Correlated subquery
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = CPA.PostId AND c.UserId = CPA.OwnerUserId) AS OwnerCommentsCount
    FROM ComplexPostAnalysis CPA
)
SELECT 
    PostId,
    Title,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    PostTypeDesc,
    OwnerUserId,
    OwnerName,
    OwnerReputation,
    OwnerTotalScore,
    OwnerQuestions,
    OwnerAnswers,
    OwnerActiveDays,
    OwnerCategory,
    PrimaryTag,
    TagPopularity,
    TagRank,
    TagAvgScore,
    QuestionStatus,
    ScoreComparison,
    EngagementScore,
    EngagementRank,
    MostEngagingPostTitle,
    PreviousPostTitle,
    NextPostTitle,
    ViewQuartile,
    PopularityIndex,
    TagsUpperTrimmed,
    CleanTagList,
    LanguageCategory,
    PostClassification,
    EffectiveTag,
    AuthorName,
    normalized_popularity_score,
    OwnerTypeAvgScore,
    OwnerCommentsCount,
    -- Boolean expressions with NULL logic
    CASE 
        WHEN Score > 0 AND ViewCount IS NOT NULL AND AnswerCount IS NOT NULL THEN 'Active Post'
        WHEN Score <= 0 AND ViewCount > 0 THEN 'Quiet Post'
        ELSE 'Unknown'
    END AS PostActivityFlag
FROM FinalAnalysis
WHERE 
    -- Complex predicates
    (Score > 0 OR ViewCount > 0 OR AnswerCount > 0) 
    AND 
    (AuthorName IS NOT NULL OR PostClassification NOT LIKE '%Deleted%')
    AND 
    (CASE WHEN TagPopularity LIKE 'Very%' THEN TagAvgScore > 20 ELSE 1=1 END)
ORDER BY 
    -- Complex sorting
    normalized_popularity_score DESC,
    EngagementRank,
    Score DESC,
    ViewCount DESC
LIMIT 1000;