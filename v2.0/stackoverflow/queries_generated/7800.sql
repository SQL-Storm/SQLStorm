-- {"query": "7800.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2563} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(SUM(p.Score) AS FLOAT) / NULLIF(COUNT(DISTINCT p.Id), 0)
            ELSE 0 
        END as AvgScorePerPost,
        STUFF((
            SELECT DISTINCT ',' + t.TagName
            FROM Posts p2
            JOIN STRING_TO_ARRAY(p2.Tags, '>') AS tag_array ON tag_array <> ''
            JOIN Tags t ON t.TagName = TRIM(tag_array, '<')
            WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, '') as UserTags,
        IIF(MAX(p.CreationDate) > DATEADD(YEAR, -1, GETDATE()), 'Active', 'Inactive') as ActivityStatus
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopPostsByScore AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.CreationDate,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreDensityRank,
        NTILE(4) OVER (ORDER BY p.Score DESC) as Quartile,
        LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) as PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScoreByUser,
        MAX(p.Score) OVER (PARTITION BY p.OwnerUserId) as MaxScoreByUser,
        MIN(p.Score) OVER (PARTITION BY p.OwnerUserId) as MinScoreByUser,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) as TotalScoreByUser,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as PostCountByUser,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'BelowAverage'
            ELSE 'Average'
        END as ScoreCategory,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                CAST(p.Score AS FLOAT) / NULLIF(p.AnswerCount, 0)
            ELSE NULL 
        END as ScorePerAnswer,
        CASE 
            WHEN p.ViewCount > 0 THEN 
                CAST(p.Score AS FLOAT) / NULLIF(p.ViewCount, 0)
            ELSE NULL 
        END as ScorePerView,
        CONCAT('Q', p.Id, ': ', LEFT(p.Title, 50), '...') as PostSummary
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- Questions only
    AND p.CreationDate >= DATEADD(YEAR, -2, GETDATE()) -- Last 2 years
),
UserPostPerformance AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.AvgScorePerPost,
        COALESCE(tps.Score, 0) as HighestScorePost,
        COALESCE(tps.Title, 'No Posts') as HighestScoringPostTitle,
        COALESCE(tps.ScorePerAnswer, 0) as ScorePerAnswer,
        COALESCE(tps.ScorePerView, 0) as ScorePerView,
        CASE 
            WHEN uas.PostCount > 0 THEN 
                CAST(uas.TotalScore AS FLOAT) / NULLIF(uas.PostCount, 0)
            ELSE 0 
        END as OverallAvgScorePerPost,
        CASE 
            WHEN uas.BadgeCount > 0 THEN 
                COALESCE(tps.Score, 0) / NULLIF(uas.BadgeCount, 0)
            ELSE 0 
        END as ScorePerBadge,
        IIF(uas.Reputation > 10000, 'Expert', 'Regular') as UserLevel,
        COALESCE(tps.PostSummary, 'No relevant posts') as HighestScorePostSummary
    FROM UserActivityStats uas
    LEFT JOIN TopPostsByScore tps ON uas.UserId = tps.OwnerUserId AND tps.ScoreRank = 1
    WHERE uas.ActivityStatus = 'Active' -- Only active users
),
CombinedStats AS (
    SELECT 
        upp.UserId,
        upp.DisplayName,
        upp.Reputation,
        upp.PostCount,
        upp.CommentCount,
        upp.BadgeCount,
        upp.AvgScorePerPost,
        upp.HighestScorePost,
        upp.HighestScoringPostTitle,
        upp.ScorePerAnswer,
        upp.ScorePerView,
        upp.OverallAvgScorePerPost,
        upp.ScorePerBadge,
        upp.UserLevel,
        upp.HighestScorePostSummary,
        CASE 
            WHEN upp.Reputation >= 100000 THEN 'Veteran'
            WHEN upp.Reputation >= 10000 THEN 'Experienced'
            WHEN upp.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        CASE 
            WHEN upp.PostCount > 100 THEN 'HighlyActive'
            WHEN upp.PostCount > 50 THEN 'Active'
            WHEN upp.PostCount > 10 THEN 'Moderate'
            ELSE 'Low'
        END as ActivityLevel,
        CASE 
            WHEN upp.BadgeCount > 50 THEN 'BadgeCollector'
            WHEN upp.BadgeCount > 25 THEN 'RegularBadgeUser'
            WHEN upp.BadgeCount > 5 THEN 'OccasionalBadgeUser'
            ELSE 'NewBadgeUser'
        END as BadgeEngagement,
        ROW_NUMBER() OVER (ORDER BY upp.Reputation DESC, upp.PostCount DESC) as GlobalRank,
        DENSE_RANK() OVER (ORDER BY upp.Reputation DESC) as ReputationRank,
        NTILE(10) OVER (ORDER BY upp.Reputation DESC) as ReputationPercentile,
        PERCENT_RANK() OVER (ORDER BY upp.Reputation DESC) as ReputationPercentRank
    FROM UserPostPerformance upp
)
SELECT 
    cs.UserId as "User ID",
    cs.DisplayName as "Display Name",
    cs.Reputation as "Reputation Points",
    cs.PostCount as "Number of Posts",
    cs.CommentCount as "Number of Comments",
    cs.BadgeCount as "Number of Badges",
    ROUND(cs.AvgScorePerPost, 2) as "Average Score per Post",
    cs.HighestScorePost as "Highest Scoring Post",
    cs.HighestScoringPostTitle as "Highest Scoring Post Title",
    ROUND(cs.ScorePerAnswer, 2) as "Score per Answer",
    ROUND(cs.ScorePerView, 4) as "Score per View",
    ROUND(cs.OverallAvgScorePerPost, 2) as "Overall Average Score",
    ROUND(cs.ScorePerBadge, 2) as "Score per Badge",
    cs.UserLevel as "User Level",
    cs.HighestScorePostSummary as "Post Summary",
    cs.ReputationLevel as "Reputation Level",
    cs.ActivityLevel as "Activity Level",
    cs.BadgeEngagement as "Badge Engagement",
    cs.GlobalRank as "Global Rank",
    cs.ReputationRank as "Reputation Rank",
    cs.ReputationPercentile as "Reputation Percentile",
    ROUND(cs.ReputationPercentRank, 4) as "Reputation Percent Rank",
    CASE 
        WHEN cs.Reputation > 100000 AND cs.PostCount > 50 THEN 'Top Performer'
        WHEN cs.Reputation > 50000 AND cs.PostCount > 25 THEN 'High Performer'
        WHEN cs.Reputation > 10000 AND cs.PostCount > 10 THEN 'Good Performer'
        ELSE 'Standard Contributor'
    END as "Performance Category",
    CONCAT('Rank #', cs.GlobalRank, ' - ', cs.DisplayName, ' - Rep:', cs.Reputation) as "Ranking Summary",
    IIF(cs.GlobalRank <= 100, 'Top 100', 'Below Top 100') as "TopRankingStatus",
    IIF(cs.Reputation > (SELECT AVG(Reputation) FROM Users), 'AboveAverage', 'BelowAverage') as "RepVsAverage",
    COALESCE(cs.ReputationLevel, 'Unknown') as "RepLevelDetected"
FROM CombinedStats cs
WHERE cs.Reputation > 100
AND cs.PostCount > 0
AND cs.HighestScorePost > 50
ORDER BY cs.Reputation DESC, cs.PostCount DESC
OFFSET 100 ROWS
FETCH NEXT 50 ROWS ONLY
UNION ALL
SELECT 
    -1 as "User ID",
    'Aggregated Summary' as "Display Name",
    SUM(Reputation) as "Reputation Points",
    SUM(PostCount) as "Number of Posts",
    SUM(CommentCount) as "Number of Comments",
    SUM(BadgeCount) as "Number of Badges",
    AVG(AvgScorePerPost) as "Average Score per Post",
    MAX(HighestScorePost) as "Highest Scoring Post",
    NULL as "Highest Scoring Post Title",
    AVG(ScorePerAnswer) as "Score per Answer",
    AVG(ScorePerView) as "Score per View",
    AVG(OverallAvgScorePerPost) as "Overall Average Score",
    AVG(ScorePerBadge) as "Score per Badge",
    'Summary' as "User Level",
    'Total Statistics' as "Post Summary",
    'Summary' as "Reputation Level",
    'Summary' as "Activity Level",
    'Summary' as "Badge Engagement",
    0 as "Global Rank",
    0 as "Reputation Rank",
    100 as "Reputation Percentile",
    1.0 as "Reputation Percent Rank",
    'Aggregated' as "Performance Category",
    'Aggregated Data' as "Ranking Summary",
    'N/A' as "TopRankingStatus",
    'N/A' as "RepVsAverage",
    'N/A' as "RepLevelDetected"
FROM (
    SELECT 
        cs.UserId,
        cs.DisplayName,
        cs.Reputation,
        cs.PostCount,
        cs.CommentCount,
        cs.BadgeCount,
        cs.AvgScorePerPost,
        cs.HighestScorePost,
        cs.HighestScoringPostTitle,
        cs.ScorePerAnswer,
        cs.ScorePerView,
        cs.OverallAvgScorePerPost,
        cs.ScorePerBadge,
        cs.UserLevel,
        cs.HighestScorePostSummary,
        cs.ReputationLevel,
        cs.ActivityLevel,
        cs.BadgeEngagement,
        cs.GlobalRank,
        cs.ReputationRank,
        cs.ReputationPercentile,
        cs.ReputationPercentRank
    FROM CombinedStats cs
    WHERE cs.Reputation > 10000
) AS FilteredData
HAVING COUNT(*) > 25