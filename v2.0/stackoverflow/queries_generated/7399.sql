-- {"query": "7399.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2391} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT b.Id) AS Badges,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2,3) THEN v.Id END) AS VoteCount,
        AVG(CAST(p.Score AS FLOAT)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '; ') AS AllTags,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostActivityRank,
        DENSE_RANK() OVER (ORDER BY u.ViewCount DESC) AS ViewRank,
        NTILE(100) OVER (ORDER BY u.Reputation) AS ReputationPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.ViewCount, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END AS PostType,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        LEN(p.Tags) - LEN(REPLACE(p.Tags, '>', '')) AS TagCount,
        CASE WHEN p.CommentCount > 0 THEN 1 ELSE 0 END AS HasComments,
        CASE WHEN p.AnswerCount > 0 THEN 1 ELSE 0 END AS HasAnswers,
        CASE WHEN p.FavoriteCount > 0 THEN 1 ELSE 0 END AS IsFavorited,
        (p.Score * p.ViewCount) AS ScoreViewProduct,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostSequence,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostDate,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreCategory,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            ELSE 'Normal'
        END AS ViewCategory,
        CASE 
            WHEN p.CreationDate >= '2023-01-01' THEN '2023'
            WHEN p.CreationDate >= '2022-01-01' THEN '2022'
            WHEN p.CreationDate >= '2021-01-01' THEN '2021'
            ELSE 'Older'
        END AS YearCategory,
        DATEDIFF(DAY, LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), p.CreationDate) AS DaysBetweenPosts
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.OwnerUserId IS NOT NULL
),
AggregatedStats AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.Questions,
        ua.Answers,
        ua.Badges,
        ua.Comments,
        ua.VoteCount,
        ua.AvgPostScore,
        ua.ReputationRank,
        ua.PostActivityRank,
        ua.ViewRank,
        ua.ReputationPercentile,
        AVG(pa.Score) AS AvgQuestionScore,
        MAX(pa.Score) AS MaxQuestionScore,
        MIN(pa.Score) AS MinQuestionScore,
        SUM(pa.ViewCount) AS TotalViews,
        AVG(pa.ViewCount) AS AvgViews,
        COUNT(CASE WHEN pa.PostType = 'Question' THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN pa.PostType = 'Answer' THEN 1 END) AS AnswerCount,
        SUM(CASE WHEN pa.HasAcceptedAnswer = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers,
        AVG(CASE WHEN pa.HasComments = 1 THEN 1 ELSE 0 END) AS AvgCommentsPerPost,
        AVG(CASE WHEN pa.HasAnswers = 1 THEN 1 ELSE 0 END) AS AvgAnswersPerPost,
        AVG(CASE WHEN pa.IsFavorited = 1 THEN 1 ELSE 0 END) AS AvgFavoritesPerPost,
        SUM(pa.ScoreViewProduct) AS TotalScoreViewProduct,
        MAX(pa.ScoreViewProduct) AS MaxScoreViewProduct,
        MIN(pa.ScoreViewProduct) AS MinScoreViewProduct,
        AVG(pa.DaysBetweenPosts) AS AvgDaysBetweenPosts,
        STRING_AGG(pa.Tags, '; ') AS AllUserTags,
        COUNT(DISTINCT pa.YearCategory) AS YearsActive
    FROM UserStats ua
    LEFT JOIN PostAnalysis pa ON ua.UserId = pa.OwnerUserId
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.TotalPosts, ua.Questions, ua.Answers, 
             ua.Badges, ua.Comments, ua.VoteCount, ua.AvgPostScore, ua.ReputationRank, 
             ua.PostActivityRank, ua.ViewRank, ua.ReputationPercentile
)
SELECT 
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.TotalPosts,
    a.Questions,
    a.Answers,
    a.Badges,
    a.Comments,
    a.VoteCount,
    a.AvgPostScore,
    a.ReputationRank,
    a.PostActivityRank,
    a.ViewRank,
    a.ReputationPercentile,
    CASE 
        WHEN a.TotalPosts >= 100 THEN 100
        WHEN a.TotalPosts >= 50 THEN 50
        WHEN a.TotalPosts >= 25 THEN 25
        ELSE 0
    END AS PostActivityLevel,
    CASE 
        WHEN a.Reputation >= 50000 THEN 'Elite'
        WHEN a.Reputation >= 10000 THEN 'Veteran'
        WHEN a.Reputation >= 5000 THEN 'Expert'
        WHEN a.Reputation >= 1000 THEN 'Intermediate'
        WHEN a.Reputation >= 100 THEN 'Beginner'
        ELSE 'Newbie'
    END AS ReputationTier,
    CASE 
        WHEN a.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average'
        WHEN a.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average'
        ELSE 'Average'
    END AS ReputationComparison,
    a.AvgQuestionScore,
    a.MaxQuestionScore,
    a.MinQuestionScore,
    a.TotalViews,
    a.AvgViews,
    a.QuestionCount,
    a.AnswerCount,
    a.AcceptedAnswers,
    a.AvgCommentsPerPost,
    a.AvgAnswersPerPost,
    a.AvgFavoritesPerPost,
    a.TotalScoreViewProduct,
    a.MaxScoreViewProduct,
    a.MinScoreViewProduct,
    a.AvgDaysBetweenPosts,
    a.AllUserTags,
    a.YearsActive,
    CASE 
        WHEN a.YearsActive > 2 THEN 'Active Long-term'
        WHEN a.YearsActive > 1 THEN 'Active Short-term'
        ELSE 'New User'
    END AS UserStatus,
    CASE 
        WHEN a.Questions > 0 AND a.Answers > 0 THEN 'Both Q&A'
        WHEN a.Questions > 0 THEN 'Questioner'
        WHEN a.Answers > 0 THEN 'Answerer'
        ELSE 'Neither'
    END AS UserRole,
    COALESCE(
        (SELECT TOP 1 Name 
         FROM Badges b 
         WHERE b.UserId = a.UserId 
         AND b.Class = 1 
         ORDER BY b.Date DESC), 
        'No Gold'
    ) AS RecentGoldBadge,
    COALESCE(
        (SELECT TOP 1 Name 
         FROM Badges b 
         WHERE b.UserId = a.UserId 
         AND b.Class = 2 
         ORDER BY b.Date DESC), 
        'No Silver'
    ) AS RecentSilverBadge,
    COALESCE(
        (SELECT TOP 1 Name 
         FROM Badges b 
         WHERE b.UserId = a.UserId 
         AND b.Class = 3 
         ORDER BY b.Date DESC), 
        'No Bronze'
    ) AS RecentBronzeBadge,
    CAST(
        (CASE WHEN a.Reputation > 1000 THEN 1 ELSE 0 END +
         CASE WHEN a.TotalPosts > 50 THEN 1 ELSE 0 END +
         CASE WHEN a.Questions > 20 THEN 1 ELSE 0 END +
         CASE WHEN a.Answers > 50 THEN 1 ELSE 0 END +
         CASE WHEN a.Badges > 20 THEN 1 ELSE 0 END) AS FLOAT
    ) * 20 AS UserEngagementScore,
    ROW_NUMBER() OVER (ORDER BY 
        CASE 
            WHEN a.Reputation > 1000 THEN 1
            WHEN a.Reputation > 500 THEN 2
            ELSE 3
        END,
        a.TotalPosts DESC
    ) AS CombinedRank,
    CASE 
        WHEN a.AvgPostScore > 5 THEN 'High Performing'
        WHEN a.AvgPostScore > 2 THEN 'Moderate Performing'
        ELSE 'Low Performing'
    END AS PerformanceTier,
    CASE 
        WHEN a.ViewRank <= 10 THEN 'Top Viewers'
        WHEN a.ViewRank <= 50 THEN 'High Viewers'
        WHEN a.ViewRank <= 200 THEN 'Average Viewers'
        ELSE 'Low Viewers'
    END AS ViewerRanking
FROM AggregatedStats a
WHERE a.Reputation > 500
  AND a.TotalPosts > 5
  AND (a.Questions > 0 OR a.Answers > 0)
  AND a.ReputationPercentile >= 10
  AND a.ReputationPercentile <= 90
ORDER BY a.Reputation DESC, a.TotalPosts DESC
OFFSET 0 ROWS
FETCH NEXT 200 ROWS ONLY;