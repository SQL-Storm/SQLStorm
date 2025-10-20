WITH UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        STRING_AGG(DISTINCT p.Tags, ', ') as AllTags,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(TRUNC(CAST(SUM(p.Score) AS numeric) / COUNT(DISTINCT p.Id), 2) AS double precision)
            ELSE 0 
        END as AvgPostScore,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= TIMESTAMP '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostStats AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        p.LastActivityDate,
        CASE WHEN p.ParentId IS NOT NULL THEN 'Answer' ELSE 'Question' END as PostType,
        COALESCE(p.ParentId, p.Id) as QuestionId,
        CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400 AS integer) as DaysActive,
        CASE 
            WHEN p.Score > 100 THEN 'Gold'
            WHEN p.Score > 50 THEN 'Silver'
            WHEN p.Score > 10 THEN 'Bronze'
            ELSE 'None'
        END as ScoreTier,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as UserPostRank
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2010-01-01'
),
UserPerformance AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgPostScore,
        ua.PostRank,
        COUNT(DISTINCT ps.PostId) as ActivePosts,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.PostId END) as ActiveQuestions,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.PostId END) as ActiveAnswers,
        SUM(ps.Score) as TotalScore,
        AVG(ps.Score) as AvgScore,
        MAX(ps.DaysActive) as MaxDaysActive,
        STRING_AGG(DISTINCT ps.Title, '; ') as PostTitles,
        STRING_AGG(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Title END, '; ') as QuestionTitles,
        STRING_AGG(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Title END, '; ') as AnswerTitles,
        STRING_AGG(DISTINCT ps.Tags, ', ') as PostTags
    FROM UserActivity ua
    LEFT JOIN PostStats ps ON ua.UserId = ps.OwnerUserId
    WHERE ps.PostId IS NOT NULL OR ua.PostCount > 0
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.PostCount, ua.QuestionCount, ua.AnswerCount, ua.AvgPostScore, ua.PostRank
),
HighScoreUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        QuestionCount,
        AnswerCount,
        AvgPostScore,
        PostRank,
        ActivePosts,
        ActiveQuestions,
        ActiveAnswers,
        TotalScore,
        AvgScore,
        MaxDaysActive,
        PostTitles,
        QuestionTitles,
        AnswerTitles,
        PostTags,
        DENSE_RANK() OVER (ORDER BY TotalScore DESC) as TotalScoreRank,
        DENSE_RANK() OVER (ORDER BY AvgScore DESC) as AvgScoreRank,
        NULL::timestamp as LastPostDate,
        NULL::timestamp as LastCommentDate
    FROM UserPerformance
),
QuestionStats AS (
    SELECT 
        ps.QuestionId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.Tags,
        ps.OwnerUserId,
        ps.DaysActive,
        ps.ScoreTier,
        ROW_NUMBER() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.Score DESC) as UserQuestionRank,
        COUNT(*) OVER (PARTITION BY ps.OwnerUserId) as TotalUserQuestions,
        AVG(ps.Score) OVER (PARTITION BY ps.OwnerUserId) as AvgUserQuestionScore,
        CASE 
            WHEN ps.AnswerCount > 0 THEN 
                CAST(ps.Score AS double precision) / (ps.AnswerCount + 1)
            ELSE ps.Score
        END as ScorePerAnswer,
        MAX(ps.Score) OVER (PARTITION BY ps.OwnerUserId) as MaxUserQuestionScore,
        ps.OwnerUserId as QS_OwnerUserId
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
),
AnswerQuality AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.CommentCount,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.ParentId,
        ps.LastActivityDate,
        ps.DaysActive,
        ps.ScoreTier,
        ps.QuestionId,
        ROW_NUMBER() OVER (PARTITION BY ps.ParentId ORDER BY ps.Score DESC) as AnswerRank,
        COUNT(*) OVER (PARTITION BY ps.ParentId) as TotalAnswers,
        AVG(ps.Score) OVER (PARTITION BY ps.ParentId) as AvgAnswerScore,
        CASE WHEN ps.Score > 5 THEN 1 ELSE 0 END as HighScoreAnswer,
        CASE WHEN ps.OwnerUserId = (SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = ps.ParentId) THEN 1 ELSE 0 END as BestAnswer,
        ps.OwnerUserId as AQ_OwnerUserId
    FROM PostStats ps
    WHERE ps.PostTypeId = 2
)
SELECT 
    hsu.UserId,
    hsu.DisplayName,
    hsu.Reputation,
    hsu.PostCount,
    hsu.QuestionCount,
    hsu.AnswerCount,
    hsu.AvgPostScore,
    hsu.TotalScore,
    hsu.AvgScore,
    hsu.MaxDaysActive,
    hsu.PostTitles,
    hsu.QuestionTitles,
    hsu.AnswerTitles,
    hsu.PostTags,
    hsu.TotalScoreRank,
    hsu.AvgScoreRank,
    STRING_AGG(DISTINCT COALESCE(qs.Title, 'No Question'), ', ') as TopQuestions,
    STRING_AGG(DISTINCT COALESCE(aq.Title, 'No Answer'), ', ') as TopAnswers,
    STRING_AGG(DISTINCT qs.Tags, ', ') as QuestionTags,
    STRING_AGG(DISTINCT CASE WHEN qs.Score > 50 THEN qs.Title END, ', ') as HighScoreQuestions,
    STRING_AGG(DISTINCT CASE WHEN aq.Score > 50 THEN aq.Title END, ', ') as HighScoreAnswers,
    COUNT(DISTINCT CASE WHEN qs.Score > 50 THEN qs.QuestionId END) as HighScoreQuestionsCount,
    COUNT(DISTINCT CASE WHEN aq.Score > 50 THEN aq.PostId END) as HighScoreAnswersCount,
    CAST(TRUNC(AVG(CASE WHEN qs.Score > 50 THEN qs.Score END), 2) AS double precision) as AvgHighQuestionScore,
    CAST(TRUNC(AVG(CASE WHEN aq.Score > 50 THEN aq.Score END), 2) AS double precision) as AvgHighAnswerScore,
    COUNT(DISTINCT CASE WHEN qs.ScoreTier = 'Gold' THEN qs.QuestionId END) as GoldQuestionCount,
    COUNT(DISTINCT CASE WHEN aq.ScoreTier = 'Gold' THEN aq.PostId END) as GoldAnswerCount,
    CASE 
        WHEN hsu.PostCount > 0 AND COALESCE(hsu.TotalScore,0) > 0 THEN 
            CAST(TRUNC(CAST(hsu.TotalScore AS numeric) / hsu.PostCount, 2) AS double precision)
        ELSE 0 
    END as ScorePerPost,
    CASE 
        WHEN hsu.AnswerCount > 0 AND COALESCE(hsu.TotalScore,0) > 0 THEN 
            CAST(TRUNC(CAST(hsu.TotalScore AS numeric) / hsu.AnswerCount, 2) AS double precision)
        ELSE 0 
    END as ScorePerAnswer,
    CASE 
        WHEN hsu.QuestionCount > 0 THEN 
            CAST(TRUNC(CAST(hsu.AnswerCount AS numeric) / hsu.QuestionCount, 2) AS double precision)
        ELSE 0 
    END as AnswersPerQuestion,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - hsu.LastPostDate)) / 86400 AS integer) as DaysSinceLastPost,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - hsu.LastCommentDate)) / 86400 AS integer) as DaysSinceLastComment,
    CASE 
        WHEN hsu.Reputation > 10000 THEN 'Expert'
        WHEN hsu.Reputation > 5000 THEN 'Advanced'
        WHEN hsu.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as ReputationTier,
    CASE 
        WHEN hsu.PostCount > 50 AND hsu.Reputation > 5000 THEN 1
        WHEN hsu.PostCount > 20 AND hsu.Reputation > 2000 THEN 1
        ELSE 0
    END as ActiveContributor
FROM HighScoreUsers hsu
LEFT JOIN QuestionStats qs ON hsu.UserId = qs.QS_OwnerUserId AND qs.UserQuestionRank <= 5
LEFT JOIN AnswerQuality aq ON hsu.UserId = aq.AQ_OwnerUserId AND aq.AnswerRank <= 5
WHERE hsu.PostCount > 0
GROUP BY 
    hsu.UserId, hsu.DisplayName, hsu.Reputation, hsu.PostCount, hsu.QuestionCount, 
    hsu.AnswerCount, hsu.AvgPostScore, hsu.TotalScore, hsu.AvgScore, hsu.MaxDaysActive, 
    hsu.PostTitles, hsu.QuestionTitles, hsu.AnswerTitles, hsu.PostTags, hsu.TotalScoreRank, 
    hsu.AvgScoreRank, hsu.LastPostDate, hsu.LastCommentDate,
    CASE 
        WHEN hsu.Reputation > 10000 THEN 'Expert'
        WHEN hsu.Reputation > 5000 THEN 'Advanced'
        WHEN hsu.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END,
    CASE 
        WHEN hsu.PostCount > 50 AND hsu.Reputation > 5000 THEN 1
        WHEN hsu.PostCount > 20 AND hsu.Reputation > 2000 THEN 1
        ELSE 0
    END,
    hsu.UserId, hsu.DisplayName, hsu.Reputation, hsu.PostCount, hsu.QuestionCount, hsu.AnswerCount, hsu.AvgPostScore, hsu.TotalScore, hsu.AvgScore, hsu.MaxDaysActive, hsu.PostTitles, hsu.QuestionTitles, hsu.AnswerTitles, hsu.PostTags, hsu.TotalScoreRank, hsu.AvgScoreRank
HAVING 
    COUNT(DISTINCT qs.QuestionId) > 0 OR 
    COUNT(DISTINCT aq.PostId) > 0 OR
    COUNT(DISTINCT CASE WHEN qs.Score > 50 THEN qs.QuestionId END) > 0 OR
    COUNT(DISTINCT CASE WHEN aq.Score > 50 THEN aq.PostId END) > 0
ORDER BY hsu.TotalScore DESC, hsu.Reputation DESC, hsu.PostCount DESC
LIMIT 1000;