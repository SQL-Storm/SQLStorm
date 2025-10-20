WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.LastActivityDate) AS LastPostActivity,
        STRING_AGG(b.Name, ', ') AS BadgeNames,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
      AND (u.LastAccessDate > DATE '2020-01-01' OR u.LastAccessDate IS NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.QuestionCount,
           us.AnswerCount,
           us.TotalPostScore,
           us.CommentCount,
           us.VoteCount,
           us.LastPostActivity,
           us.BadgeNames,
           us.AvgViewCount,
           ROW_NUMBER() OVER (ORDER BY us.TotalPostScore DESC) AS ScoreRank,
           PERCENT_RANK() OVER (ORDER BY (us.QuestionCount + us.AnswerCount)) AS ActivityPercentile,
           LAG(us.Reputation, 1, 0) OVER (ORDER BY us.Reputation DESC) - us.Reputation AS RepDiffFromPrev
    FROM UserStats us
),
ActivityDetails AS (
    SELECT ru.Id,
           ru.DisplayName,
           ru.ScoreRank,
           ru.ActivityPercentile,
           ru.RepDiffFromPrev,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ru.Id AND p.ClosedDate IS NOT NULL) AS ClosedPosts,
           CASE 
               WHEN ru.QuestionCount > 0 AND ru.AnswerCount > 0 THEN 'Both'
               WHEN ru.QuestionCount > 0 THEN 'Only Questions'
               WHEN ru.AnswerCount > 0 THEN 'Only Answers'
               ELSE 'None'
           END AS PostType,
           COALESCE(ru.BadgeNames, 'No Badges') AS Badges,
           ru.LastPostActivity,
           ROUND(CAST(ru.TotalPostScore AS NUMERIC) / NULLIF((ru.QuestionCount + ru.AnswerCount), 0), 2) AS AvgScorePerPost,
           CASE 
               WHEN ru.AvgViewCount > 1000 THEN 'Popular'
               WHEN ru.AvgViewCount BETWEEN 100 AND 1000 THEN 'Moderate'
               ELSE 'Low'
           END AS PopularityCategory
    FROM RankedUsers ru
    WHERE ru.TotalPostScore > 10
),
TopClosedQuestions AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.ViewCount,
           -- convert tags like '<tag1><tag2>' into array ['tag1','tag2']
           regexp_split_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), E'><') AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
    ORDER BY p.Score DESC
    LIMIT 50
),
UserActivitySummary AS (
    SELECT ad.Id,
           ad.DisplayName,
           ad.ScoreRank,
           ad.ClosedPosts,
           ad.PostType,
           ad.Badges,
           ad.PopularityCategory,
           ad.LastPostActivity,
           COALESCE(ad.AvgScorePerPost, 0) AS AvgScorePerPost,
           (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ad.Id AND c.Score > 5) AS HighScoreComments
    FROM ActivityDetails ad
)
SELECT uas.Id,
       uas.DisplayName,
       uas.ScoreRank,
       uas.ClosedPosts,
       uas.PostType,
       uas.Badges,
       uas.PopularityCategory,
       uas.LastPostActivity,
       uas.AvgScorePerPost,
       uas.HighScoreComments,
       tc.Title AS TopClosedTitle,
       tc.Score AS TopClosedScore,
       tc.ViewCount AS TopClosedViews,
       CASE WHEN tc.TagArray IS NOT NULL THEN array_length(tc.TagArray, 1) ELSE 0 END AS NumTags,
       CASE WHEN uas.ScoreRank <= 10 THEN 'Elite' ELSE 'Standard' END AS UserTier
FROM UserActivitySummary uas
LEFT JOIN TopClosedQuestions tc ON tc.Id = uas.Id
UNION ALL
SELECT NULL AS Id, NULL AS DisplayName, NULL AS ScoreRank, NULL AS ClosedPosts, NULL AS PostType, NULL AS Badges, NULL AS PopularityCategory, NULL AS LastPostActivity, NULL AS AvgScorePerPost, NULL AS HighScoreComments, NULL AS TopClosedTitle, NULL AS TopClosedScore, NULL AS TopClosedViews, NULL AS NumTags, NULL AS UserTier
WHERE 1=0
ORDER BY ScoreRank NULLS LAST, AvgScorePerPost DESC
LIMIT 100;