-- {"query": "7513.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2364}
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
        COALESCE(p.Body, '') AS Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeDesc,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'None'
        END AS ScoreCategory,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRankInType,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RecentPostNumber,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) AS PrevScore,
        LAG(p.ViewCount, 1) OVER (ORDER BY p.CreationDate) AS PrevViewCount,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByType,
        MAX(p.ViewCount) OVER (ORDER BY p.CreationDate) AS MaxViewCountSoFar,
        NTILE(4) OVER (ORDER BY p.Score) AS Quartile,
        CASE WHEN p.AnswerCount > 0 THEN (p.Score * 1.0 / p.AnswerCount) ELSE 0 END AS ScorePerAnswer,
        COALESCE(
            (SELECT c.text
             FROM Comments c
             WHERE c.PostId = p.Id
             ORDER BY c.CreationDate DESC
             LIMIT 1),
            'No comments'
        ) AS LatestComment,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v 
             WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)), 
            0
        ) AS VoteCount,
        CASE
            WHEN (SELECT COUNT(*) 
                  FROM PostLinks pl 
                  WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) > 0
            THEN 'HasDuplicates'
            ELSE 'NoDuplicates'
        END AS DuplicateStatus,
        REPLACE(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ', '') AS CleanedTags
    FROM Posts p
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 YEAR')
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        (SELECT COUNT(*) 
         FROM Badges b 
         WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
        (SELECT COUNT(*) 
         FROM Badges b 
         WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
        (SELECT COUNT(*) 
         FROM Badges b 
         WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount,
        (SELECT STRING_AGG(b.Name, ', ') 
         FROM Badges b 
         WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgesList
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 YEAR')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
)
SELECT 
    ps.Id AS PostId,
    ps.PostTypeDesc,
    ps.Title,
    ps.Score,
    ps.ViewCount,
    ps.ScoreCategory,
    ps.ScoreRankInType,
    ps.RecentPostNumber,
    ps.ScorePerAnswer,
    ps.AvgScoreByType,
    ps.Quartile,
    ps.LatestComment,
    ps.VoteCount,
    ps.DuplicateStatus,
    ps.CleanedTags,
    ps.CreationDate,
    ps.LastActivityDate,
    u.DisplayName,
    u.Reputation,
    u.PostCount,
    u.TotalScore,
    u.GoldBadgeCount,
    u.SilverBadgeCount,
    u.BronzeBadgeCount,
    u.GoldBadgesList,
    CASE 
        WHEN ps.Score > u.AvgPostScore THEN 'AboveAvg'
        WHEN ps.Score < u.AvgPostScore THEN 'BelowAvg'
        ELSE 'Avg'
    END AS ScoreVsUserAvg,
    CASE 
        WHEN ps.Score > ps.AvgScoreByType THEN 'AboveTypeAvg'
        WHEN ps.Score < ps.AvgScoreByType THEN 'BelowTypeAvg'
        ELSE 'TypeAvg'
    END AS ScoreVsTypeAvg,
    CAST(
        (ps.Score * 1.0 / 
         (CASE WHEN ps.AnswerCount > 0 THEN ps.AnswerCount ELSE 1 END)) 
        AS NUMERIC(10,2)
    ) AS ScorePerAnswerNorm,
    CASE
        WHEN ps.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 1) 
             AND ps.PostTypeId = 1
        THEN 'HighQuestionScore'
        ELSE 'NormalOrLow'
    END AS QuestionScoreStatus,
    CASE
        WHEN u.Reputation > 10000 AND ps.ScoreCategory = 'High' THEN 'ReputableHighScorer'
        WHEN u.Reputation > 10000 AND ps.ScoreCategory <> 'High' THEN 'Reputable'
        ELSE 'NonReputable'
    END AS UserReputationStatus,
    CASE 
        WHEN ps.Score > 50 AND ps.AnswerCount > 2 THEN 'ActiveQuestion'
        WHEN ps.PostTypeId = 2 AND ps.Score > 25 THEN 'ActiveAnswer'
        ELSE 'Inactive'
    END AS EngagementLevel,
    ABS(ps.Score - ps.PrevScore) AS ScoreChange,
    ABS(ps.ViewCount - ps.PrevViewCount) AS ViewChange,
    CASE 
        WHEN ps.Score >= 100 AND u.GoldBadgeCount >= 1 THEN 'Elite'
        WHEN ps.Score >= 50 THEN 'Experienced'
        WHEN ps.Score >= 10 THEN 'Beginner'
        ELSE 'Newbie'
    END AS UserLevel,
    CASE
        WHEN ps.Tags IS NOT NULL AND ps.Tags LIKE '%<%' AND ps.Tags LIKE '%>%' THEN
            (SELECT COUNT(*) FROM (
                SELECT regexp_split_to_table(REPLACE(REPLACE(REPLACE(ps.Tags, '<', ''), '>', ''), ' ', ''), '><') AS value
            ) t WHERE t.value <> '')
        ELSE 0
    END AS NumberOfTags,
    CASE
        WHEN ps.CreationDate > ps.LastActivityDate THEN EXTRACT(DAY FROM (ps.CreationDate - ps.LastActivityDate))
        ELSE EXTRACT(DAY FROM (ps.LastActivityDate - ps.CreationDate))
    END AS DayDiffFromActivity,
    CASE
        WHEN ps.ViewCount > 1000 AND ps.Score > 30 THEN 'Popular'
        ELSE 'Normal'
    END AS PopularityStatus,
    CASE
        WHEN ps.CreationDate BETWEEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '4 WEEK') AND CAST('2024-10-01 12:34:56' AS TIMESTAMP)
             AND ps.PostTypeId = 1
        THEN 'RecentQuestion'
        ELSE 'Other'
    END AS TemporalRelevance,
    CASE 
        WHEN ps.PostTypeDesc = 'Answer' AND ps.Score = (
            SELECT MAX(p2.Score) 
            FROM Posts p2 
            WHERE p2.ParentId = ps.Id
        ) THEN 'TopAnswer'
        ELSE 'RegularAnswer'
    END AS AnswerType,
    CASE 
        WHEN ps.Tags LIKE '%sql%' OR ps.Tags LIKE '%database%' THEN 'DatabaseRelated'
        WHEN ps.Tags LIKE '%python%' OR ps.Tags LIKE '%programming%' THEN 'ProgrammingRelated'
        ELSE 'OtherRelated'
    END AS SubjectArea,
    CASE WHEN ps.PostTypeId = 1 AND ps.AnswerCount >= 3 AND ps.CommentCount >= 2 THEN 1 ELSE 0 END AS ComplexQuestion,
    CASE WHEN ps.Score > 100 OR (ps.PostTypeId = 2 AND ps.Score > 50) THEN 1 ELSE 0 END AS ValuableContribution,
    ps.MaxViewCountSoFar,
    CASE
        WHEN ps.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 DAY') AND ps.Score > 10 THEN 'HotTopic'
        ELSE 'Regular'
    END AS TemporalStatus,
    CASE 
        WHEN ps.Score < 0 THEN 'Negative'
        WHEN ps.Score BETWEEN 0 AND 10 THEN 'ZeroToTen'
        WHEN ps.Score BETWEEN 11 AND 100 THEN 'TenToHundred'
        ELSE 'AboveHundred'
    END AS ScoreRange,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - ps.CreationDate)) AS DaysSinceCreation,
    CASE WHEN ps.ViewCount > ps.AvgScoreByType * 2 AND ps.Score > 10 THEN 1 ELSE 0 END AS HighViewScoreRatio,
    CASE
        WHEN COALESCE(ps.Title, '') = '' OR ps.Title LIKE '%question%question%' OR ps.Title LIKE '%Question%' THEN 'PotentialSpam'
        ELSE 'ValidTitle'
    END AS TitleQuality,
    ps.NextScore,
    ps.PrevScore,
    CASE 
        WHEN ps.PostTypeId = 1 AND ps.AnswerCount IS NOT NULL THEN (
            CAST(ps.AnswerCount AS NUMERIC(10,2)) / NULLIF((SELECT COUNT(*) FROM Posts p WHERE p.ParentId = ps.Id), 0)
        ) 
        ELSE NULL 
    END AS AnswerRatio,
    CASE
        WHEN ps.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 DAY') THEN 'RecentActivity'
        ELSE 'OldActivity'
    END AS ActivityStatus
FROM PostStats ps
LEFT JOIN UserActivity u ON ps.OwnerUserId = u.UserId
WHERE ps.Score IS NOT NULL 
  AND ps.ViewCount IS NOT NULL
  AND (ps.PostTypeId IN (1, 2) OR ps.PostTypeDesc = 'Answer')
  AND ps.Score BETWEEN -100 AND 1000
  AND ps.RecentPostNumber BETWEEN 1 AND 10000
  AND ps.ScorePerAnswer BETWEEN -100 AND 1000
  AND ps.ScoreRankInType BETWEEN 1 AND 100
ORDER BY ps.Score DESC, ps.CreationDate DESC
OFFSET 100 ROWS FETCH NEXT 500 ROWS ONLY;