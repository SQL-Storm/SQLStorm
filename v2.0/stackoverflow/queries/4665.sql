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
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_by_score,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS previous_day_score,
        SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id ORDER BY p.Id) AS comment_count_for_post,
        CASE
            WHEN p.OwnerUserId IS NOT NULL THEN (SELECT Reputation FROM Users WHERE Id = p.OwnerUserId)
            ELSE -1
        END AS OwnerReputation,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS view_rank_overall,
        COALESCE(p.AnswerCount, 0) AS non_null_answer_count,
        p.Tags
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
),
PostHistorySummary AS (
    SELECT
        PostId,
        COUNT(CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS edit_count,
        MAX(CreationDate) AS last_edit_date
    FROM PostHistory
    WHERE CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
    GROUP BY PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.non_null_answer_count,
    rp.comment_count_for_post,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.view_rank_overall,
    phs.edit_count,
    CASE
        WHEN rp.ClosedDate IS NOT NULL AND rp.Score < 0 THEN 'Negatively Scored Closed Post'
        WHEN rp.OwnerReputation > 10000 AND rp.rn_by_score <= 10 THEN 'High Rep High Score Post'
        WHEN rp.comment_count_for_post > 5 AND COALESCE(phs.edit_count, 0) > 0 THEN 'Active and Edited Post'
        WHEN rp.previous_day_score = 0 AND rp.Score > 0 THEN 'First Day Score Gain'
        WHEN rp.Tags LIKE '%<sql>%' THEN 'SQL Tagged Post'
        WHEN rp.PostTypeId = 1 AND rp.AnswerCount > 0 AND rp.ViewCount > (SELECT AVG(p2.ViewCount) FROM Posts p2 WHERE p2.PostTypeId = 1) * 2 THEN 'Popular Question with Answers'
        ELSE 'Standard Post'
    END AS post_category,
    (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = rp.PostId AND c2.UserId = rp.OwnerUserId) AS comments_by_owner,
    COALESCE(rp.FavoriteCount, 0) AS NonNullFavoriteCount,
    UPPER(SUBSTR(rp.OwnerDisplayName, 1, 1)) || SUBSTR(rp.OwnerDisplayName, 2) AS FormattedOwnerName,
    CASE WHEN rp.rn_by_score = 1 THEN 'Top Post for Type' ELSE '' END AS RankIndicator
FROM RankedPosts rp
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
WHERE rp.rn_by_score <= 20
  AND rp.ViewCount > 100
  AND rp.OwnerReputation >= 0
ORDER BY rp.ViewCount DESC, rp.Score DESC
LIMIT 100;