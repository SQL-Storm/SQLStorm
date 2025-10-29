-- {"query": "4765.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1450} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_by_score_views,
        AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS total_views_by_type,
        LEAD(p.CreationDate, 1, '9999-12-31') OVER (ORDER BY p.CreationDate) AS next_post_creation_date
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2)
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS body_edit_count,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS last_body_edit_date,
        COUNT(DISTINCT ph.UserId) AS distinct_editors_count
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (2, 5) -- Initial Body, Edit Body
    GROUP BY ph.PostId
),
TopTagQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC) AS tag_rank
    FROM Posts AS p
    WHERE p.PostTypeId = 1 AND p.FavoriteCount IS NOT NULL
),
TagStats AS (
    SELECT
        t.TagName,
        t.Count AS tag_post_count,
        t.ExcerptPostId,
        t.WikiPostId,
        SUM(p.Score) AS total_score_for_tag,
        AVG(CAST(p.Score AS FLOAT)) AS avg_score_for_tag
    FROM Tags AS t
    LEFT JOIN Posts AS p ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AND p.PostTypeId = 1
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
    HAVING COUNT(p.Id) > 50 -- Only consider tags with a decent number of questions
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.AnswerCount,
    rp.rn_by_score_views,
    rp.avg_score_by_type,
    rp.total_views_by_type,
    COALESCE(phd.body_edit_count, 0) AS body_edit_count,
    phd.last_body_edit_date,
    phd.distinct_editors_count,
    ttq.tag_rank AS top_tag_question_rank,
    COALESCE(ts.tag_post_count, 0) AS total_questions_with_tag,
    ts.total_score_for_tag,
    ts.avg_score_for_tag,
    CASE
        WHEN rp.Score > (rp.avg_score_by_type * 1.5) THEN 'Above Average Score'
        WHEN rp.Score < (rp.avg_score_by_type * 0.5) THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS score_category,
    rp.next_post_creation_date,
    DATEDIFF(DAY, rp.PostCreationDate, rp.next_post_creation_date) AS days_until_next_post,
    LOWER(rp.Title) AS lower_case_title,
    REPLACE(rp.Title, ' ', '_') AS title_with_underscores,
    LENGTH(rp.Title) AS title_length,
    (rp.ViewCount * 1.0 / NULLIF(rp.AnswerCount, 0)) AS views_per_answer,
    CASE
        WHEN rp.FavoriteCount > 100 THEN 'Highly Favorited'
        WHEN rp.FavoriteCount > 50 THEN 'Moderately Favorited'
        ELSE 'Less Favorited'
    END AS favorite_status,
    UPPER(CONCAT(LEFT(rp.OwnerDisplayName, 1), SUBSTRING(rp.OwnerDisplayName, LENGTH(rp.OwnerDisplayName)-1, 2))) AS owner_initial_last_two,
    CASE WHEN rp.Score IS NULL OR rp.ViewCount IS NULL THEN 'Incomplete Metrics' ELSE 'Complete Metrics' END AS metric_completeness,
    rp.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31' AS created_in_2023,
    rp.PostCreationDate >= NOW() - INTERVAL '30 days' AS created_in_last_30_days
FROM RankedPosts AS rp
LEFT JOIN PostHistoryDetails AS phd ON rp.PostId = phd.PostId
LEFT JOIN TopTagQuestions AS ttq ON rp.PostId = ttq.Id
LEFT JOIN TagStats AS ts ON ts.TagName = ANY(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><'))
WHERE rp.rn_by_score_views <= 1000 -- Limit to top 1000 posts per type based on score/views
ORDER BY rp.PostTypeId, rp.rn_by_score_views;