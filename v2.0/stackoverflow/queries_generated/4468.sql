-- {"query": "4468.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1614} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate ASC) AS rn_asc,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextPostScore,
        SUM(p.AnswerCount) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAnswerCount,
        (p.Score - LAG(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate)) AS ScoreDifference
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate > '2023-01-01'
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(p.ViewCount) AS TotalPostViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
RecentComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountInLastDay,
        SUM(c.Score) AS TotalCommentScoreInLastDay,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate >= datetime('now', '-1 day')
    GROUP BY c.PostId
),
PostDetails AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.PostCreationDate,
        rp.PostScore,
        rp.PostViewCount,
        rp.rn_desc,
        rp.rn_asc,
        rp.PreviousPostScore,
        rp.NextPostScore,
        rp.CumulativeAnswerCount,
        rp.ScoreDifference,
        COALESCE(ups.QuestionCount, 0) AS OwnerQuestionCount,
        COALESCE(ups.AnswerCount, 0) AS OwnerAnswerCount,
        COALESCE(ups.AvgQuestionScore, 0.0) AS OwnerAvgQuestionScore,
        COALESCE(ups.TotalPostViews, 0) AS OwnerTotalPostViews,
        COALESCE(rc.CommentCountInLastDay, 0) AS RecentCommentCount,
        COALESCE(rc.TotalCommentScoreInLastDay, 0) AS RecentCommentScore
    FROM RankedPosts rp
    LEFT JOIN UserPostStats ups ON rp.OwnerUserId = ups.UserId
    LEFT JOIN RecentComments rc ON rp.PostId = rc.PostId
    WHERE rp.rn_desc <= 100 OR rp.rn_asc <= 100
)
SELECT
    pd.PostId,
    pd.PostTypeName,
    pd.PostCreationDate,
    pd.PostScore,
    pd.PostViewCount,
    pd.OwnerQuestionCount,
    pd.OwnerAnswerCount,
    pd.OwnerAvgQuestionScore,
    pd.OwnerTotalPostViews,
    pd.RecentCommentCount,
    pd.RecentCommentScore,
    CASE
        WHEN pd.PostScore > 100 AND pd.PostViewCount > 10000 THEN 'High Impact'
        WHEN pd.PostScore < 0 AND pd.PostViewCount < 100 THEN 'Low Engagement'
        ELSE 'Standard'
    END AS PostImpactCategory,
    CAST(strftime('%Y-%m', pd.PostCreationDate) AS TEXT) AS PostMonth,
    CASE
        WHEN pd.PreviousPostScore < pd.PostScore AND pd.NextPostScore < pd.PostScore THEN 'Peak Score'
        WHEN pd.PreviousPostScore > pd.PostScore AND pd.NextPostScore > pd.PostScore THEN 'Trough Score'
        ELSE 'Stable Trend'
    END AS ScoreTrend,
    REPLACE(pd.PostTypeName, ' ', '_') || '_' || CAST(pd.PostId AS TEXT) AS CompositeKey,
    (pd.PostScore * pd.PostViewCount) / NULLIF(pd.OwnerAnswerCount + pd.OwnerQuestionCount, 0) AS EngagementRatio,
    CASE
        WHEN pd.rn_desc = 1 THEN 'Most Recent'
        WHEN pd.rn_asc = 1 THEN 'Oldest'
        ELSE 'Mid-Range'
    END AS RecencyRank,
    pd.ScoreDifference AS ScoreChangeFromPrevious,
    pd.CumulativeAnswerCount,
    CASE
        WHEN UPPER(SUBSTR(pd.PostTypeName, 1, 1)) BETWEEN 'A' AND 'Z' THEN 'Starts with Letter'
        ELSE 'Does Not Start with Letter'
    END AS PostTypeInitialLetterCheck,
    (pd.PostScore + pd.PostViewCount + pd.OwnerQuestionCount + pd.OwnerAnswerCount + pd.RecentCommentCount) AS TotalScoreMetric,
    CASE
        WHEN pd.PostCreationDate IS NULL THEN 'Unknown'
        WHEN pd.PostCreationDate < '2023-01-01' THEN 'Pre-2023'
        ELSE '2023 or Later'
    END AS CreationPeriod,
    UPPER(LEFT(pd.PostTypeName, 3)) AS PostTypeAbbreviation
FROM PostDetails pd
WHERE pd.PostScore > COALESCE(pd.PreviousPostScore, 0) OR pd.PostScore > COALESCE(pd.NextPostScore, 0)
UNION ALL
SELECT
    NULL,
    'Summary',
    NULL,
    AVG(PostScore),
    SUM(PostViewCount),
    AVG(OwnerQuestionCount),
    AVG(OwnerAnswerCount),
    AVG(OwnerAvgQuestionScore),
    SUM(OwnerTotalPostViews),
    AVG(RecentCommentCount),
    AVG(RecentCommentScore),
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM PostDetails
WHERE PostTypeName = 'Question';
