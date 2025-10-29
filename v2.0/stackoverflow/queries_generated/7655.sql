-- {"query": "7655.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1863} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        STRING_AGG(DISTINCT COALESCE(p.Tags, ''), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) AS RankByReputation,
        DENSE_RANK() OVER (ORDER BY Views DESC) AS RankByViews,
        RANK() OVER (ORDER BY TotalQuestionScore DESC) AS RankByQuestionScore,
        NTILE(10) OVER (ORDER BY UpVotes - DownVotes DESC) AS EngagementTier
    FROM UserStats
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        PostCount,
        QuestionCount,
        AnswerCount,
        TotalQuestionScore,
        TotalAnswerScore,
        RankByReputation,
        RankByViews,
        RankByQuestionScore,
        EngagementTier
    FROM RankedUsers
    WHERE RankByReputation <= 1000
),
PostWithHistory AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryCreationDate,
        ph.UserId AS HistoryUserId,
        ph.Comment AS HistoryComment,
        ph.Text AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS LatestHistoryRank,
        COUNT(*) OVER (PARTITION BY p.Id) AS HistoryCount,
        CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN 1 ELSE 0 END AS StatusChangeCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2)
),
UserActivityPerDay AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        DATE(p.CreationDate) AS ActivityDate,
        COUNT(*) AS DailyPosts,
        SUM(p.Score) AS DailyScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS DailyQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS DailyAnswers
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, DATE(p.CreationDate)
),
ActivityStats AS (
    SELECT 
        UserId,
        DisplayName,
        ActivityDate,
        DailyPosts,
        DailyScore,
        DailyQuestions,
        DailyAnswers,
        LAG(DailyPosts, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate) AS PreviousDayPosts,
        LAG(DailyScore, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate) AS PreviousDayScore,
        AVG(DailyPosts) OVER (PARTITION BY UserId ORDER BY ActivityDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS WeeklyAvgPosts,
        AVG(DailyScore) OVER (PARTITION BY UserId ORDER BY ActivityDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS WeeklyAvgScore,
        CASE 
            WHEN LAG(DailyPosts, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate) > 0 
            THEN (DailyPosts::FLOAT - LAG(DailyPosts, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate)) / LAG(DailyPosts, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate) 
            ELSE NULL 
        END AS PostGrowthRate,
        CASE 
            WHEN LAG(DailyScore, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate) > 0 
            THEN (DailyScore::FLOAT - LAG(DailyScore, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate)) / LAG(DailyScore, 1) OVER (PARTITION BY UserId ORDER BY ActivityDate) 
            ELSE NULL 
        END AS ScoreGrowthRate
    FROM UserActivityPerDay uapd
    JOIN Users u ON uapd.UserId = u.Id
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.Views,
    tu.PostCount,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalQuestionScore,
    tu.TotalAnswerScore,
    tu.RankByReputation,
    tu.RankByViews,
    tu.RankByQuestionScore,
    tu.EngagementTier,
    pwh.PostId,
    pwh.Title,
    pwh.Score,
    pwh.ViewCount,
    pwh.CreationDate,
    pwh.HistoryCount,
    pwh.StatusChangeCount,
    pwh.PostHistoryTypeId,
    pwh.HistoryComment,
    pwh.HistoryText,
    pwh.HistoryCreationDate,
    pwh.LatestHistoryRank,
    ast.ActivityDate,
    ast.DailyPosts,
    ast.DailyScore,
    ast.DailyQuestions,
    ast.DailyAnswers,
    ast.PreviousDayPosts,
    ast.PreviousDayScore,
    ast.WeeklyAvgPosts,
    ast.WeeklyAvgScore,
    ast.PostGrowthRate,
    ast.ScoreGrowthRate,
    CASE 
        WHEN pwh.HistoryCount > 0 AND pwh.HistoryCount >= 5 THEN 'High Activity'
        WHEN pwh.HistoryCount > 1 THEN 'Moderate Activity'
        WHEN pwh.HistoryCount = 1 THEN 'Low Activity'
        ELSE 'No History'
    END AS ActivityLevel,
    CASE 
        WHEN tu.Reputation >= 10000 THEN 'Elite'
        WHEN tu.Reputation >= 5000 THEN 'Active'
        WHEN tu.Reputation >= 1000 THEN 'Regular'
        ELSE 'Beginner'
    END AS ReputationTier,
    CASE 
        WHEN ast.PostGrowthRate > 0.2 THEN 'Rising Star'
        WHEN ast.PostGrowthRate < -0.2 THEN 'Declining'
        WHEN ast.PostGrowthRate BETWEEN -0.2 AND 0.2 THEN 'Stable'
        ELSE 'No Growth Data'
    END AS ActivityTrend,
    COALESCE(tu.AllTags, 'No Tags') AS Tags,
    (SELECT STRING_AGG(Name, ', ') FROM Badges WHERE UserId = tu.UserId AND Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = tu.UserId AND Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges WHERE UserId = tu.UserId AND Class = 3) AS BronzeBadgeCount,
    ROUND(AVG(tu.Reputation) OVER (ORDER BY tu.RankByReputation), 2) AS AvgReputationUpToRank
FROM TopUsers tu
LEFT JOIN PostWithHistory pwh ON tu.UserId = pwh.OwnerUserId
LEFT JOIN ActivityStats ast ON tu.UserId = ast.UserId
WHERE tu.Reputation > 1000
AND (pwh.PostId IS NULL OR pwh.LatestHistoryRank = 1)
AND (ast.ActivityDate IS NULL OR ast.ActivityDate BETWEEN '2021-01-01' AND '2023-12-31')
ORDER BY 
    tu.RankByReputation ASC,
    tu.Reputation DESC,
    tu.PostCount DESC,
    pwh.Score DESC
LIMIT 10000;