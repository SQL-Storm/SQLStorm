-- {"query": "7005.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3662} 
WITH PostStats AS (
    SELECT 
        p.Id,
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
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END AS PostTypeDesc,
        COALESCE(p.AnswerCount, 0) AS AnswerCountWithZero,
        COALESCE(p.CommentCount, 0) AS CommentCountWithZero,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCountWithZero,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.ViewCount) AS ViewPercentile,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostSequence,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevView,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        STDDEV(p.Score) OVER (PARTITION BY p.OwnerUserId) AS StdDevUserScore,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'BelowAverage'
            ELSE 'Average'
        END AS ScoreCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'HighTraffic'
            WHEN p.ViewCount > 100 THEN 'MediumTraffic'
            WHEN p.ViewCount > 0 THEN 'LowTraffic'
            ELSE 'NoTraffic'
        END AS TrafficLevel,
        LENGTH(p.Body) AS BodyLength,
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS CleanTags,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountSubquery,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id) AS VoteCountSubquery,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Name LIKE '%Question%' AND b.Date > p.CreationDate),
            0
        ) AS QuestionBadgesCount,
        (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.PostId = p.Id) AS EditsByUsersCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END AS PopularityLevel,
        (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags LIKE '%' || t.TagName || '%') AS QuestionCountWithTag,
        (SELECT AVG(p.ViewCount) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags LIKE '%' || t.TagName || '%') AS AvgViewsPerQuestion,
        STRING_AGG(DISTINCT u.DisplayName, ', ') AS UsersWhoUsedThisTag
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalPosts,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS TotalQuestions,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS TotalAnswers,
        (SELECT SUM(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalScore,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgScorePerPost,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id) AS TotalVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS TotalBadges,
        COALESCE(
            (SELECT COUNT(*) FROM PostHistory ph 
             WHERE ph.UserId = u.Id 
             AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
             AND ph.CreationDate > '2020-01-01'),
            0
        ) AS RecentEdits,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        RANK() OVER (ORDER BY u.Views DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY u.UpVotes DESC) AS UpVoteRank
    FROM Users u
    WHERE u.Id IN (
        SELECT DISTINCT OwnerUserId 
        FROM Posts 
        WHERE PostTypeId IN (1, 2)
        AND CreationDate > '2020-01-01'
    )
),
UserPostPerformance AS (
    SELECT 
        pu.Id,
        pu.DisplayName,
        pu.Reputation,
        pu.TotalPosts,
        pu.TotalQuestions,
        pu.TotalAnswers,
        pu.TotalScore,
        pu.AvgScorePerPost,
        pu.TotalVotes,
        pu.TotalBadges,
        pu.RecentEdits,
        pu.RepRank,
        pu.ViewRank,
        pu.UpVoteRank,
        ps.Id AS PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.PostTypeDesc,
        ps.ScoreRank,
        ps.ViewPercentile,
        ps.AvgUserScore,
        ps.StdDevUserScore,
        ps.ScoreCategory,
        ps.TrafficLevel,
        ps.TagArray,
        CASE 
            WHEN ps.Score > 5 AND ps.ViewCount > 100 THEN 'HighPerforming'
            WHEN ps.Score > 1 AND ps.ViewCount > 50 THEN 'MidPerforming'
            WHEN ps.Score >= 0 AND ps.ViewCount > 10 THEN 'LowPerforming'
            ELSE 'Poor'
        END AS PerformanceLevel,
        DATEDIFF('day', ps.CreationDate, ps.LastActivityDate) AS DaysSinceLastActivity,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.Id) AS CommentsOnPost,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 3) AS DownVotes,
        CASE 
            WHEN ps.PostTypeId = 1 AND ps.AnswerCount IS NOT NULL AND ps.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = ps.Id AND p2.Score > 0) 
            ELSE 0 
        END AS HighScoringAnswers,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ps.OwnerUserId AND b.Date >= ps.CreationDate AND b.Date <= ps.CreationDate + INTERVAL 30 DAY) AS BadgesInFirstMonth,
        COALESCE(
            (SELECT COUNT(*) FROM PostHistory ph 
             WHERE ph.PostId = ps.Id 
             AND ph.CreationDate BETWEEN ps.CreationDate AND ps.CreationDate + INTERVAL 7 DAY),
            0
        ) AS EditsInFirstWeek
    FROM TopUsers pu
    INNER JOIN PostStats ps ON pu.Id = ps.OwnerUserId
    WHERE ps.PostTypeDesc IN ('Question', 'Answer')
),
CombinedAnalysis AS (
    SELECT 
        upp.Id,
        upp.DisplayName,
        upp.Reputation,
        upp.TotalPosts,
        upp.TotalQuestions,
        upp.TotalAnswers,
        upp.TotalScore,
        upp.AvgScorePerPost,
        upp.TotalVotes,
        upp.TotalBadges,
        upp.RecentEdits,
        upp.RepRank,
        upp.ViewRank,
        upp.UpVoteRank,
        upp.PostId,
        upp.Title,
        upp.Score,
        upp.ViewCount,
        upp.AnswerCount,
        upp.CommentCount,
        upp.FavoriteCount,
        upp.PostTypeDesc,
        upp.ScoreRank,
        upp.ViewPercentile,
        upp.AvgUserScore,
        upp.StdDevUserScore,
        upp.ScoreCategory,
        upp.TrafficLevel,
        upp.PerformanceLevel,
        upp.DaysSinceLastActivity,
        upp.CommentsOnPost,
        upp.UpVotes,
        upp.DownVotes,
        upp.HighScoringAnswers,
        upp.BadgesInFirstMonth,
        upp.EditsInFirstWeek,
        CASE 
            WHEN upp.RepRank <= 50 AND upp.ViewRank <= 100 THEN 'TopPerformer'
            WHEN upp.RepRank <= 100 AND upp.ViewRank <= 200 THEN 'HighPerformer'
            WHEN upp.RepRank <= 200 AND upp.ViewRank <= 300 THEN 'MidPerformer'
            ELSE 'RegularPerformer'
        END AS UserPerformanceTier,
        CASE 
            WHEN upp.TrafficLevel = 'HighTraffic' AND upp.Score > 10 THEN 'HighEngagementHighScore'
            WHEN upp.TrafficLevel = 'HighTraffic' AND upp.Score <= 10 THEN 'HighEngagementLowScore'
            WHEN upp.TrafficLevel = 'MediumTraffic' AND upp.Score > 5 THEN 'MidEngagementHighScore'
            WHEN upp.TrafficLevel = 'LowTraffic' THEN 'LowEngagement'
            ELSE 'Unknown'
        END AS EngagementScoreCategory,
        ARRAY_AGG(upp.TagArray) AS AllUserTags,
        COUNT(upp.PostId) OVER (PARTITION BY upp.Id) AS PostsPerUser,
        AVG(upp.Score) OVER (PARTITION BY upp.Id) AS AvgScorePerUser,
        MAX(upp.ViewCount) OVER (PARTITION BY upp.Id) AS MaxViewsPerUser,
        MIN(upp.ViewCount) OVER (PARTITION BY upp.Id) AS MinViewsPerUser,
        STRING_AGG(upp.Title, ' | ') OVER (PARTITION BY upp.Id) AS UserPostTitles
    FROM UserPostPerformance upp
    GROUP BY 
        upp.Id, upp.DisplayName, upp.Reputation, upp.TotalPosts, upp.TotalQuestions, upp.TotalAnswers,
        upp.TotalScore, upp.AvgScorePerPost, upp.TotalVotes, upp.TotalBadges, upp.RecentEdits,
        upp.RepRank, upp.ViewRank, upp.UpVoteRank, upp.PostId, upp.Title, upp.Score, upp.ViewCount,
        upp.AnswerCount, upp.CommentCount, upp.FavoriteCount, upp.PostTypeDesc, upp.ScoreRank,
        upp.ViewPercentile, upp.AvgUserScore, upp.StdDevUserScore, upp.ScoreCategory, upp.TrafficLevel,
        upp.PerformanceLevel, upp.DaysSinceLastActivity, upp.CommentsOnPost, upp.UpVotes, upp.DownVotes,
        upp.HighScoringAnswers, upp.BadgesInFirstMonth, upp.EditsInFirstWeek
)
SELECT 
    DISTINCT 
    ca.Id,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.TotalQuestions,
    ca.TotalAnswers,
    ca.TotalScore,
    ca.AvgScorePerPost,
    ca.TotalVotes,
    ca.TotalBadges,
    ca.RecentEdits,
    ca.RepRank,
    ca.ViewRank,
    ca.UpVoteRank,
    ca.PostId,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.PostTypeDesc,
    ca.ScoreRank,
    ca.ViewPercentile,
    ca.AvgUserScore,
    ca.StdDevUserScore,
    ca.ScoreCategory,
    ca.TrafficLevel,
    ca.PerformanceLevel,
    ca.DaysSinceLastActivity,
    ca.CommentsOnPost,
    ca.UpVotes,
    ca.DownVotes,
    ca.HighScoringAnswers,
    ca.BadgesInFirstMonth,
    ca.EditsInFirstWeek,
    ca.UserPerformanceTier,
    ca.EngagementScoreCategory,
    ARRAY_LENGTH(ca.AllUserTags) AS TotalUniqueTagArrays,
    ca.PostsPerUser,
    ca.AvgScorePerUser,
    ca.MaxViewsPerUser,
    ca.MinViewsPerUser,
    LENGTH(ca.UserPostTitles) AS TotalTitleLength,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.Id AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.Id AND b.Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.Id AND b.Class = 3) AS BronzeBadgeCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.Id AND p.CreationDate > '2024-01-01') AS PostsThisYear,
    COALESCE(
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = ca.Id AND p.CreationDate > '2024-01-01'), 
        0
    ) AS AvgScoreThisYear,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = ca.Id AND ph.CreationDate > '2024-01-01') AS EditsThisYear,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.Id AND v.CreationDate > '2024-01-01'), 
        0
    ) AS VotesThisYear,
    STRING_AGG(UPPER(LEFT(unnest(ca.AllUserTags), 1)), ', ') AS FirstLettersOfTags,
    RANK() OVER (ORDER BY ca.TotalScore DESC, ca.ViewCount DESC) AS OverallRank,
    DENSE_RANK() OVER (ORDER BY ca.AvgScorePerPost DESC) AS AvgScoreRank,
    ROW_NUMBER() OVER (ORDER BY ca.RepRank ASC, ca.ViewRank ASC) AS CombinedRank
    
FROM CombinedAnalysis ca
WHERE ca.Reputation > 1000
    AND ca.TotalPosts > 5
    AND ca.PostTypeDesc IN ('Question')
    AND ca.TrafficLevel IN ('HighTraffic', 'MediumTraffic')
    AND ca.PerformanceLevel IN ('HighPerforming', 'MidPerforming')
    AND ca.ScoreCategory IN ('AboveAverage', 'Average')
    
GROUP BY 
    ca.Id, ca.DisplayName, ca.Reputation, ca.TotalPosts, ca.TotalQuestions, ca.TotalAnswers,
    ca.TotalScore, ca.AvgScorePerPost, ca.TotalVotes, ca.TotalBadges, ca.RecentEdits,
    ca.RepRank, ca.ViewRank, ca.UpVoteRank, ca.PostId, ca.Title, ca.Score, ca.ViewCount,
    ca.AnswerCount, ca.CommentCount, ca.FavoriteCount, ca.PostTypeDesc, ca.ScoreRank,
    ca.ViewPercentile, ca.AvgUserScore, ca.StdDevUserScore, ca.ScoreCategory, ca.TrafficLevel,
    ca.PerformanceLevel, ca.DaysSinceLastActivity, ca.CommentsOnPost, ca.UpVotes, ca.DownVotes,
    ca.HighScoringAnswers, ca.BadgesInFirstMonth, ca.EditsInFirstWeek, ca.UserPerformanceTier,
    ca.EngagementScoreCategory, ca.AllUserTags, ca.PostsPerUser, ca.AvgScorePerUser,
    ca.MaxViewsPerUser, ca.MinViewsPerUser, ca.UserPostTitles
    
HAVING 
    COUNT(ca.PostId) >= 2
    AND AVG(ca.Score) >= 5
    AND AVG(ca.ViewCount) >= 100
    
ORDER BY 
    ca.TotalScore DESC, 
    ca.ViewCount DESC,
    ca.RepRank ASC,
    ca.ViewRank ASC,
    ca.AvgScorePerUser DESC,
    ca.PostsPerUser DESC
LIMIT 1000 OFFSET 100;