-- {"query": "4469.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1089}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextScore,
        SUM(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScoreSum
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score > 10
),
PostWithAggregatedComments AS (
    SELECT
        pc.Id AS PostId,
        COUNT(c.Id) AS CommentCountOnPost,
        AVG(CAST(c.Score AS DECIMAL(10, 2))) AS AvgCommentScore,
        -- STRING_AGG with ORDER BY is not supported in all dialects; use a generic aggregate when supported.
        -- For compatibility, build a concatenation without guaranteed order if necessary.
        STRING_AGG(SUBSTRING(c.Text FROM 1 FOR 50), ' | ') AS SampleCommentTexts
    FROM Posts pc
    LEFT JOIN Comments c ON pc.Id = c.PostId
    GROUP BY pc.Id
),
UserActivity AS (
    SELECT
        pu.Id AS UserId,
        pu.DisplayName,
        COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
        MAX(ph.CreationDate) AS LastPostActivityDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditCount
    FROM Users pu
    LEFT JOIN PostHistory ph ON pu.Id = ph.UserId
    GROUP BY pu.Id, pu.DisplayName
),
TopUsers AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.PostHistoryCount,
        ua.EditCount,
        ROW_NUMBER() OVER (ORDER BY ua.EditCount DESC, ua.PostHistoryCount DESC) AS UserRank
    FROM UserActivity ua
    WHERE ua.PostHistoryCount > 50
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.rn_desc,
    rp.PreviousScore,
    rp.NextScore,
    rp.RunningScoreSum,
    pac.CommentCountOnPost,
    pac.AvgCommentScore,
    pac.SampleCommentTexts,
    CASE
        WHEN rp.Score > 1000 AND rp.FavoriteCount > 100 THEN 'Highly Engaging'
        WHEN rp.Score > 100 AND rp.AnswerCount > 10 THEN 'Popular Question'
        WHEN rp.Score < 0 THEN 'Negatively Scored'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CreationDate < (cast('2024-10-01' as date) - INTERVAL '365' DAY) AND rp.Score < 5 THEN 'Old and Unpopular'
        ELSE 'Active'
    END AS PostStatus,
    latest_editors.DisplayName AS LatestEditorDisplayName,
    tu.DisplayName AS TopEditorDisplayName,
    tu.UserRank
FROM RankedPosts rp
LEFT JOIN PostWithAggregatedComments pac ON rp.PostId = pac.PostId
LEFT JOIN (
    SELECT
        ph_inner.PostId,
        u_inner.Id AS UserId,
        u_inner.DisplayName,
        ROW_NUMBER() OVER (PARTITION BY ph_inner.PostId ORDER BY ph_inner.CreationDate DESC) AS latest_edit_rn
    FROM PostHistory ph_inner
    JOIN Users u_inner ON ph_inner.UserId = u_inner.Id
    WHERE ph_inner.PostHistoryTypeId IN (4, 5, 6)
) AS latest_editors ON rp.PostId = latest_editors.PostId AND latest_editors.latest_edit_rn = 1
LEFT JOIN TopUsers tu ON latest_editors.UserId = tu.UserId
WHERE rp.rn_desc <= 100
ORDER BY rp.Score DESC, rp.CreationDate DESC;