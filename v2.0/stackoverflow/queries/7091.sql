-- {"query": "7091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2520}
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
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
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 1
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NULL THEN 0
            ELSE NULL 
        END AS IsQuestionOpen,
        CASE 
            WHEN p.PostTypeId = 2 AND p.Score > 0 THEN 'HighlyVotedAnswer'
            WHEN p.PostTypeId = 2 AND p.Score <= 0 THEN 'LowVotedAnswer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            ELSE 'Other' 
        END AS PostCategory,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS GlobalRank,
        NTILE(100) OVER (ORDER BY p.Score) AS ScorePercentile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
      AND p.Score IS NOT NULL
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgesEarned,
        CASE 
            WHEN COUNT(DISTINCT p.Id) >= 1000 THEN 'Elite'
            WHEN COUNT(DISTINCT p.Id) >= 500 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) >= 100 THEN 'Contributor'
            ELSE 'Newbie' 
        END AS ContributionLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate
),
TopQuestions AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Tags,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.OwnerUserId,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.PostCategory,
        ps.ScoreRank,
        ps.GlobalRank,
        ps.ScorePercentile,
        CASE 
            WHEN ps.Score > 100 THEN 'HighlyVoted'
            WHEN ps.Score > 50 THEN 'ModeratelyVoted'
            WHEN ps.Score > 0 THEN 'LowVoted'
            ELSE 'Unpopular'
        END AS VotedLevel,
        CASE 
            WHEN ps.AnswerCount > 10 THEN 'WellAnswered'
            WHEN ps.AnswerCount > 5 THEN 'ModeratelyAnswered'
            WHEN ps.AnswerCount > 0 THEN 'PartiallyAnswered'
            ELSE 'Unanswered'
        END AS AnswerStatus,
        ps.Score - COALESCE(ps.PrevScore, 0) AS ScoreChange,
        ps.Score - COALESCE(ps.NextScore, 0) AS ScoreTrend
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
      AND ps.Score >= 0
),
QuestionAnalysis AS (
    SELECT 
        tq.PostId,
        tq.Title,
        tq.Tags,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount,
        tq.CommentCount,
        tq.OwnerUserId,
        tq.CreationDate,
        tq.LastActivityDate,
        tq.PostCategory,
        tq.ScoreRank,
        tq.GlobalRank,
        tq.ScorePercentile,
        tq.VotedLevel,
        tq.AnswerStatus,
        tq.ScoreChange,
        tq.ScoreTrend,
        CASE 
            WHEN tq.Score > 100 AND tq.AnswerCount > 0 THEN 1
            WHEN tq.Score > 50 AND tq.AnswerCount > 0 THEN 2
            WHEN tq.Score > 0 AND tq.AnswerCount > 0 THEN 3
            ELSE 4
        END AS QualityRank,
        DENSE_RANK() OVER (ORDER BY tq.AnswerCount DESC, tq.ViewCount DESC) AS PopularityRank,
        LAG(tq.PostId) OVER (ORDER BY tq.Score DESC) AS PrevQuestionId,
        LEAD(tq.PostId) OVER (ORDER BY tq.Score DESC) AS NextQuestionId,
        COUNT(*) OVER (PARTITION BY tq.OwnerUserId) AS UserQuestionsCount
    FROM TopQuestions tq
    WHERE tq.Score > 0
),
FilteredUsers AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.LastAccessDate,
        ua.TotalPosts,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.AvgPostScore,
        ua.LatestPostDate,
        ua.EarliestPostDate,
        ua.BadgeCount,
        ua.BadgesEarned,
        ua.ContributionLevel,
        CASE 
            WHEN ua.Reputation > 10000 THEN 'HighReputation'
            WHEN ua.Reputation > 5000 THEN 'MediumReputation'
            WHEN ua.Reputation > 1000 THEN 'LowReputation'
            ELSE 'NoviceReputation'
        END AS RepLevel,
        CASE 
            WHEN ua.Views > 10000 THEN 'HighViewUser'
            WHEN ua.Views > 5000 THEN 'MediumViewUser'
            WHEN ua.Views > 1000 THEN 'LowViewUser'
            ELSE 'BasicUser'
        END AS ViewLevel,
        DENSE_RANK() OVER (ORDER BY ua.Reputation DESC) AS RepRank
    FROM UserActivity ua
    WHERE ua.TotalPosts >= 10
) 
SELECT 
    fu.UserId,
    fu.Reputation,
    fu.Views,
    fu.UpVotes,
    fu.DownVotes,
    fu.LastAccessDate,
    fu.TotalPosts,
    fu.TotalQuestions,
    fu.TotalAnswers,
    fu.AvgPostScore,
    fu.LatestPostDate,
    fu.EarliestPostDate,
    fu.BadgeCount,
    fu.BadgesEarned,
    fu.ContributionLevel,
    fu.RepLevel,
    fu.ViewLevel,
    fu.RepRank,
    qa.PostId,
    qa.Title,
    qa.Tags,
    qa.Score,
    qa.ViewCount,
    qa.AnswerCount,
    qa.CommentCount,
    qa.CreationDate,
    qa.LastActivityDate,
    qa.PostCategory,
    qa.ScoreRank,
    qa.GlobalRank,
    qa.ScorePercentile,
    qa.VotedLevel,
    qa.AnswerStatus,
    qa.ScoreChange,
    qa.ScoreTrend,
    qa.QualityRank,
    qa.PopularityRank,
    qa.PrevQuestionId,
    qa.NextQuestionId,
    qa.UserQuestionsCount,
    CASE 
        WHEN ((fu.UpVotes * 1.0) / (fu.UpVotes + fu.DownVotes + 1)) > 0.8 THEN 'ExcellentVoter'
        WHEN ((fu.UpVotes * 1.0) / (fu.UpVotes + fu.DownVotes + 1)) > 0.6 THEN 'GoodVoter'
        WHEN ((fu.UpVotes * 1.0) / (fu.UpVotes + fu.DownVotes + 1)) > 0.4 THEN 'AverageVoter'
        ELSE 'PoorVoter'
    END AS VotingQuality,
    CASE 
        WHEN fu.TotalQuestions >= 100 THEN 'ProlificQuestioner'
        WHEN fu.TotalQuestions >= 50 THEN 'RegularQuestioner'
        WHEN fu.TotalQuestions >= 10 THEN 'OccasionalQuestioner'
        ELSE 'InfrequentQuestioner'
    END AS QuestionerLevel,
    CASE 
        WHEN fu.TotalAnswers >= 500 THEN 'ProlificAnswerer'
        WHEN fu.TotalAnswers >= 200 THEN 'RegularAnswerer'
        WHEN fu.TotalAnswers >= 50 THEN 'OccasionalAnswerer'
        ELSE 'InfrequentAnswerer'
    END AS AnswererLevel,
    ROW_NUMBER() OVER (PARTITION BY fu.UserId ORDER BY qa.Score DESC) AS QuestionRank,
    DENSE_RANK() OVER (ORDER BY qa.Score DESC) AS OverallQuestionRank,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1) - DENSE_RANK() OVER (ORDER BY qa.Score DESC) AS QuestionRankFromTop,
    CASE 
        WHEN fu.TotalPosts > 0 THEN 'Active'
        ELSE 'Inactive'
    END AS UserStatus,
    CASE 
        WHEN fu.Reputation > 5000 AND fu.BadgeCount > 10 THEN 'Veteran'
        WHEN fu.Reputation > 1000 AND fu.BadgeCount > 5 THEN 'Experienced'
        WHEN fu.Reputation > 100 AND fu.BadgeCount > 2 THEN 'Beginner'
        ELSE 'NewUser'
    END AS UserExperienceLevel,
    NULLIF(CAST(fu.Views AS FLOAT) / NULLIF(fu.TotalPosts, 0), 0) AS AvgViewsPerPost,
    NULLIF(CAST(fu.UpVotes AS FLOAT) / NULLIF(fu.DownVotes + 1, 0), 0) AS UpVoteRatio,
    NULLIF(CAST(COUNT(qa.PostId) AS FLOAT) / NULLIF(fu.TotalPosts, 0), 0) AS QuestionRatio,
    CASE 
        WHEN (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fu.UserId AND p.PostTypeId = 1) > 0 THEN 
            (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = fu.UserId AND p.PostTypeId = 1)
        ELSE 0
    END AS AvgQScore,
    CASE 
        WHEN (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fu.UserId AND p.PostTypeId = 2) > 0 THEN 
            (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = fu.UserId AND p.PostTypeId = 2)
        ELSE 0
    END AS AvgAScore,
    CASE 
        WHEN fu.Reputation > (SELECT AVG(u.Reputation) FROM Users u) THEN 'AboveAverage'
        WHEN fu.Reputation < (SELECT AVG(u.Reputation) FROM Users u) THEN 'BelowAverage'
        ELSE 'Average'
    END AS ReputationComparison
FROM FilteredUsers fu
LEFT JOIN QuestionAnalysis qa ON fu.UserId = qa.OwnerUserId
WHERE fu.UserId IN (
    SELECT DISTINCT OwnerUserId 
    FROM Posts 
    WHERE PostTypeId = 1 AND Score > 0
    INTERSECT
    SELECT DISTINCT UserId 
    FROM Badges 
    WHERE Name IN ('Great Question', 'Great Answer', 'Popular Question')
)
  AND qa.PostId IS NOT NULL
GROUP BY
    fu.UserId,
    fu.Reputation,
    fu.Views,
    fu.UpVotes,
    fu.DownVotes,
    fu.LastAccessDate,
    fu.TotalPosts,
    fu.TotalQuestions,
    fu.TotalAnswers,
    fu.AvgPostScore,
    fu.LatestPostDate,
    fu.EarliestPostDate,
    fu.BadgeCount,
    fu.BadgesEarned,
    fu.ContributionLevel,
    fu.RepLevel,
    fu.ViewLevel,
    fu.RepRank,
    qa.PostId,
    qa.Title,
    qa.Tags,
    qa.Score,
    qa.ViewCount,
    qa.AnswerCount,
    qa.CommentCount,
    qa.CreationDate,
    qa.LastActivityDate,
    qa.PostCategory,
    qa.ScoreRank,
    qa.GlobalRank,
    qa.ScorePercentile,
    qa.VotedLevel,
    qa.AnswerStatus,
    qa.ScoreChange,
    qa.ScoreTrend,
    qa.QualityRank,
    qa.PopularityRank,
    qa.PrevQuestionId,
    qa.NextQuestionId,
    qa.UserQuestionsCount
ORDER BY fu.RepRank ASC, qa.Score DESC
LIMIT 1000;