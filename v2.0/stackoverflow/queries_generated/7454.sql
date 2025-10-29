-- {"query": "7454.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2420} 
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
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COALESCE(p.Title, 'No Title') AS CleanTitle,
        CASE 
            WHEN p.Tags IS NULL OR p.Tags = '' THEN 0 
            ELSE (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '>', ''))) / 2 + 1
        END AS TagCount,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        p.Score - LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS ScoreChange
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(YEAR, -2, GETDATE())
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) AS Answers,
        SUM(COALESCE(ps.Score, 0)) AS TotalScore,
        AVG(COALESCE(ps.Score, 0)) AS AvgScore,
        MAX(ps.CreationDate) AS LastActivity,
        CASE 
            WHEN MAX(ps.CreationDate) >= DATEADD(MONTH, -3, GETDATE()) THEN 'Active'
            WHEN MAX(ps.CreationDate) >= DATEADD(MONTH, -6, GETDATE()) THEN 'Moderately Active'
            ELSE 'Inactive'
        END AS ActivityStatus,
        COUNT(CASE WHEN ps.Score > 0 THEN 1 END) AS PositiveScorePosts,
        COUNT(CASE WHEN ps.Score < 0 THEN 1 END) AS NegativeScorePosts,
        COUNT(DISTINCT ps.ParentId) AS AnsweredQuestions,
        CAST(COUNT(CASE WHEN ps.PostTypeId = 1 THEN 1 END) AS FLOAT) / NULLIF(COUNT(DISTINCT ps.ParentId), 0) AS AvgAnswersPerQuestion
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TopPosts AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.Title,
        ps.Tags,
        ps.PostType,
        ps.CleanTitle,
        ps.TagCount,
        ps.UserPostRank,
        ps.GlobalScoreRank,
        ps.AvgUserScore,
        ps.ScoreChange,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM PostStats WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN ps.Score > 0 THEN 'Positive'
            ELSE 'Non-Positive'
        END AS ScoreCategory,
        CASE 
            WHEN ps.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'No Answers'
        END AS AnswerStatus,
        CASE 
            WHEN ps.ViewCount > 1000 THEN 'High Traffic'
            WHEN ps.ViewCount > 100 THEN 'Medium Traffic'
            ELSE 'Low Traffic'
        END AS TrafficLevel,
        ROW_NUMBER() OVER (ORDER BY ps.Score DESC) AS RankByScore,
        RANK() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.Score DESC) AS UserRankByScore
    FROM PostStats ps
    WHERE ps.Score > 0
),
UserRanking AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.DisplayName,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.AccountId,
        ua.TotalPosts,
        ua.Questions,
        ua.Answers,
        ua.TotalScore,
        ua.AvgScore,
        ua.LastActivity,
        ua.ActivityStatus,
        ua.PositiveScorePosts,
        ua.NegativeScorePosts,
        ua.AnsweredQuestions,
        ua.AvgAnswersPerQuestion,
        DENSE_RANK() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY ua.TotalScore DESC) AS TotalScoreRank,
        DENSE_RANK() OVER (ORDER BY ua.Questions DESC) AS QuestionsRank,
        DENSE_RANK() OVER (ORDER BY ua.Answers DESC) AS AnswersRank,
        CASE 
            WHEN ua.TotalPosts > 100 AND ua.Reputation > 5000 THEN 'Elite Contributor'
            WHEN ua.TotalPosts > 50 AND ua.Reputation > 2000 THEN 'Advanced Contributor'
            WHEN ua.TotalPosts > 10 AND ua.Reputation > 500 THEN 'Contributor'
            ELSE 'Regular User'
        END AS ContributorTier,
        (ua.PositiveScorePosts * 1.0 / NULLIF(ua.TotalPosts, 0)) * 100 AS PositiveScoreRatio
    FROM UserActivity ua
),
PostTagAnalysis AS (
    SELECT 
        tp.Id,
        tp.PostTypeId,
        tp.OwnerUserId,
        tp.Score,
        tp.ViewCount,
        tp.AnswerCount,
        tp.CommentCount,
        tp.FavoriteCount,
        tp.CreationDate,
        tp.Title,
        tp.Tags,
        tp.PostType,
        tp.CleanTitle,
        tp.TagCount,
        tp.UserPostRank,
        tp.GlobalScoreRank,
        tp.AvgUserScore,
        tp.ScoreChange,
        tp.ScoreCategory,
        tp.AnswerStatus,
        tp.TrafficLevel,
        tp.RankByScore,
        tp.UserRankByScore,
        STRING_AGG(
            CASE 
                WHEN tp.Tags IS NOT NULL AND tp.Tags != ''
                THEN SUBSTRING(tp.Tags, 2, LEN(tp.Tags) - 2)
                ELSE NULL
            END, 
            ', '
        ) AS AllTags,
        COUNT(DISTINCT CASE WHEN tp.Tags IS NOT NULL AND tp.Tags != '' THEN 1 END) AS TaggedPosts,
        AVG(tp.TagCount) OVER () AS AvgTagCount,
        COUNT(*) OVER () AS TotalTaggedPosts
    FROM TopPosts tp
    GROUP BY tp.Id, tp.PostTypeId, tp.OwnerUserId, tp.Score, tp.ViewCount, tp.AnswerCount, 
             tp.CommentCount, tp.FavoriteCount, tp.CreationDate, tp.Title, tp.Tags, tp.PostType, 
             tp.CleanTitle, tp.TagCount, tp.UserPostRank, tp.GlobalScoreRank, tp.AvgUserScore, 
             tp.ScoreChange, tp.ScoreCategory, tp.AnswerStatus, tp.TrafficLevel, tp.RankByScore, 
             tp.UserRankByScore
),
QualityPosts AS (
    SELECT 
        pta.*,
        ur.ReputationRank,
        ur.TotalScoreRank,
        ur.QuestionsRank,
        ur.AnswersRank,
        ur.ContributorTier,
        ur.PositiveScoreRatio,
        CASE 
            WHEN pta.Score > 100 AND pta.ViewCount > 1000 THEN 'High Quality'
            WHEN pta.Score > 50 AND pta.ViewCount > 500 THEN 'Medium Quality'
            WHEN pta.Score > 10 AND pta.ViewCount > 100 THEN 'Low Quality'
            ELSE 'Very Low Quality'
        END AS QualityLevel,
        CASE 
            WHEN pta.Score > (SELECT AVG(Score) FROM TopPosts) 
            AND pta.ViewCount > (SELECT AVG(ViewCount) FROM TopPosts)
            AND pta.AnswerCount > 0 THEN 'High Impact'
            WHEN pta.Score > (SELECT AVG(Score) FROM TopPosts) 
            AND pta.ViewCount > (SELECT AVG(ViewCount) FROM TopPosts) THEN 'Moderate Impact'
            ELSE 'Minimal Impact'
        END AS ImpactLevel,
        pta.CreationDate - DATEADD(DAY, -7, GETDATE()) AS DaysSinceCreation,
        CASE 
            WHEN pta.ViewCount > 1000 THEN 'Popular'
            WHEN pta.ViewCount > 100 THEN 'Semi-Popular'
            ELSE 'Less Popular'
        END AS PopularityLevel
    FROM PostTagAnalysis pta
    INNER JOIN UserRanking ur ON pta.OwnerUserId = ur.UserId
),
FinalQuery AS (
    SELECT 
        qp.*,
        CASE 
            WHEN qp.QualityLevel = 'High Quality' AND qp.ImpactLevel = 'High Impact' THEN 'Premium Post'
            WHEN qp.QualityLevel = 'High Quality' THEN 'High Quality Post'
            WHEN qp.QualityLevel = 'Medium Quality' THEN 'Medium Quality Post'
            WHEN qp.QualityLevel = 'Low Quality' THEN 'Low Quality Post'
            ELSE 'Very Low Quality Post'
        END AS PostClassification,
        CASE 
            WHEN qp.ReputationRank <= 10 THEN 'Top Performer'
            WHEN qp.ReputationRank <= 50 THEN 'High Performer'
            WHEN qp.ReputationRank <= 100 THEN 'Moderate Performer'
            ELSE 'Regular Performer'
        END AS PerformerCategory,
        CASE 
            WHEN qp.PositiveScoreRatio > 90 THEN 'Excellent Reputational Status'
            WHEN qp.PositiveScoreRatio > 70 THEN 'Good Reputational Status'
            WHEN qp.PositiveScoreRatio > 50 THEN 'Fair Reputational Status'
            ELSE 'Poor Reputational Status'
        END AS ReputationalStatus,
        ROW_NUMBER() OVER (ORDER BY qp.Score DESC, qp.ViewCount DESC) AS FinalRanking
    FROM QualityPosts qp
)
SELECT 
    FinalRanking,
    Id,
    PostTypeId,
    OwnerUserId,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    CreationDate,
    Title,
    Tags,
    PostType,
    CleanTitle,
    TagCount,
    UserPostRank,
    GlobalScoreRank,
    AvgUserScore,
    ScoreChange,
    ScoreCategory,
    AnswerStatus,
    TrafficLevel,
    RankByScore,
    UserRankByScore,
    ReputationRank,
    TotalScoreRank,
    QuestionsRank,
    AnswersRank,
    ContributorTier,
    PositiveScoreRatio,
    QualityLevel,
    ImpactLevel,
    DaysSinceCreation,
    PopularityLevel,
    PostClassification,
    PerformerCategory,
    ReputationalStatus
FROM FinalQuery
WHERE FinalRanking <= 5000
ORDER BY FinalRanking
OPTION (MAXDOP 8);