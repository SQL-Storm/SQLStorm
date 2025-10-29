-- {"query": "7659.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3538} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MIN(p.CreationDate) as FirstPostDate,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF('DAY', MIN(p.CreationDate), MAX(p.CreationDate)) as ActiveDays,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.AnswerCount ELSE 0 END), 0) as TotalAnswers,
        COALESCE(AVG(p.ViewCount), 0) as AvgViewCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(p.Id), 0), 0) as QuestionPercentage,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
            THEN COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) * 1.0 / NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0)
            ELSE 0 
        END as AvgAnswerScorePerQuestion
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2008-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        COALESCE(SUM(p.Score), 0) as TotalTagScore,
        COALESCE(COUNT(DISTINCT p.Id), 0) as QuestionCount,
        COALESCE(AVG(p.ViewCount), 0) as AvgViewCount,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TopUsers,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as rn
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2010-01-01 00:00:00'
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 10
),
PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN p.Title 
            ELSE SUBSTRING(p.Body, 1, 100) 
        END as PostTitle,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score > 0)
            ELSE 0 
        END as PositiveAnswers,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score < 0)
            ELSE 0 
        END as NegativeAnswers,
        COALESCE((SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2,3)), 0) as VoteCount,
        COALESCE((SELECT AVG(Score) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2), 0) as AvgAnswerScore,
        IIF(p.ViewCount > 1000 AND p.Score > 5 AND p.AnswerCount > 0, 1, 0) as HighValueQuestion, 
        CASE 
            WHEN LENGTH(p.Title) > 50 AND p.Score <= 0 THEN 'ProblematicTitle'
            WHEN LENGTH(p.Title) < 10 THEN 'ShortTitle'
            WHEN p.Tags IS NOT NULL AND p.Tags LIKE '%<%' THEN 'Tagged'
            ELSE 'Other'
        END as PostCategory
    FROM Posts p
    WHERE p.CreationDate >= '2010-01-01 00:00:00' AND p.PostTypeId IN (1,2)
),
ComplexActivity AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.HighViewQuestions,
        uas.Comments,
        uas.Badges,
        uas.FirstPostDate,
        uas.LastPostDate,
        uas.ActiveDays,
        uas.TotalScore,
        uas.QuestionScore,
        uas.AnswerScore,
        uas.TotalAnswers,
        uas.AvgViewCount,
        uas.QuestionPercentage,
        uas.AvgAnswerScorePerQuestion,
        IIF(uas.Reputation > 10000 AND uas.TotalPosts > 500 AND uas.Badges > 50, 1, 0) as PowerUserFlag,
        IIF(uas.Answers > uas.Questions * 1.5, 1, 0) as AnswerHeavyUser,
        IIF(uas.Comments > uas.Questions * 2 AND uas.TotalPosts > 100, 1, 0) as CommentHeavyUser,
        IIF(uas.Badges > uas.Questions * 0.5 AND uas.Reputation > 5000, 1, 0) as BadgeActiveUser,
        DATEDIFF('MONTH', uas.FirstPostDate, uas.LastPostDate) as MonthsActive,
        CASE 
            WHEN uas.QuestionPercentage > 50 AND uas.AnswerScore > uas.QuestionScore THEN 'QuestionFocused'
            WHEN uas.AnswerScore > uas.QuestionScore AND uas.Answers > 50 THEN 'AnswerFocused'
            WHEN uas.Comments > 100 THEN 'CommunityFocused'
            ELSE 'Generalist'
        END as UserFocusArea,
        CASE 
            WHEN uas.Reputation BETWEEN 1000 AND 5000 THEN 'Intermediate'
            WHEN uas.Reputation BETWEEN 5001 AND 15000 THEN 'Advanced'
            WHEN uas.Reputation > 15000 THEN 'Expert'
            ELSE 'Beginner'
        END as ReputationTier,
        IIF(uas.Reputation > 5000 AND uas.Badges > 20 AND uas.ActiveDays > 365, 1, 0) as LongTermActive,
        IIF(uas.TotalPosts > 100 AND uas.Answers > uas.Questions, 1, 0) as MoreAnswersThanQuestions,
        IIF(uas.QuestionScore > 0 AND uas.TotalPosts > 100, uas.QuestionScore * 1.0 / uas.TotalPosts, 0) as QuestionEfficiency,
        IIF(uas.AnswerScore > 0 AND uas.Answers > 10, uas.AnswerScore * 1.0 / uas.Answers, 0) as AnswerEfficiency,
        IIF(uas.Badges > 0, uas.Badges * 1.0 / uas.ActiveDays, 0) as BadgeRate,
        IIF(uas.TotalScore < 0, -1, 1) * IIF(uas.TotalScore = 0, 0, ABS(uas.TotalScore) / NULLIF(ABS(uas.QuestionScore + uas.AnswerScore), 0)) as ScoreRatio,
        CASE 
            WHEN uas.Reputation < 100 THEN 2
            WHEN uas.Reputation BETWEEN 100 AND 1000 THEN 1
            WHEN uas.Reputation BETWEEN 1001 AND 10000 THEN 0
            ELSE -1
        END as ReputationWeight 
    FROM UserActivityStats uas
    WHERE uas.TotalPosts > 0
),
UserPostEngagement AS (
    SELECT 
        ca.UserId,
        ca.Displayname,
        ca.Reputation,
        ca.TotalPosts,
        ca.Questions,
        ca.Answers,
        ca.ActiveDays,
        ca.TotalScore,
        ca.QuestionScore,
        ca.AnswerScore,
        ca.Badges,
        AVG(ps.Score) as AvgPostScore,
        MEDIAN(ps.Score) as MedianPostScore,
        MAX(ps.ViewCount) as MaxViewCount,
        MIN(ps.CreationDate) as FirstPost,
        MAX(ps.CreationDate) as LastPost,
        COALESCE(
            (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = ca.UserId AND PostTypeId = 1 AND AnswerCount > 0),
            0
        ) as QuestionsWithAnswers,
        COALESCE(
            (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = ca.UserId AND PostTypeId = 2 AND Score > 10),
            0
        ) as HighValueAnswers,
        COALESCE(
            (SELECT COUNT(*) FROM Votes WHERE UserId = ca.UserId AND VoteTypeId IN (2,3)),
            0
        ) as VotedPosts,
        CASE 
            WHEN ca.TotalPosts > 100 AND ca.Answers > ca.Questions THEN 1
            ELSE 0 
        END as AnswerRatioFlag,
        CASE 
            WHEN ca.Questions > 50 AND ca.QuestionScore > 100 THEN 1
            ELSE 0 
        END as QuestionQualityFlag,
        CASE 
            WHEN ca.Answers > 200 AND ca.AnswerScore > 500 THEN 1
            ELSE 0 
        END as AnswerQuantityFlag,
        (ca.QuestionScore + ca.AnswerScore) / NULLIF(ca.TotalPosts, 0) as ScorePerPost,
        (ca.Badges * 1.0) / NULLIF(ca.ActiveDays, 0) as BadgesPerDay,
        CASE 
            WHEN ca.Badges = 0 THEN 'None'
            WHEN ca.Badges BETWEEN 1 AND 5 THEN 'Few'
            WHEN ca.Badges BETWEEN 6 AND 20 THEN 'Some'
            WHEN ca.Badges BETWEEN 21 AND 50 THEN 'Many'
            ELSE 'Lots'
        END as BadgeLevel,
        CASE 
            WHEN ca.TotalScore > 1000 AND ca.QuestionScore > 500 THEN 'TopQuestioner'
            WHEN ca.TotalScore > 1000 AND ca.AnswerScore > 500 THEN 'TopAnswerer'
            WHEN ca.Badges > 30 THEN 'TopBadgeUser'
            ELSE 'RegularUser'
        END as UserTypeClassification,
        ROW_NUMBER() OVER (ORDER BY (ca.TotalScore + ca.Badges * 10) DESC) as OverallRank,
        RANK() OVER (ORDER BY ca.TotalScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY ca.Badges DESC) as BadgeRank,
        IIF(ca.UserId IN (SELECT UserId FROM Badges WHERE Name LIKE '%Scholar%'), 1, 0) as ScholarBadge,
        IIF(ca.UserId IN (SELECT UserId FROM Badges WHERE Name LIKE '%Teacher%'), 1, 0) as TeacherBadge,
        IIF(ca.UserId IN (SELECT UserId FROM Badges WHERE Name LIKE '%Peer%'), 1, 0) as PeerBadge,
        IIF(ca.UserId IN (SELECT UserId FROM Badges WHERE Name LIKE '%Student%'), 1, 0) as StudentBadge
    FROM ComplexActivity ca
    LEFT JOIN Posts ps ON ca.UserId = ps.OwnerUserId
    WHERE ca.ActiveDays > 0
    GROUP BY 
        ca.UserId, ca.DisplayName, ca.Reputation, ca.TotalPosts, ca.Questions, ca.Answers,
        ca.ActiveDays, ca.TotalScore, ca.QuestionScore, ca.AnswerScore, ca.Badges
)
SELECT 
    upa.UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.TotalPosts,
    upa.Questions,
    upa.Answers,
    upa.ActiveDays,
    upa.TotalScore,
    upa.QuestionScore,
    upa.AnswerScore,
    upa.Badges,
    ROUND(upa.AvgPostScore, 2) as AvgPostScore,
    ROUND(upa.MedianPostScore, 2) as MedianPostScore,
    upa.MaxViewCount,
    upa.FirstPost,
    upa.LastPost,
    upa.QuestionsWithAnswers,
    upa.HighValueAnswers,
    upa.VotedPosts,
    upa.AnswerRatioFlag,
    upa.QuestionQualityFlag,
    upa.AnswerQuantityFlag,
    ROUND(upa.ScorePerPost, 3) as ScorePerPost,
    ROUND(upa.BadgesPerDay, 4) as BadgesPerDay,
    upa.BadgeLevel,
    upa.UserTypeClassification,
    upa.OverallRank,
    upa.ScoreRank,
    upa.BadgeRank,
    upa.ScholarBadge,
    upa.TeacherBadge,
    upa.PeerBadge,
    upa.StudentBadge,
    CASE 
        WHEN upa.UserTypeClassification IN ('TopQuestioner', 'TopAnswerer') THEN 'Elite'
        WHEN upa.UserTypeClassification = 'TopBadgeUser' THEN 'Achiever'
        WHEN upa.Questions > 50 AND upa.Answers > 50 THEN 'Contributor'
        WHEN upa.TotalPosts > 100 THEN 'Regular'
        ELSE 'Beginner'
    END as ContributionLevel,
    IIF(upa.Reputation > 500 AND upa.Badges > 10 AND upa.ActiveDays > 180, 1, 0) as EngagedUser,
    IIF(upa.ScorePerPost > 5 AND upa.BadgeLevel IN ('Many', 'Lots'), 1, 0) as HighQualityEngagement,
    IIF(upa.VotedPosts > 500 OR upa.ScholarBadge = 1, 1, 0) as ActiveVoter,
    IIF(upa.ScholarBadge + upa.TeacherBadge + upa.PeerBadge + upa.StudentBadge > 2, 1, 0) as MultipleAchiever,
    IIF(upa.UserTypeClassification IN ('TopQuestioner', 'TopAnswerer', 'TopBadgeUser') AND 
        (upa.Badges > 20 OR upa.ScorePerPost > 10), 
        1, 0) as ExceptionalContributor,
    COUNT(*) OVER () as TotalUsers,
    (upa.OverallRank * 1.0 / COUNT(*) OVER ()) * 100 as PercentileRank,
    IIF(upa.BadgeLevel IN ('Many', 'Lots'), 1, 0) * (upa.Badges * 1.0 / 100) as BadgeEffectivenessScore
FROM UserPostEngagement upa
WHERE upa.TotalPosts > 0
ORDER BY upa.OverallRank ASC
LIMIT 1000;