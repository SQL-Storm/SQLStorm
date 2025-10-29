-- {"query": "7403.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1809} 
WITH UserStats AS (
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
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT p.Tags, ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY AVGPostScore DESC) as RankByAvgScore,
        NTILE(10) OVER (ORDER BY Reputation) as Decile
    FROM UserStats
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        AvgPostScore,
        RankByReputation,
        RankByAvgScore
    FROM RankedUsers
    WHERE RankByReputation <= 2000
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.Id) as HistoryCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) as ModerationEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN ph.Id END) as EditEvents,
        AVG(DATEDIFF(day, ph.CreationDate, GETDATE())) as AvgDaysSinceActivity
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName
),
CombinedData AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.BadgeCount,
        tu.AvgPostScore,
        tu.RankByReputation,
        tu.RankByAvgScore,
        ua.HistoryCount,
        ua.ModerationEvents,
        ua.EditEvents,
        ua.AvgDaysSinceActivity,
        CASE WHEN tu.Reputation > 10000 THEN 'Expert' 
             WHEN tu.Reputation > 5000 THEN 'Advanced' 
             WHEN tu.Reputation > 1000 THEN 'Intermediate'
             ELSE 'Beginner' END as UserLevel,
        COALESCE(tu.AllTags, '') as UserTags,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.Score > 10) as HighScorePosts,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 1) as AvgQuestionScore,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 2) as AvgAnswerScore
    FROM TopUsers tu
    LEFT JOIN UserActivity ua ON tu.UserId = ua.UserId
),
TagAnalysis AS (
    SELECT 
        cd.UserId,
        cd.DisplayName,
        STRING_AGG(DISTINCT SUBSTRING(cd.UserTags, 
            CASE WHEN CHARINDEX(',', cd.UserTags) > 0 THEN CHARINDEX(',', cd.UserTags) + 1 ELSE 1 END,
            CASE WHEN CHARINDEX(',', cd.UserTags, CHARINDEX(',', cd.UserTags) + 1) > 0 THEN 
                CHARINDEX(',', cd.UserTags, CHARINDEX(',', cd.UserTags) + 1) - CHARINDEX(',', cd.UserTags) - 1
                ELSE LEN(cd.UserTags) END), ', ') as PopularTags,
        COUNT(DISTINCT cd.QuestionCount) as QuestionsWithTags,
        COUNT(DISTINCT CASE WHEN cd.QuestionCount > 5 THEN cd.UserId END) as ActiveTagUsers
    FROM CombinedData cd
    GROUP BY cd.UserId, cd.DisplayName
),
FinalAnalysis AS (
    SELECT 
        cd.UserId,
        cd.DisplayName,
        cd.Reputation,
        cd.PostCount,
        cd.QuestionCount,
        cd.AnswerCount,
        cd.BadgeCount,
        cd.AvgPostScore,
        cd.RankByReputation,
        cd.RankByAvgScore,
        cd.HistoryCount,
        cd.ModerationEvents,
        cd.EditEvents,
        cd.AvgDaysSinceActivity,
        cd.UserLevel,
        COALESCE(ta.PopularTags, 'None') as PopularTags,
        cd.HighScorePosts,
        cd.AvgQuestionScore,
        cd.AvgAnswerScore,
        CASE 
            WHEN cd.Reputation > 10000 AND cd.HistoryCount > 100 THEN 'Highly Active'
            WHEN cd.Reputation > 5000 AND cd.HistoryCount > 50 THEN 'Active'
            WHEN cd.Reputation > 1000 AND cd.HistoryCount > 10 THEN 'Moderate'
            ELSE 'Low Activity'
        END as ActivityLevel,
        CASE 
            WHEN cd.AvgPostScore > 10 AND cd.HighScorePosts > 10 THEN 'High Scoring'
            WHEN cd.AvgPostScore > 5 AND cd.HighScorePosts > 5 THEN 'Moderate Scoring'
            ELSE 'Low Scoring'
        END as ScoreLevel,
        -- Complex null and string handling in calculated field
        COALESCE(NULLIF(cd.DisplayName, ''), 'Anonymous User') as EffectiveDisplayName,
        -- Calculated performance metrics
        ROUND((cd.Reputation * cd.PostCount * cd.BadgeCount) / NULLIF(cd.HistoryCount, 0), 2) as PerformanceRatio,
        -- Conditional window function
        CASE WHEN cd.RankByReputation <= 10 THEN 'Top 10' ELSE 'Others' END as AchievementTier,
        -- Aggregated string expression
        CONCAT(
            'User: ', cd.DisplayName,
            ' | Rank: ', cd.RankByReputation,
            ' | Score: ', ROUND(cd.AvgPostScore, 2),
            ' | Tags: ', COALESCE(ta.PopularTags, 'None')
        ) as UserSummary
    FROM CombinedData cd
    LEFT JOIN TagAnalysis ta ON cd.UserId = ta.UserId
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostCount,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.BadgeCount,
    fa.AvgPostScore,
    fa.HistoryCount,
    fa.ModerationEvents,
    fa.EditEvents,
    fa.AvgDaysSinceActivity,
    fa.UserLevel,
    fa.PopularTags,
    fa.ActivityLevel,
    fa.ScoreLevel,
    fa.EffectiveDisplayName,
    fa.PerformanceRatio,
    fa.AchievementTier,
    fa.UserSummary,
    -- Complex date arithmetic
    DATEADD(day, -30, GETDATE()) as MonthAgo,
    -- Set operator example with multiple conditions
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p WHERE p.OwnerUserId = fa.UserId 
            AND p.CreationDate > DATEADD(day, -30, GETDATE())
        ) THEN 'Recent Contributor'
        ELSE 'Regular Contributor'
    END as ContributionStatus,
    -- Correlated subquery in SELECT clause
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = fa.UserId AND v.VoteTypeId = 2) as UpvoteCount
FROM FinalAnalysis fa
WHERE (
    fa.Reputation > 1000 
    OR fa.PostCount > 50 
    OR fa.HistoryCount > 100
)
AND fa.AvgDaysSinceActivity IS NOT NULL
ORDER BY fa.Reputation DESC, fa.PostCount DESC, fa.HistoryCount DESC
OFFSET 1000 ROWS
FETCH NEXT 500 ROWS ONLY;