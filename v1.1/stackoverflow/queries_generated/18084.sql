-- {"query": "18084.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1425} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        p.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_score,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore,
        AVG(CAST(p.Score AS FLOAT)) OVER(PARTITION BY p.PostTypeId) AS AvgScoreForType,
        SUM(p.AnswerCount) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAnswers
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score > -5
),
UserPostEngagement AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.FavoriteCount) AS MaxFavorite,
        AVG(CAST(p.ViewCount AS FLOAT)) AS AvgViews
    FROM RankedPosts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TopUsers AS (
    SELECT
        upe.OwnerUserId,
        upe.QuestionCount,
        upe.AnswerCount,
        upe.TotalScore,
        upe.MaxFavorite,
        upe.AvgViews,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName AS UserName,
        CASE
            WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
            WHEN u.Location IS NOT NULL AND u.Location <> '' THEN 'Has Location'
            ELSE 'No Specific Info'
        END AS UserProfileStatus,
        ROW_NUMBER() OVER(ORDER BY u.Reputation DESC, upe.TotalScore DESC) AS UserRank
    FROM UserPostEngagement upe
    JOIN Users u ON upe.OwnerUserId = u.Id
    WHERE upe.QuestionCount > 5 OR upe.AnswerCount > 10
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN ph.Comment ELSE NULL END) AS LastCloseReason,
        AVG(CASE WHEN ph.PostHistoryTypeId = 2 THEN DATEDIFF(minute, LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate), ph.CreationDate) ELSE NULL END) AS AvgBodyEditIntervalMinutes
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 10, 101, 102, 103, 104, 105)
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    pt.Name AS PostTypeName,
    COALESCE(tu.UserName, rp.OwnerUserId::VARCHAR) AS DisplayUser,
    rp.Score,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.ViewCount,
    rp.CreationDate,
    rp.rn_score AS RankWithinType,
    (rp.Score - rp.PreviousScore) AS ScoreIncreaseSincePrevious,
    (rp.Score - rp.NextScore) AS ScoreDecreaseSinceNext,
    rp.AvgScoreForType,
    rp.CumulativeAnswers,
    tu.Reputation AS UserReputation,
    tu.UserRank,
    tu.UserProfileStatus,
    pha.BodyEdits,
    pha.TitleEdits,
    pha.LastCloseReason,
    pha.AvgBodyEditIntervalMinutes,
    CASE
        WHEN rp.Score > 500 AND rp.AnswerCount > 10 AND rp.FavoriteCount > 20 THEN 'Highly Engaged Question'
        WHEN rp.Score < -5 AND rp.PostTypeId = 2 THEN 'Low Rated Answer'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    CASE
        WHEN pha.AvgBodyEditIntervalMinutes IS NULL THEN 'No Body Edits'
        WHEN pha.AvgBodyEditIntervalMinutes > 60 THEN 'Infrequent Edits'
        ELSE 'Frequent Edits'
    END AS EditFrequency,
    CONCAT('User_Score:', tu.TotalScore, '_Rep:', tu.Reputation) AS UserEngagementSummary,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.ViewCount > 10000 THEN 'High Traffic'
        ELSE 'Normal Traffic'
    END AS PostStatus,
    CASE
        WHEN rp.OwnerUserId IS NULL THEN TRUE
        ELSE FALSE
    END AS IsCommunityOwned,
    (rp.Score * 1.0 / NULLIF(rp.ViewCount, 0)) AS ScorePerView,
    (rp.AnswerCount * 1.0 / NULLIF(rp.CommentCount, 0)) AS AnswersPerComment
FROM RankedPosts rp
JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN TopUsers tu ON rp.OwnerUserId = tu.OwnerUserId
LEFT JOIN PostHistoryAnalysis pha ON rp.PostId = pha.PostId
WHERE rp.rn_score <= 1000
ORDER BY rp.PostTypeId, rp.rn_score;
