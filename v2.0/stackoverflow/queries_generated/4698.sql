-- {"query": "4698.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1579} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_type,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS previous_post_score,
        SUM(c.Score) OVER (PARTITION BY p.Id) AS total_comment_score,
        COUNT(ph.Id) OVER (PARTITION BY p.Id) AS post_history_count,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS is_closed_flag
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, pt.Name
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(rp.PostId) AS total_posts_by_user,
        SUM(rp.PostScore) AS total_score_of_user_posts,
        AVG(rp.PostViewCount) AS avg_view_count_of_user_posts,
        SUM(CASE WHEN rp.is_closed_flag = 1 THEN 1 ELSE 0 END) AS closed_posts_count,
        MAX(rp.PostCreationDate) AS last_post_creation_date
    FROM Users u
    JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagPerformance AS (
    SELECT
        t.TagName,
        t.Count AS tag_post_count,
        AVG(rp.PostScore) AS avg_score_for_tag,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count_for_tag,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count_for_tag
    FROM Tags t
    JOIN Posts p ON t.TagName IN (SELECT value FROM UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '')) AS value)
    JOIN RankedPosts rp ON p.Id = rp.PostId AND rp.PostTypeId = 1 -- Only considering questions for tag performance
    GROUP BY t.TagName, t.Count
),
UnionLatestEdits AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.UserId AS EditorUserId,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn_edit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.total_comment_score,
    rp.post_history_count,
    rp.is_closed_flag,
    CASE
        WHEN rp.AnswerCount > 0 THEN CAST(rp.Score * 1.0 / rp.AnswerCount AS DECIMAL(10, 2))
        ELSE 0.00
    END AS score_per_answer,
    CONCAT(
        COALESCE(ups.DisplayName, 'Anonymous'),
        ' (Rep: ', ups.Reputation, ')',
        ' - Posts: ', ups.total_posts_by_user
    ) AS author_info,
    ups.avg_view_count_of_user_posts,
    ups.closed_posts_count,
    tp.TagName,
    tp.avg_score_for_tag,
    tp.question_count_for_tag,
    tp.answer_count_for_tag,
    ue.EditDate AS latest_edit_date,
    ue.EditorUserId AS latest_editor_id,
    rp.PostCreationDate < ups.UserCreationDate AS was_created_before_user,
    rp.rn_by_type,
    rp.previous_post_score,
    CASE WHEN rp.Score > rp.previous_post_score THEN 'Increased' WHEN rp.Score < rp.previous_post_score THEN 'Decreased' ELSE 'Same' END AS score_change_vs_previous,
    CASE WHEN pht.Name = 'Post Closed' THEN 'Yes' ELSE 'No' END AS is_post_closed_history,
    CASE WHEN pl.LinkTypeId = 3 THEN 'Duplicate Link' ELSE 'Other Link' END AS post_link_type
FROM RankedPosts rp
JOIN Users ups ON rp.OwnerUserId = ups.Id
LEFT JOIN LATERAL (
    SELECT STRING_AGG(tp_inner.TagName, ', ') AS TagName, SUM(tp_inner.avg_score_for_tag) AS avg_score_for_tag, SUM(tp_inner.question_count_for_tag) AS question_count_for_tag, SUM(tp_inner.answer_count_for_tag) AS answer_count_for_tag
    FROM TagPerformance tp_inner
    WHERE rp.PostId IN (SELECT PostId FROM Posts p_inner WHERE p_inner.Tags LIKE '%' || tp_inner.TagName || '%')
    GROUP BY rp.PostId
) tp ON TRUE
LEFT JOIN UnionLatestEdits ue ON rp.PostId = ue.PostId AND ue.rn_edit = 1
LEFT JOIN PostHistoryTypes pht ON pht.Id = 10 -- For Post Closed
LEFT JOIN PostLinks pl ON rp.PostId = pl.PostId AND pl.LinkTypeId = 3 -- For duplicate links
WHERE rp.rn_by_type <= 1000 -- Limit to top 1000 posts by type for performance
ORDER BY rp.PostCreationDate DESC
LIMIT 500;
