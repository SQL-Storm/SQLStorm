-- {"query": "4096.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2497} 
WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.FavoriteCount,
        p.CommentCount,
        p.ViewCount AS PostViewCount,
        COUNT(DISTINCT c.Id) AS CommentCountTotal,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSequenceForUser,
        AVG(CAST(p.Score AS FLOAT)) OVER(PARTITION BY p.OwnerUserId) AS AvgUserPostScore,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.FavoriteCount, p.CommentCount, p.ViewCount
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(pe.PostCreationDate) AS LastPostDate,
        SUM(pe.PostScore) AS TotalPostScore,
        AVG(CAST(pe.PostViewCount AS FLOAT)) AS AvgPostViewCount,
        COUNT(CASE WHEN pe.PostSequenceForUser = 1 THEN 1 END) AS IsMostRecentPost,
        SUM(pe.UpVotes) AS TotalUpvotesReceived,
        SUM(pe.DownVotes) AS TotalDownvotesReceived,
        SUM(pe.FavoriteCount) AS TotalFavoritesReceived,
        COUNT(CASE WHEN pe.PostSequenceForUser BETWEEN 1 AND 5 THEN 1 END) AS Top5PostsCount,
        CASE WHEN u.Location IS NULL THEN 'Unknown' ELSE u.Location END AS UserLocation,
        CASE WHEN pe.AvgUserPostScore > 10 THEN 'High' WHEN pe.AvgUserPostScore > 0 THEN 'Medium' ELSE 'Low' END AS ReputationTierBasedOnAvgPostScore
    FROM Users u
    LEFT JOIN PostEngagement pe ON u.Id = pe.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes, pe.AvgUserPostScore, pe.PreviousPostScore
),
ComplexCalculations AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.UserCreationDate,
        ua.UserViews,
        ua.UserUpVotes,
        ua.UserDownVotes,
        ua.BadgeCount,
        ua.LastPostDate,
        ua.TotalPostScore,
        ua.AvgPostViewCount,
        ua.IsMostRecentPost,
        ua.TotalUpvotesReceived,
        ua.TotalDownvotesReceived,
        ua.TotalFavoritesReceived,
        ua.Top5PostsCount,
        ua.UserLocation,
        ua.ReputationTierBasedOnAvgPostScore,
        CASE
            WHEN ua.TotalPostScore > 1000 THEN 'Very High'
            WHEN ua.TotalPostScore > 500 THEN 'High'
            WHEN ua.TotalPostScore > 100 THEN 'Medium'
            ELSE 'Low'
        END AS ActivityScoreTier,
        DATEDIFF(day, ua.UserCreationDate, GETDATE()) AS DaysSinceCreation,
        ua.TotalUpvotesReceived - ua.TotalDownvotesReceived AS NetUpvotes,
        ua.TotalPostScore * 1.0 / NULLIF(DATEDIFF(day, ua.UserCreationDate, GETDATE()), 0) AS AvgDailyScore,
        IIF(ua.BadgeCount > 10, 'Pro', 'Novice') AS UserBadgeStatus,
        CASE WHEN ua.LastPostDate IS NOT NULL AND ua.LastPostDate < DATEADD(month, -6, GETDATE()) THEN 'Inactive' ELSE 'Active' END AS UserActivityStatus,
        LEN(ua.DisplayName) AS DisplayNameLength,
        UPPER(SUBSTRING(ua.DisplayName, 1, 3)) AS DisplayNamePrefix
    FROM UserActivity ua
),
RankedPosts AS (
    SELECT
        pe.PostId,
        pe.OwnerUserId,
        pe.PostTypeId,
        pe.PostCreationDate,
        pe.PostScore,
        pe.FavoriteCount,
        pe.CommentCount,
        pe.PostViewCount,
        pe.UpVotes,
        pe.DownVotes,
        pe.PostSequenceForUser,
        pe.AvgUserPostScore,
        pe.PreviousPostScore,
        RANK() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostScore DESC) AS ScoreRank,
        DENSE_RANK() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostCreationDate ASC) AS ChronologicalRank,
        SUM(pe.PostScore) OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScore
    FROM PostEngagement pe
    WHERE pe.OwnerUserId IS NOT NULL AND pe.PostTypeId = 1 -- Focus on Questions
),
QuestionDetails AS (
    SELECT
        rp.PostId,
        rp.OwnerUserId,
        rp.PostScore,
        rp.FavoriteCount,
        rp.UpVotes,
        rp.DownVotes,
        rp.PostViewCount,
        rp.CumulativeScore,
        rp.ScoreRank,
        rp.ChronologicalRank,
        rp.PostCreationDate,
        p.Title,
        p.AnswerCount,
        p.ClosedDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN DATEDIFF(day, p.ClosedDate, GETDATE()) ELSE NULL END AS DaysSinceClosed,
        CASE WHEN p.Tags LIKE '%<sql>%' THEN 1 ELSE 0 END AS IsSqlRelated
    FROM RankedPosts rp
    JOIN Posts p ON rp.PostId = p.Id
)
SELECT
    cc.UserId,
    cc.DisplayName,
    cc.Reputation,
    cc.UserCreationDate,
    cc.UserViews,
    cc.UserUpVotes,
    cc.UserDownVotes,
    cc.BadgeCount,
    cc.LastPostDate,
    cc.TotalPostScore,
    cc.AvgPostViewCount,
    cc.IsMostRecentPost,
    cc.TotalUpvotesReceived,
    cc.TotalDownvotesReceived,
    cc.TotalFavoritesReceived,
    cc.Top5PostsCount,
    cc.UserLocation,
    cc.ReputationTierBasedOnAvgPostScore,
    cc.ActivityScoreTier,
    cc.DaysSinceCreation,
    cc.NetUpvotes,
    cc.AvgDailyScore,
    cc.UserBadgeStatus,
    cc.UserActivityStatus,
    cc.DisplayNameLength,
    cc.DisplayNamePrefix,
    qd.PostId AS TopQuestionId,
    qd.Title AS TopQuestionTitle,
    qd.PostScore AS TopQuestionScore,
    qd.FavoriteCount AS TopQuestionFavorites,
    qd.AnswerCount AS TopQuestionAnswers,
    qd.DaysSinceClosed AS TopQuestionDaysSinceClosed,
    qd.IsSqlRelated AS TopQuestionIsSqlRelated,
    CASE
        WHEN qd.CumulativeScore IS NULL THEN 0
        WHEN qd.CumulativeScore > 5000 THEN 'Very High Cumulative Score'
        WHEN qd.CumulativeScore > 1000 THEN 'High Cumulative Score'
        ELSE 'Moderate Cumulative Score'
    END AS CumulativeScoreCategory,
    CASE
        WHEN qd.ClosedDate IS NOT NULL AND qd.ClosedDate < DATEADD(year, -1, GETDATE()) THEN 'ClosedOverAYearAgo'
        WHEN qd.ClosedDate IS NOT NULL THEN 'ClosedRecently'
        WHEN qd.AnswerCount > 50 THEN 'ManyAnswers'
        WHEN qd.AnswerCount > 10 THEN 'SeveralAnswers'
        ELSE 'FewAnswers'
    END AS QuestionStatusCategory,
    COALESCE(qd.AnswerCount, 0) AS NonNullAnswerCount,
    CASE WHEN qd.Title LIKE '%?%' THEN 1 ELSE 0 END AS TitleHasQuestionMark,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = qd.PostId AND pl.LinkTypeId = 1) AS LinkedPostsCount
FROM ComplexCalculations cc
LEFT JOIN QuestionDetails qd ON cc.UserId = qd.OwnerUserId AND qd.ScoreRank = 1
WHERE cc.Reputation > 100 OR cc.BadgeCount > 5
UNION ALL
SELECT
    cc.UserId,
    cc.DisplayName,
    cc.Reputation,
    cc.UserCreationDate,
    cc.UserViews,
    cc.UserUpVotes,
    cc.UserDownVotes,
    cc.BadgeCount,
    cc.LastPostDate,
    cc.TotalPostScore,
    cc.AvgPostViewCount,
    cc.IsMostRecentPost,
    cc.TotalUpvotesReceived,
    cc.TotalDownvotesReceived,
    cc.TotalFavoritesReceived,
    cc.Top5PostsCount,
    cc.UserLocation,
    cc.ReputationTierBasedOnAvgPostScore,
    cc.ActivityScoreTier,
    cc.DaysSinceCreation,
    cc.NetUpvotes,
    cc.AvgDailyScore,
    cc.UserBadgeStatus,
    cc.UserActivityStatus,
    cc.DisplayNameLength,
    cc.DisplayNamePrefix,
    NULL AS TopQuestionId,
    NULL AS TopQuestionTitle,
    NULL AS TopQuestionScore,
    NULL AS TopQuestionFavorites,
    NULL AS TopQuestionAnswers,
    NULL AS TopQuestionDaysSinceClosed,
    NULL AS TopQuestionIsSqlRelated,
    NULL AS CumulativeScoreCategory,
    NULL AS QuestionStatusCategory,
    0 AS NonNullAnswerCount,
    0 AS TitleHasQuestionMark,
    0 AS LinkedPostsCount
FROM ComplexCalculations cc
WHERE cc.Reputation <= 100 AND cc.BadgeCount <= 5;