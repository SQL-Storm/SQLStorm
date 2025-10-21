-- {"query": "18077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1689} 

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
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_creation,
        RANK() OVER (ORDER BY p.Score DESC) AS r_score,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS previous_day_score
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS edit_count,
        MAX(ph.CreationDate) AS last_edit_date
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS posts_created,
        COUNT(DISTINCT c.Id) AS comments_made,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_given,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_given,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS gold_badges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS silver_badges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS bronze_badges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
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
    pht.edit_count,
    pht.last_edit_date,
    ua.posts_created,
    ua.comments_made,
    ua.upvotes_given,
    ua.downvotes_given,
    ua.gold_badges,
    ua.silver_badges,
    ua.bronze_badges,
    rp.rn_creation,
    rp.r_score,
    rp.previous_day_score,
    CASE
        WHEN rp.Score > 1000 AND rp.ViewCount > 50000 THEN 'Popular and High Score'
        WHEN rp.Score < 0 AND rp.ClosedDate IS NOT NULL THEN 'Closed and Negative Score'
        WHEN rp.AnswerCount > 10 AND rp.FavoriteCount > 5 THEN 'Highly Engaged Question'
        WHEN pht.edit_count > 5 THEN 'Frequently Edited Post'
        WHEN rp.OwnerDisplayName LIKE '%[deleted]%' THEN 'Deleted User Post'
        ELSE 'Standard Post'
    END AS post_categorization,
    COALESCE(rp.OwnerDisplayName, 'Community') AS owner_identifier,
    CASE WHEN rp.Score > rp.ViewCount / 1000.0 THEN 'High Score Ratio' ELSE 'Normal Score Ratio' END AS score_to_view_ratio,
    UPPER(SUBSTRING(rp.OwnerDisplayName, 1, 3)) AS owner_name_prefix,
    (rp.Score * 1.5 + rp.ViewCount * 0.2 + rp.FavoriteCount * 5.0) AS composite_score
FROM RankedPosts rp
LEFT JOIN PostHistorySummary pht ON rp.PostId = pht.PostId
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE rp.rn_creation <= 100 -- Top 100 by creation date within each post type
AND rp.r_score <= 500 -- Top 500 posts by score overall
AND COALESCE(rp.ClosedDate, '9999-12-31') < CURRENT_TIMESTAMP -- Consider only non-closed posts or posts closed in the far future for this analysis
UNION ALL
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
    pht.edit_count,
    pht.last_edit_date,
    ua.posts_created,
    ua.comments_made,
    ua.upvotes_given,
    ua.downvotes_given,
    ua.gold_badges,
    ua.silver_badges,
    ua.bronze_badges,
    rp.rn_creation,
    rp.r_score,
    rp.previous_day_score,
    CASE
        WHEN rp.Score > 1000 AND rp.ViewCount > 50000 THEN 'Popular and High Score'
        WHEN rp.Score < 0 AND rp.ClosedDate IS NOT NULL THEN 'Closed and Negative Score'
        WHEN rp.AnswerCount > 10 AND rp.FavoriteCount > 5 THEN 'Highly Engaged Question'
        WHEN pht.edit_count > 5 THEN 'Frequently Edited Post'
        WHEN rp.OwnerDisplayName LIKE '%[deleted]%' THEN 'Deleted User Post'
        ELSE 'Standard Post'
    END AS post_categorization,
    COALESCE(rp.OwnerDisplayName, 'Community') AS owner_identifier,
    CASE WHEN rp.Score > rp.ViewCount / 1000.0 THEN 'High Score Ratio' ELSE 'Normal Score Ratio' END AS score_to_view_ratio,
    UPPER(SUBSTRING(rp.OwnerDisplayName, 1, 3)) AS owner_name_prefix,
    (rp.Score * 1.5 + rp.ViewCount * 0.2 + rp.FavoriteCount * 5.0) AS composite_score
FROM RankedPosts rp
LEFT JOIN PostHistorySummary pht ON rp.PostId = pht.PostId
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE rp.rn_creation > 100 -- Posts not in the top 100 creation date
AND rp.r_score > 500 -- Posts not in the top 500 score overall
AND rp.Score > 50 -- Posts with a score greater than 50
ORDER BY rp.CreationDate DESC
LIMIT 500;
