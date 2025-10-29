-- {"query": "4172.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1423} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score_views,
        SUM(p.Score) OVER (PARTITION BY p.PostTypeId) AS total_score_for_type,
        AVG(CAST(p.ViewCount AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS avg_viewcount_for_type,
        COUNT(p.Id) OVER (PARTITION BY p.PostTypeId) AS count_for_type,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS next_post_score
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= '2023-01-01' AND p.Score IS NOT NULL
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        AvgPostScore,
        LastPostDate,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC) AS user_rank
    FROM UserPostStats
    WHERE TotalPosts > 100
),
RecentActivity AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastActivityTimestamp
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (2, 5) -- Edits to Body
    GROUP BY ph.PostId
),
PostDetails AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.total_score_for_type,
        rp.avg_viewcount_for_type,
        rp.count_for_type,
        CASE WHEN rp.Score > rp.avg_viewcount_for_type THEN 'High Score Relative to Views' ELSE 'Standard Score' END AS score_vs_views,
        CASE WHEN ra.LastActivityTimestamp IS NOT NULL THEN
            CASE WHEN ra.LastActivityTimestamp > rp.CreationDate + INTERVAL '7 days' THEN 'Edited After First Week' ELSE 'Edited Within First Week' END
        ELSE 'No Edits Recorded' END AS edit_lag,
        rp.next_post_score
    FROM RankedPosts rp
    LEFT JOIN RecentActivity ra ON rp.PostId = ra.PostId
    WHERE rp.rn_score_views <= 1000
)
SELECT
    pd.PostId,
    pd.PostTypeName,
    pd.Score,
    pd.ViewCount,
    pd.AnswerCount,
    pd.CommentCount,
    pd.FavoriteCount,
    pd.score_vs_views,
    pd.edit_lag,
    pd.next_post_score,
    tu.DisplayName AS TopUserDisplayName,
    tu.Reputation AS TopUserReputation,
    tu.TotalPosts AS TopUserTotalPosts,
    CASE WHEN pd.Score IS NULL THEN 'Score is NULL' ELSE 'Score is NOT NULL' END AS null_score_check,
    COALESCE(LOWER(SUBSTRING(p.Title FROM 1 FOR 50)), 'No Title Provided') AS TitleSnippet,
    p.Tags,
    (pd.Score * 1.0 / NULLIF(pd.total_score_for_type, 0)) * 100 AS PercentageOfTotalScore,
    (pd.ViewCount * 1.0 / NULLIF(pd.avg_viewcount_for_type, 0)) * 100 AS PercentageOfAverageViews
FROM PostDetails pd
JOIN Posts p ON pd.PostId = p.Id
LEFT JOIN TopUsers tu ON p.OwnerUserId = tu.UserId AND tu.user_rank <= 50 -- Joining with top 50 users
WHERE pd.Score > 10 OR pd.ViewCount > 1000
UNION ALL
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    'N/A' AS score_vs_views,
    'N/A' AS edit_lag,
    rp.next_post_score,
    NULL AS TopUserDisplayName,
    NULL AS TopUserReputation,
    NULL AS TopUserTotalPosts,
    CASE WHEN rp.Score IS NULL THEN 'Score is NULL' ELSE 'Score is NOT NULL' END AS null_score_check,
    COALESCE(LOWER(SUBSTRING(p.Title FROM 1 FOR 50)), 'No Title Provided') AS TitleSnippet,
    p.Tags,
    NULL AS PercentageOfTotalScore,
    NULL AS PercentageOfAverageViews
FROM RankedPosts rp
JOIN Posts p ON rp.PostId = p.Id
WHERE rp.rn_score_views > 1000 AND rp.PostTypeId IN (3, 5) -- Include some less popular post types
ORDER BY PostId;