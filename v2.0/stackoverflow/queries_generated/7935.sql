-- {"query": "7935.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2069} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(DISTINCT b.Id) as Badges,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT v.Id) as Votes,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0), 0) as QuestionPercentage,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC, COUNT(DISTINCT p.Id) DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TopUsersByReputation AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        TotalPosts,
        Questions,
        Answers,
        TotalScore,
        LastPostDate,
        Badges,
        Comments,
        Votes,
        QuestionPercentage,
        RankByScore,
        ReputationRank
    FROM UserActivityStats
    WHERE ReputationRank <= 1000
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END as QuestionStatus,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRankOverall,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevQuestionDate,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextQuestionDate
    FROM Posts p
    WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2010-01-01'
),
AnswerStats AS (
    SELECT 
        a.Id as AnswerId,
        a.PostId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        a.ParentId,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY a.Score DESC) as ScoreRankOverall,
        NTILE(4) OVER (ORDER BY a.Score DESC) as ScoreQuartile,
        AVG(a.Score) OVER (PARTITION BY a.ParentId) as AvgAnswerScore,
        CASE 
            WHEN (SELECT COUNT(*) FROM Posts WHERE ParentId = a.ParentId AND PostTypeId = 2 AND Score > 0) > 1 
            THEN 'HighlyVotedAnswers'
            ELSE 'StandardAnswers'
        END as AnswerType
    FROM Posts a
    WHERE a.PostTypeId = 2
    AND a.CreationDate >= '2010-01-01'
),
UserPerformance AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.Views,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.TotalScore,
        tu.LastPostDate,
        tu.Badges,
        tu.Comments,
        tu.Votes,
        tu.QuestionPercentage,
        tu.RankByScore,
        tu.ReputationRank,
        COALESCE(ROUND((tu.TotalScore * 100.0) / NULLIF(tu.Answers, 0), 2), 0) as AvgScorePerAnswer,
        COALESCE(ROUND((tu.TotalScore * 100.0) / NULLIF(tu.Questions, 0), 2), 0) as AvgScorePerQuestion,
        CASE 
            WHEN tu.TotalPosts >= 500 THEN 'Elite'
            WHEN tu.TotalPosts >= 100 THEN 'Veteran'
            WHEN tu.TotalPosts >= 10 THEN 'Regular'
            ELSE 'Beginner'
        END as UserLevel
    FROM TopUsersByReputation tu
),
QuestionQuality AS (
    SELECT 
        qs.QuestionId,
        qs.Title,
        qs.Score,
        qs.ViewCount,
        qs.AnswerCount,
        qs.CommentCount,
        qs.CreationDate,
        qs.OwnerUserId,
        qs.QuestionStatus,
        qs.ScoreRank,
        qs.ScoreRankOverall,
        qs.AvgScorePerUser,
        qs.PrevQuestionDate,
        qs.NextQuestionDate,
        CASE 
            WHEN qs.Score >= 100 THEN 'HighlyVoted'
            WHEN qs.Score >= 50 THEN 'ModeratelyVoted'
            ELSE 'LowVoted'
        END as VoteQuality,
        DATEDIFF('DAY', qs.CreationDate, NOW()) as DaysSinceCreation,
        CASE 
            WHEN qs.AnswerCount > 5 THEN 'WellAnswered'
            WHEN qs.AnswerCount > 0 THEN 'PartiallyAnswered'
            ELSE 'Unanswered'
        END as AnswerQuality
    FROM QuestionStats qs
),
AnswerComplexity AS (
    SELECT 
        asa.AnswerId,
        asa.QuestionId,
        asa.Score,
        asa.CreationDate,
        asa.OwnerUserId,
        asa.ParentId,
        asa.ScoreRank,
        asa.ScoreRankOverall,
        asa.ScoreQuartile,
        asa.AvgAnswerScore,
        asa.AnswerType,
        DATEDIFF('DAY', asa.CreationDate, NOW()) as DaysSinceAnswer,
        CASE 
            WHEN asa.Score >= 50 THEN 'HighImpact'
            WHEN asa.Score >= 25 THEN 'MediumImpact'
            ELSE 'LowImpact'
        END as ImpactLevel
    FROM AnswerStats asa
)
SELECT 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.Views,
    up.TotalPosts,
    up.Questions,
    up.Answers,
    up.TotalScore,
    up.LastPostDate,
    up.Badges,
    up.Comments,
    up.Votes,
    up.QuestionPercentage,
    up.RankByScore,
    up.ReputationRank,
    up.AvgScorePerAnswer,
    up.AvgScorePerQuestion,
    up.UserLevel,
    COUNT(DISTINCT qc.QuestionId) as QuestionsInCategory,
    COUNT(DISTINCT ac.AnswerId) as AnswersInCategory,
    COUNT(DISTINCT CASE WHEN qc.VoteQuality = 'HighlyVoted' THEN qc.QuestionId END) as HighVotedQuestions,
    COUNT(DISTINCT CASE WHEN qc.AnswerQuality = 'WellAnswered' THEN qc.QuestionId END) as WellAnsweredQuestions,
    COALESCE(ROUND(SUM(qc.Score) / NULLIF(COUNT(qc.QuestionId), 0), 2), 0) as AvgQuestionScore,
    COALESCE(ROUND(SUM(ac.Score) / NULLIF(COUNT(ac.AnswerId), 0), 2), 0) as AvgAnswerScore,
    COALESCE(ROUND(SUM(ac.Score * qc.Score) / NULLIF(COUNT(ac.AnswerId), 0), 2), 0) as ScoreMultiplier,
    MIN(DATEDIFF('DAY', qc.CreationDate, NOW())) as DaysSinceFirstQuestion,
    MAX(DATEDIFF('DAY', qc.CreationDate, NOW())) as DaysSinceLastQuestion,
    MIN(DATEDIFF('DAY', ac.CreationDate, NOW())) as DaysSinceFirstAnswer,
    MAX(DATEDIFF('DAY', ac.CreationDate, NOW())) as DaysSinceLastAnswer
FROM UserPerformance up
LEFT JOIN QuestionQuality qc ON up.UserId = qc.OwnerUserId
LEFT JOIN AnswerComplexity ac ON up.UserId = ac.OwnerUserId
WHERE up.Reputation >= 1000
GROUP BY 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.Views,
    up.TotalPosts,
    up.Questions,
    up.Answers,
    up.TotalScore,
    up.LastPostDate,
    up.Badges,
    up.Comments,
    up.Votes,
    up.QuestionPercentage,
    up.RankByScore,
    up.ReputationRank,
    up.AvgScorePerAnswer,
    up.AvgScorePerQuestion,
    up.UserLevel
HAVING 
    COUNT(DISTINCT qc.QuestionId) >= 5
    OR COUNT(DISTINCT ac.AnswerId) >= 10
ORDER BY 
    up.Reputation DESC,
    up.TotalScore DESC,
    COUNT(DISTINCT qc.QuestionId) DESC,
    COUNT(DISTINCT ac.AnswerId) DESC
LIMIT 500;