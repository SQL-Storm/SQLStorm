-- {"query": "5082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1516} 
WITH recent_users AS (
    SELECT
        u.Id AS user_id,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        DENSE_RANK() OVER (ORDER BY u.CreationDate DESC) AS recency_rank
    FROM
        Users u
    WHERE
        u.Reputation > 1000
        AND u.CreationDate > CURRENT_DATE - INTERVAL '6 months'
),
question_info AS (
    SELECT
        p.Id AS question_id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        coalesce(p.AnswerCount, 0) AS AnswerCount,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_list,
        row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS rn_score_desc,
        avg(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score_by_user,
        p.ViewCount
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Questions
        AND p.CreationDate > CURRENT_DATE - INTERVAL '6 months'
),
badge_counts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        COUNT(*) AS total_badges
    FROM
        Badges b
    WHERE
        b.Date > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY
        b.UserId
),
most_used_tags AS (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
        COUNT(*) as usage_count
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 1
),
user_favorite_counts AS (
    SELECT
        v.UserId,
        COUNT(*) AS favorite_given
    FROM
        Votes v
    WHERE
        v.VoteTypeId = 5 -- Favorite (bookmark)
        AND v.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY v.UserId
),
top_answers AS (
    SELECT
        p.ParentId AS question_id,
        p.Id AS answer_id,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC NULLS LAST, p.CreationDate ASC) AS rn
    FROM
        Posts p
    WHERE
        p.PostTypeId = 2
        AND p.Score >= 1
),
closed_questions AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS closed_date,
        crt.Name AS close_reason
    FROM
        PostHistory ph
        LEFT JOIN CloseReasonTypes crt ON NULLIF(ph.Comment, '')::int = crt.Id
    WHERE
        ph.PostHistoryTypeId = 10
)
SELECT
    ru.user_id,
    ru.DisplayName,
    ru.CreationDate AS user_creation,
    ru.Reputation,
    bc.gold_badges,
    bc.silver_badges,
    bc.bronze_badges,
    COALESCE(bc.total_badges, 0) AS total_badges,
    q.question_id,
    q.Title AS question_title,
    q.CreationDate AS question_created,
    q.Score AS question_score,
    q.ViewCount,
    q.AnswerCount,
    CASE
        WHEN (q.AnswerCount > 5 OR q.Score > q.avg_score_by_user + 1.96*2) THEN 'Hot'
        ELSE 'Regular'
    END AS question_category,
    -- Tag string expressions
    array_to_string(q.tag_list, ', ') AS tag_list_string,
    (
        SELECT mt.tag
        FROM most_used_tags mt
        WHERE mt.tag = ANY(q.tag_list)
        ORDER BY mt.usage_count DESC
        LIMIT 1
    ) AS most_popular_tag,
    -- Top answer info
    ta.answer_id AS top_answer_id,
    ta.OwnerUserId AS top_answer_user,
    ta.Score AS top_answer_score,
    CASE WHEN ta.OwnerUserId = ru.user_id THEN 'Self-answered' ELSE 'Other' END AS top_answer_type,
    -- Closed information
    cq.closed_date,
    cq.close_reason,
    -- Recent favorite activity
    COALESCE(ufc.favorite_given, 0) AS favorites_given_last_6mo,
    -- Predicate for complex NULL logic and expressions
    CASE
        WHEN bc.total_badges IS NULL OR bc.total_badges = 0 THEN 'No Badges'
        WHEN bc.gold_badges > 0 THEN 'Gold'
        WHEN bc.silver_badges > 0 THEN 'Silver'
        WHEN bc.bronze_badges > 0 THEN 'Bronze'
        ELSE 'Other'
    END AS badge_tier,
    -- Complicated calculation: Z-score of question compared to all user's questions in last 6 months
    (q.Score - q.avg_score_by_user) /
        NULLIF(
            stddev_pop(q.Score) OVER (PARTITION BY q.OwnerUserId), 0
        ) AS question_score_z
FROM
    recent_users ru
    LEFT JOIN badge_counts bc ON bc.UserId = ru.user_id
    INNER JOIN question_info q ON q.OwnerUserId = ru.user_id AND q.rn_score_desc <= 3
    LEFT JOIN top_answers ta ON ta.question_id = q.question_id AND ta.rn = 1
    LEFT JOIN closed_questions cq ON cq.PostId = q.question_id
    LEFT JOIN user_favorite_counts ufc ON ufc.UserId = ru.user_id
WHERE
    (
        -- Example of an intricate predicate: highly active users or users with many gold badges, but filter out near-zero bronze-only users
        (ru.Reputation > 2500 AND COALESCE(bc.gold_badges, 0) > 1)
        OR (COALESCE(bc.silver_badges, 0) >= 5 AND COALESCE(ufc.favorite_given, 0) > 10)
    )
    AND (
        -- String and NULL logic: only questions tagged with the most popular tag, or that have "SQL" in their title, and are not closed for duplicate
        (
            (EXISTS (
                SELECT 1
                FROM most_used_tags mt
                WHERE mt.tag = ANY(q.tag_list)
                AND mt.usage_count = (SELECT MAX(usage_count) FROM most_used_tags)
            ))
            OR (
                lower(q.Title) LIKE '%sql%'
                AND COALESCE(cq.close_reason, '') NOT ILIKE '%duplicate%'
            )
        )
    )
ORDER BY
    ru.Reputation DESC,
    q.Score DESC,
    q.CreationDate DESC
LIMIT 100;