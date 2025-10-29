-- {"query": "4734.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1461} 
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
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score_views,
        AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS avg_score_per_type,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS comment_count_for_post,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS previous_post_score
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
UserPostActivity AS (
    SELECT
        ph.UserId,
        u.DisplayName AS UserDisplayName,
        COUNT(DISTINCT ph.PostId) AS distinct_posts_edited,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS edit_count,
        SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS initial_body_count,
        AVG(DATEDIFF(second, p.CreationDate, ph.CreationDate)) AS avg_time_to_first_edit_seconds,
        MAX(ph.CreationDate) AS last_activity_date
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (4, 5, 6, 2)
    GROUP BY ph.UserId, u.DisplayName
    HAVING COUNT(DISTINCT ph.PostId) > 5
),
TagEngagement AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS number_of_questions_with_tag,
        SUM(p.AnswerCount) AS total_answers_for_tag,
        AVG(p.Score) AS average_score_for_tag,
        COUNT(DISTINCT ph.UserId) AS distinct_users_editing_tag_posts
    FROM Tags t
    JOIN Posts p ON CHARINDEX('<' + t.TagName + '>', p.Tags) > 0 AND p.PostTypeId = 1
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 6 -- Edit Tags
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 1000
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
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    rp.rn_score_views,
    rp.avg_score_per_type,
    rp.comment_count_for_post,
    rp.previous_post_score,
    COALESCE(upa.edit_count, 0) AS user_total_edits,
    COALESCE(upa.initial_body_count, 0) AS user_initial_body_posts,
    upa.avg_time_to_first_edit_seconds,
    te.number_of_questions_with_tag,
    te.total_answers_for_tag,
    te.average_score_for_tag,
    te.distinct_users_editing_tag_posts,
    CASE
        WHEN rp.Score > rp.avg_score_per_type * 1.5 THEN 'Above Average'
        WHEN rp.Score < rp.avg_score_per_type * 0.5 THEN 'Below Average'
        ELSE 'Average'
    END AS ScoreCategory,
    CASE
        WHEN rp.CommentCount > (SELECT AVG(CommentCount) FROM Posts WHERE PostTypeId = rp.PostTypeId) * 2 THEN 'High Comment Volume'
        ELSE 'Normal Comment Volume'
    END AS CommentVolumeCategory,
    CASE
        WHEN rp.FavoriteCount > (SELECT AVG(FavoriteCount) FROM Posts WHERE PostTypeId = rp.PostTypeId) * 3 THEN 'Very Popular'
        ELSE 'Standard Popularity'
    END AS PopularityCategory,
    SUBSTRING(rp.OwnerDisplayName, 1, 3) AS OwnerNamePrefix,
    CONCAT(rp.PostTypeName, ' - ', rp.OwnerDisplayName) AS PostIdentifier,
    CASE
        WHEN rp.CommentCount IS NULL OR rp.AnswerCount IS NULL THEN 'Missing Count Data'
        WHEN rp.CommentCount = 0 AND rp.AnswerCount = 0 THEN 'No Interaction'
        WHEN rp.CommentCount > rp.AnswerCount THEN 'More Comments than Answers'
        ELSE 'More Answers than Comments'
    END AS InteractionRatio,
    UPPER(COALESCE(rp.PostTypeName, 'UNKNOWN')) AS PostTypeUpper,
    rp.OwnerUserId % 10 AS OwnerUserIdMod10
FROM RankedPosts rp
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.UserId
LEFT JOIN TagEngagement te ON EXISTS (
    SELECT 1
    FROM Posts p_tag
    JOIN Tags t_tag ON CHARINDEX('<' + t_tag.TagName + '>', p_tag.Tags) > 0 AND p_tag.PostTypeId = 1
    WHERE p_tag.Id = rp.PostId AND t_tag.TagName = te.TagName
)
WHERE rp.rn_score_views <= 100 -- Top 100 posts by score/view count per type
ORDER BY rp.PostTypeId, rp.rn_score_views;