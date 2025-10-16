WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreCount,
        SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) AS NegativeScoreCount,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)) AS RecentPostsLast30Days
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT p.OwnerUserId) AS UserCount,
        RANK() OVER (ORDER BY t.Count DESC) AS TagRank,
        STRING_AGG(DISTINCT u.DisplayName, ', ') AS TagUsers
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    INNER JOIN Users u ON u.Id = p.OwnerUserId
    WHERE t.Count > 10 
    GROUP BY t.TagName, t.Count
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        (EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400) AS DaysActive,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                CAST(p.AnswerCount AS DOUBLE PRECISION) / NULLIF((p.AnswerCount + p.CommentCount), 0)
            ELSE NULL 
        END AS AnswerToCommentRatio,
        CASE 
            WHEN p.OwnerUserId IS NOT NULL AND p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0 
        END AS HasAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS TopQuestionByUser,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        PERCENT_RANK() OVER (ORDER BY p.Score) AS ScorePercentile
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        CASE 
            WHEN a.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'AboveAverage'
            WHEN a.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'BelowAverage'
            ELSE 'Average' 
        END AS ScoreCategory
    FROM Posts a
    WHERE a.PostTypeId = 2
),
UserPostStats AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.Questions,
        ua.Answers,
        ua.Comments,
        ua.Badges,
        ua.LastPostDate,
        ua.ReputationRank,
        ua.AvgPostScore,
        ua.PositiveScoreCount,
        ua.NegativeScoreCount,
        ua.RecentPostsLast30Days,
        CASE 
            WHEN ua.RecentPostsLast30Days > 50 THEN 'HighlyActive'
            WHEN ua.RecentPostsLast30Days > 20 THEN 'ModeratelyActive'
            WHEN ua.RecentPostsLast30Days > 5 THEN 'OccasionallyActive'
            ELSE 'Inactive' 
        END AS ActivityLevel,
        CASE 
            WHEN ua.Answers > 0 AND ua.Questions > 0 THEN 
                CAST(ua.Answers AS DOUBLE PRECISION) / NULLIF(ua.Questions, 0)
            ELSE NULL 
        END AS AnswerToQuestionRatio,
        (SELECT AVG(sub.AvgPostScore) FROM (
            SELECT AvgPostScore, ROW_NUMBER() OVER (ORDER BY AvgPostScore) AS rn, COUNT(*) OVER () AS cnt
            FROM UserActivityStats
        ) sub WHERE sub.rn IN (CAST(FLOOR((sub.cnt+1)/2.0) AS INTEGER), CAST(CEIL((sub.cnt+1)/2.0) AS INTEGER))) AS MedianAvgScore,
        ROW_NUMBER() OVER (ORDER BY ua.AvgPostScore DESC) AS AvgScoreRank
    FROM UserActivityStats ua
    WHERE ua.TotalPosts > 0
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.TotalPosts, ua.Questions, ua.Answers, ua.Comments, ua.Badges, ua.LastPostDate, ua.ReputationRank, ua.AvgPostScore, ua.PositiveScoreCount, ua.NegativeScoreCount, ua.RecentPostsLast30Days, ua.Reputation
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ups.Comments,
    ups.Badges,
    ups.LastPostDate,
    ups.ReputationRank,
    ups.AvgPostScore,
    ups.PositiveScoreCount,
    ups.NegativeScoreCount,
    ups.RecentPostsLast30Days,
    ups.ActivityLevel,
    ups.AnswerToQuestionRatio,
    ups.AvgScoreRank,
    ts.TagName,
    ts.TagCount,
    ts.AvgScore AS TagAvgScore,
    ts.UserCount,
    ts.TagRank,
    ts.TagUsers,
    qs.QuestionId,
    qs.Title,
    qs.Score AS QuestionScore,
    qs.ViewCount,
    qs.AnswerCount,
    qs.CommentCount,
    qs.DaysActive,
    qs.AnswerToCommentRatio,
    qs.HasAcceptedAnswer,
    qs.TopQuestionByUser,
    qs.PreviousScore,
    qs.ScorePercentile,
    asa.AnswerId,
    asa.ParentId,
    asa.Score AS AnswerScore,
    asa.ScoreCategory,
    CASE 
        WHEN ups.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'AboveAverageReputation'
        ELSE 'BelowAverageReputation'
    END AS ReputationLevel,
    CASE 
        WHEN ups.Answers > (SELECT AVG(Answers) FROM UserPostStats) THEN 'AboveAverageAnswerer'
        ELSE 'BelowAverageAnswerer'
    END AS AnsweringLevel,
    CASE 
        WHEN ups.PositiveScoreCount > ups.NegativeScoreCount THEN 'PositiveContributor'
        WHEN ups.NegativeScoreCount > ups.PositiveScoreCount THEN 'NegativeContributor'
        ELSE 'NeutralContributor'
    END AS ContributionType,
    COALESCE(ts.TagName, 'No Tags') AS TagFocus,
    CASE 
        WHEN qs.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'HighValueQuestion'
        WHEN qs.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'LowValueQuestion'
        ELSE 'AverageValueQuestion'
    END AS QuestionValueCategory,
    (ups.PositiveScoreCount + ups.NegativeScoreCount) AS TotalScoreContributions,
    DENSE_RANK() OVER (ORDER BY (ups.PositiveScoreCount + ups.NegativeScoreCount) DESC) AS ContributionRank,
    COALESCE(ups.Reputation, 0) + COALESCE(ups.Badges, 0) + COALESCE(ups.Answers, 0) AS CompositeScore
FROM UserPostStats ups
FULL OUTER JOIN TopTags ts ON ts.TagRank <= 10
FULL OUTER JOIN QuestionStats qs ON qs.OwnerUserId = ups.UserId
FULL OUTER JOIN AnswerStats asa ON asa.ParentId = qs.QuestionId
WHERE ups.Reputation > 200
  AND (
    (ups.RecentPostsLast30Days > 5 OR ups.Answers > 0 OR ups.Questions > 0) 
    OR ts.TagName IS NOT NULL
  )
  AND (
    (ups.Answers > 0 AND ups.Questions > 0) 
    OR qs.QuestionId IS NOT NULL
    OR asa.AnswerId IS NOT NULL
  )
  AND (ups.ActivityLevel IN ('HighlyActive', 'ModeratelyActive') OR ts.TagName IS NOT NULL)
GROUP BY
    ups.UserId, ups.DisplayName, ups.Reputation, ups.TotalPosts, ups.Questions, ups.Answers, ups.Comments, ups.Badges, ups.LastPostDate, ups.ReputationRank, ups.AvgPostScore, ups.PositiveScoreCount, ups.NegativeScoreCount, ups.RecentPostsLast30Days, ups.ActivityLevel, ups.AnswerToQuestionRatio, ups.AvgScoreRank,
    ts.TagName, ts.TagCount, ts.AvgScore, ts.UserCount, ts.TagRank, ts.TagUsers,
    qs.QuestionId, qs.Title, qs.Score, qs.ViewCount, qs.AnswerCount, qs.CommentCount, qs.DaysActive, qs.AnswerToCommentRatio, qs.HasAcceptedAnswer, qs.TopQuestionByUser, qs.PreviousScore, qs.ScorePercentile,
    asa.AnswerId, asa.ParentId, asa.Score, asa.ScoreCategory
ORDER BY ups.Reputation DESC, ups.TotalPosts DESC, qs.Score DESC, ups.AvgPostScore DESC
OFFSET 0 ROWS FETCH NEXT 500 ROWS ONLY;