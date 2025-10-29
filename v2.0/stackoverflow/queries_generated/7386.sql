-- {"query": "7386.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2173} 
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
        p.Body,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'SlightlyVoted'
            ELSE 'NoVotes'
        END AS VoteCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.Score) AS ScorePercentile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScorePerUser
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2020-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        u.CreationDate,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) AS AnswerCount,
        SUM(ps.Score) AS TotalScore,
        AVG(ps.Score) AS AvgScore,
        MAX(ps.CreationDate) AS LastPostDate,
        MIN(ps.CreationDate) AS FirstPostDate,
        DATEDIFF(CURRENT_DATE, MAX(ps.CreationDate)) AS DaysSinceLastPost,
        STRING_AGG(DISTINCT ps.Tags, ',') AS AllTags,
        CASE 
            WHEN COUNT(DISTINCT ps.Id) > 100 THEN 'Active'
            WHEN COUNT(DISTINCT ps.Id) > 50 THEN 'Moderate'
            WHEN COUNT(DISTINCT ps.Id) > 10 THEN 'Casual'
            ELSE 'Newbie'
        END AS UserActivityLevel
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.CreationDate >= '2015-01-01'
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate, u.CreationDate
),
AnswerQuality AS (
    SELECT 
        ps.Id AS AnswerId,
        ps.ParentId AS QuestionId,
        ps.OwnerUserId AS AnswererId,
        ps.Score AS AnswerScore,
        ps.CreationDate AS AnswerDate,
        ps.Body,
        ps.Title AS AnswerTitle,
        ps.PostType,
        ps.VoteCategory,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.ScorePercentile,
        ps.PreviousScore,
        ps.NextScore,
        ps.AvgScorePerUser,
        CASE 
            WHEN ps.Score > 10 AND ps.AcceptedAnswerId > 0 THEN 'HighQualityVerified'
            WHEN ps.Score > 10 THEN 'HighQuality'
            WHEN ps.Score >= 0 THEN 'StandardQuality'
            ELSE 'LowQuality'
        END AS QualityAssessment
    FROM PostStats ps
    WHERE ps.PostTypeId = 2
),
QuestionAnalysis AS (
    SELECT 
        ps.Id AS QuestionId,
        ps.OwnerUserId AS QuestionerId,
        ps.Score AS QuestionScore,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate AS QuestionDate,
        ps.Title AS QuestionTitle,
        ps.Tags,
        ps.Body AS QuestionBody,
        ps.PostType,
        ps.VoteCategory,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.ScorePercentile,
        ps.PreviousScore,
        ps.NextScore,
        ps.AvgScorePerUser,
        ps.AcceptedAnswerId,
        CASE 
            WHEN ps.AnswerCount >= 5 THEN 'WellAnswered'
            WHEN ps.AnswerCount >= 1 THEN 'Answered'
            ELSE 'Unanswered'
        END AS QuestionStatus,
        CASE 
            WHEN ps.Score > 50 THEN 'HighInterest'
            WHEN ps.Score > 10 THEN 'MediumInterest'
            ELSE 'LowInterest'
        END AS InterestLevel,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Answers a WHERE a.ParentId = ps.Id AND a.Score > ps.Score) 
            THEN 'ScoredBelowAnswers'
            ELSE 'ScoredAboveAnswers'
        END AS ScoreComparison
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
),
ComplexAnalytics AS (
    SELECT 
        qa.AnswerId,
        qa.QuestionId,
        qa.AnswererId,
        qa.AnswerScore,
        qa.AnswerDate,
        qa.AnswerTitle,
        qa.QualityAssessment,
        qa.UserPostRank,
        qa.ScoreRank,
        qa.ScorePercentile,
        qa.PreviousScore,
        qa.NextScore,
        qa.AvgScorePerUser,
        qa.ScoreComparison,
        u.DisplayName AS AnswererName,
        u.Reputation AS AnswererReputation,
        q.QuestionTitle,
        q.QuestionScore,
        q.QuestionDate,
        q.QuestionStatus,
        q.InterestLevel,
        q.ViewCount AS QuestionViews,
        q.AnswerCount AS QuestionAnswers,
        q.CommentCount AS QuestionComments,
        q.FavoriteCount AS QuestionFavorites,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            WHEN u.Reputation > 100 THEN 'Beginner'
            ELSE 'New' 
        END AS ExpertiseLevel,
        ROW_NUMBER() OVER (PARTITION BY qa.AnswererId ORDER BY qa.AnswerScore DESC) AS TopAnswerRank,
        RANK() OVER (ORDER BY (qa.AnswerScore + q.QuestionScore) DESC) AS CombinedPopularityRank
    FROM AnswerQuality qa
    JOIN QuestionAnalysis q ON qa.QuestionId = q.QuestionId
    JOIN Users u ON qa.AnswererId = u.Id
    WHERE qa.AnswerScore > 0 AND q.QuestionScore > 0
)
SELECT 
    ca.AnswerId,
    ca.QuestionId,
    ca.AnswererId,
    ca.AnswerScore,
    ca.AnswerDate,
    ca.AnswerTitle,
    ca.QualityAssessment,
    ca.UserPostRank,
    ca.ScoreRank,
    ca.ScorePercentile,
    ca.PreviousScore,
    ca.NextScore,
    ca.AvgScorePerUser,
    ca.ScoreComparison,
    ca.AnswererName,
    ca.AnswererReputation,
    ca.QuestionTitle,
    ca.QuestionScore,
    ca.QuestionDate,
    ca.QuestionStatus,
    ca.InterestLevel,
    ca.QuestionViews,
    ca.QuestionAnswers,
    ca.QuestionComments,
    ca.QuestionFavorites,
    ca.ExpertiseLevel,
    ca.TopAnswerRank,
    ca.CombinedPopularityRank,
    CASE 
        WHEN ca.AnswerScore > 50 AND ca.QuestionScore > 50 THEN 'VeryHighImpact'
        WHEN ca.AnswerScore > 25 AND ca.QuestionScore > 25 THEN 'HighImpact'
        WHEN ca.AnswerScore > 10 AND ca.QuestionScore > 10 THEN 'ModerateImpact'
        ELSE 'LowImpact'
    END AS ImpactLevel,
    ABS(ca.AnswerScore - ca.QuestionScore) AS ScoreDifference,
    CASE 
        WHEN ca.AnswerScore > ca.AvgScorePerUser THEN 'AboveAverage'
        WHEN ca.AnswerScore < ca.AvgScorePerUser THEN 'BelowAverage'
        ELSE 'Average'
    END AS PerformanceRelativeToUserAverage,
    COALESCE(ca.AnswerDate, '1900-01-01') AS FinalAnswerDate,
    COALESCE(ca.QuestionDate, '1900-01-01') AS FinalQuestionDate,
    CASE 
        WHEN ca.CombinedPopularityRank <= 10 THEN 'Top10'
        WHEN ca.CombinedPopularityRank <= 50 THEN 'Top50'
        WHEN ca.CombinedPopularityRank <= 100 THEN 'Top100'
        ELSE 'Below100'
    END AS PopularityTier,
    CASE 
        WHEN (ca.AnswerScore > 20 AND ca.QuestionScore > 20) 
        AND (ca.ExpertiseLevel IN ('Expert', 'Intermediate')) 
        THEN 'QualifiedHighValue'
        WHEN (ca.AnswerScore > 10 AND ca.QuestionScore > 10) 
        AND (ca.ExpertiseLevel IN ('Expert', 'Intermediate', 'Beginner')) 
        THEN 'ModerateValue'
        ELSE 'LowValue'
    END AS ValueAssessment
FROM ComplexAnalytics ca
WHERE ca.AnswerDate >= '2020-01-01'
  AND ca.QuestionDate >= '2020-01-01'
  AND ca.AnswerScore >= 0
  AND ca.QuestionScore >= 0
  AND ca.AnswererReputation >= 100
  AND ca.QuestionStatus IN ('WellAnswered', 'Answered')
ORDER BY ca.CombinedPopularityRank ASC, ca.AnswerScore DESC, ca.QuestionScore DESC
LIMIT 1000;