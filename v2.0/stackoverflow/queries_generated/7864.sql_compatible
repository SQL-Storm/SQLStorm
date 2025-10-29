WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavorites,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') AS Badges,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ', ') AS RecentQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
QuestionAnalysis AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.CreationDate,
        q.OwnerUserId,
        q.Tags,
        COALESCE(q.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
        CASE 
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN q.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus,
        DENSE_RANK() OVER (ORDER BY q.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS UserQuestionRank
    FROM Posts q
    WHERE q.PostTypeId = 1
),
AnswerAnalysis AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        a.LastActivityDate,
        a.LastEditDate,
        CASE 
            WHEN a.CreationDate > (SELECT MAX(CreationDate) FROM Posts WHERE Id = a.ParentId) - INTERVAL '1' DAY 
            THEN 'Recent'
            ELSE 'Old'
        END AS AnswerAge,
        DENSE_RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS ScoreRankWithinQuestion
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END AS TagPopularity,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 0) AS AssociatedQuestions
    FROM Tags t
),
ComplexQuery AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgScore,
        us.LastPostDate,
        us.TotalViews,
        us.TotalFavorites,
        us.BadgeCount,
        us.Badges,
        us.RecentQuestions,
        qa.QuestionId,
        qa.Title AS QuestionTitle,
        qa.Score AS QuestionScore,
        qa.ViewCount AS QuestionViewCount,
        qa.AnswerCount AS QuestionAnswerCount,
        qa.CommentCount AS QuestionCommentCount,
        qa.CreationDate AS QuestionCreationDate,
        qa.PostStatus,
        qa.ScoreRank,
        aa.AnswerId,
        aa.Score AS AnswerScore,
        aa.CreationDate AS AnswerCreationDate,
        aa.AnswerAge,
        aa.ScoreRankWithinQuestion,
        ta.TagName,
        ta.Count AS TagCount,
        ta.TagPopularity,
        CASE 
            WHEN qa.ScoreRank <= 5 AND aa.ScoreRankWithinQuestion = 1 THEN 'Top Question with Top Answer'
            WHEN qa.ScoreRank <= 5 THEN 'Top Question'
            WHEN aa.ScoreRankWithinQuestion = 1 THEN 'Top Answer'
            ELSE 'Regular Post'
        END AS PostImportance
    FROM UserStats us
    LEFT JOIN QuestionAnalysis qa ON us.UserId = qa.OwnerUserId
    LEFT JOIN AnswerAnalysis aa ON qa.QuestionId = aa.QuestionId
    LEFT JOIN (
        SELECT 
            t.TagName,
            t.Count,
            t.ExcerptPostId,
            t.WikiPostId,
            CASE 
                WHEN t.Count > 1000 THEN 'Popular'
                WHEN t.Count > 100 THEN 'Moderate'
                ELSE 'Niche'
            END AS TagPopularity
        FROM Tags t
        WHERE t.Count > 100
    ) ta ON qa.Tags LIKE '%' || ta.TagName || '%'
    WHERE 
        (qa.QuestionId IS NOT NULL OR aa.AnswerId IS NOT NULL)
        AND (
            qa.ScoreRank <= 5 
            OR aa.ScoreRankWithinQuestion = 1 
            OR ta.TagName IS NOT NULL
        )
    UNION ALL
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgScore,
        us.LastPostDate,
        us.TotalViews,
        us.TotalFavorites,
        us.BadgeCount,
        us.Badges,
        us.RecentQuestions,
        qa.QuestionId,
        qa.Title AS QuestionTitle,
        qa.Score AS QuestionScore,
        qa.ViewCount AS QuestionViewCount,
        qa.AnswerCount AS QuestionAnswerCount,
        qa.CommentCount AS QuestionCommentCount,
        qa.CreationDate AS QuestionCreationDate,
        qa.PostStatus,
        qa.ScoreRank,
        NULL AS AnswerId,
        NULL AS AnswerScore,
        NULL AS AnswerCreationDate,
        NULL AS AnswerAge,
        NULL AS ScoreRankWithinQuestion,
        ta.TagName,
        ta.Count AS TagCount,
        ta.TagPopularity,
        CASE 
            WHEN qa.ScoreRank <= 5 THEN 'Top Question'
            ELSE 'Regular Post'
        END AS PostImportance
    FROM UserStats us
    JOIN QuestionAnalysis qa ON us.UserId = qa.OwnerUserId
    LEFT JOIN (
        SELECT 
            t.TagName,
            t.Count,
            t.ExcerptPostId,
            t.WikiPostId,
            CASE 
                WHEN t.Count > 1000 THEN 'Popular'
                WHEN t.Count > 100 THEN 'Moderate'
                ELSE 'Niche'
            END AS TagPopularity
        FROM Tags t
        WHERE t.Count > 100
    ) ta ON qa.Tags LIKE '%' || ta.TagName || '%'
    WHERE 
        qa.ScoreRank <= 5 
        AND ta.TagName IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 
            FROM AnswerAnalysis aa 
            WHERE aa.QuestionId = qa.QuestionId
        )
)

SELECT 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    QuestionCount,
    AnswerCount,
    AvgScore,
    LastPostDate,
    TotalViews,
    TotalFavorites,
    BadgeCount,
    Badges,
    RecentQuestions,
    QuestionId,
    QuestionTitle,
    QuestionScore,
    QuestionViewCount,
    QuestionAnswerCount,
    QuestionCommentCount,
    QuestionCreationDate,
    PostStatus,
    ScoreRank,
    AnswerId,
    AnswerScore,
    AnswerCreationDate,
    AnswerAge,
    ScoreRankWithinQuestion,
    TagName,
    TagCount,
    TagPopularity,
    PostImportance,
    CASE 
        WHEN Reputation > 100000 AND PostCount > 1000 THEN 'Elite User'
        WHEN Reputation > 10000 AND PostCount > 200 THEN 'Veteran User'
        WHEN Reputation > 1000 THEN 'Active User'
        ELSE 'Regular User'
    END AS UserCategory,
    CASE 
        WHEN ABS(COALESCE(QuestionScore,0) - COALESCE(AvgScore,0)) > 50 THEN 'High Variance'
        WHEN ABS(COALESCE(QuestionScore,0) - COALESCE(AvgScore,0)) < 10 THEN 'Low Variance'
        ELSE 'Moderate Variance'
    END AS ScoreVarianceCategory,
    ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY QuestionCreationDate DESC) AS QuestionSequence,
    RANK() OVER (ORDER BY QuestionScore DESC) AS GlobalQuestionRank,
    DENSE_RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank,
    COUNT(*) OVER (PARTITION BY UserId) AS UserPostCount,
    AVG(QuestionScore) OVER (PARTITION BY UserId) AS UserAvgQuestionScore,
    MIN(QuestionCreationDate) OVER (PARTITION BY UserId) AS FirstQuestionDate,
    MAX(QuestionCreationDate) OVER (PARTITION BY UserId) AS LastQuestionDate
FROM ComplexQuery
WHERE QuestionId IS NOT NULL
ORDER BY 
    Reputation DESC,
    QuestionScore DESC,
    ScoreRank ASC,
    PostImportance DESC,
    QuestionTitle ASC
FETCH FIRST 1000 ROWS ONLY;