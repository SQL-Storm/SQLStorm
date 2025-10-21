-- {"query": "18012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1311} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_user_creation,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS dr_score,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS comment_count_per_post,
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL AND p.AnswerCount > 0 THEN 'Has Accepted Answer'
            WHEN p.AnswerCount > 0 THEN 'Has Answers, No Accepted'
            ELSE 'No Answers'
        END AS answer_status
    FROM Posts AS p
    LEFT JOIN Comments AS c
        ON p.Id = c.PostId
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS total_post_edits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS body_edit_count,
        AVG(rp.Score) FILTER (WHERE rp.rn_user_creation <= 5) AS avg_score_top_5_posts,
        MAX(rp.CreationDate) AS latest_post_creation
    FROM Users AS u
    LEFT JOIN PostHistory AS ph
        ON u.Id = ph.UserId
    LEFT JOIN RankedPosts AS rp
        ON u.Id = rp.OwnerUserId
    WHERE
        u.Reputation > 1000 AND u.Views > 5000
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate
),
TagPerformance AS (
    SELECT
        TRIM(REPLACE(REPLACE(REPLACE(t.TagName, '<', ''), '>', ''), '/', '')) AS CleanTagName,
        COUNT(p.Id) AS tag_post_count,
        SUM(p.Score) AS total_tag_score,
        AVG(p.ViewCount) AS avg_tag_view_count,
        (SUM(p.FavoriteCount) * 1.0 / NULLIF(COUNT(p.Id), 0)) AS avg_favorites_per_post
    FROM Tags AS t
    JOIN Posts AS p
        ON t.TagName = ANY(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))
    WHERE
        p.PostTypeId = 1 AND p.CreationDate > '2023-01-01'
    GROUP BY
        TRIM(REPLACE(REPLACE(REPLACE(t.TagName, '<', ''), '>', ''), '/', ''))
    HAVING
        COUNT(p.Id) > 10
)
SELECT
    rp.PostId,
    rp.Title,
    rp.answer_status,
    rp.comment_count_per_post,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    COALESCE(ua.DisplayName, 'Unknown User') AS UserDisplayName,
    ua.Reputation,
    ua.total_post_edits,
    ua.body_edit_count,
    ua.avg_score_top_5_posts,
    tp.CleanTagName,
    tp.tag_post_count,
    tp.total_tag_score,
    tp.avg_tag_view_count,
    tp.avg_favorites_per_post,
    CASE
        WHEN rp.Score > 100 THEN 'High Score'
        WHEN rp.Score BETWEEN 10 AND 100 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS score_category,
    EXTRACT(YEAR FROM rp.CreationDate) AS post_year,
    LOWER(SUBSTRING(rp.Title FROM 1 FOR 3)) AS title_prefix,
    rp.dr_score AS global_score_rank,
    CASE WHEN rp.FavoriteCount > (SELECT AVG(FavoriteCount) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg Favorites' ELSE 'Below Avg Favorites' END AS favorite_comparison
FROM
    RankedPosts AS rp
LEFT JOIN
    UserActivity AS ua
        ON rp.OwnerUserId = ua.UserId
LEFT JOIN
    TagPerformance AS tp
        ON SUBSTRING(rp.Title FROM '#(\d+)#' FROM 1) = tp.CleanTagName -- Example of a very contrived string operation trying to extract a tag from title
WHERE
    rp.rn_user_creation <= 10
    AND rp.PostTypeId = 1
    AND ua.Reputation IS NOT NULL
    AND rp.Score > 0
    AND rp.Title IS NOT NULL
    AND LENGTH(rp.Title) > 15
    AND rp.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
ORDER BY
    rp.Score DESC,
    rp.ViewCount DESC
LIMIT 100;
