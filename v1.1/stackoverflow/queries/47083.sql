WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) AS question_count,
        1 AS level
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1
      AND t.Count > 1000
    GROUP BY t.Id, t.TagName

    UNION ALL

    SELECT 
        t.Id,
        t.TagName,
        th.question_count,
        th.level + 1
    FROM tag_hierarchy th
    CROSS JOIN Tags t
    WHERE th.level < 3
      AND t.Id <> th.Id
),
user_expertise AS (
    SELECT 
        u.Id AS user_id,
        u.DisplayName,
        u.Reputation,
        EXTRACT(YEAR FROM u.CreationDate) AS join_year,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers,
        AVG(p.Score) AS avg_score,
        SUM(p.Score) AS total_score,
        COUNT(DISTINCT b.Name) AS unique_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), ',') AS top_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 5000
      AND u.CreationDate < (DATE '2024-10-01' - INTERVAL '365' DAY)
    GROUP BY u.Id, u.DisplayName, u.Reputation, EXTRACT(YEAR FROM u.CreationDate)
),
post_metrics AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.ViewCount > 0 THEN CAST(p.Score AS DOUBLE PRECISION) / p.ViewCount 
            ELSE 0 
        END AS engagement_ratio,
        COUNT(DISTINCT ph.UserId) AS editor_count,
        MAX(CASE WHEN ph.PostHistoryTypeId = 52 THEN 1 ELSE 0 END) AS was_hot_question,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS upvoters,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS downvoters,
        EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, TIMESTAMP '2024-10-01 12:34:56') - p.CreationDate))/3600 AS hours_until_closed,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.Score DESC) AS yearly_rank
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
      AND p.CreationDate > DATE '2020-01-01'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
             p.FavoriteCount, p.ClosedDate, p.CreationDate
),
answer_quality AS (
    SELECT 
        a.Id AS answer_id,
        a.ParentId AS question_id,
        a.Score AS answer_score,
        q.Score AS question_score,
        a.OwnerUserId,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS is_accepted,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/60 AS minutes_to_answer,
        LENGTH(a.Body) AS answer_length,
        (LENGTH(a.Body) - LENGTH(REPLACE(a.Body, '<code>', ''))) / 6 AS code_blocks,
        COUNT(c.Id) AS comment_count,
        AVG(c.Score) AS avg_comment_score
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2
      AND q.PostTypeId = 1
      AND a.Score > 0
    GROUP BY a.Id, a.ParentId, a.Score, q.Score, a.OwnerUserId, 
             q.AcceptedAnswerId, a.CreationDate, q.CreationDate, a.Body
),
top_user_posts AS (
    -- explicit derived table to avoid non-inner join on subquery in FROM for some engines
    SELECT p.*
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.join_year,
    ue.total_posts,
    ue.questions,
    ue.answers,
    ROUND(CAST(ue.avg_score AS NUMERIC), 2) AS avg_post_score,
    ue.gold_badges,
    ue.silver_badges,
    COUNT(DISTINCT pm.Id) AS top_questions,
    CAST(AVG(pm.engagement_ratio) AS NUMERIC(10,6)) AS avg_engagement,
    SUM(CASE WHEN pm.was_hot_question = 1 THEN 1 ELSE 0 END) AS hot_questions,
    COUNT(DISTINCT aq.answer_id) AS quality_answers,
    AVG(aq.minutes_to_answer) AS avg_response_time,
    SUM(aq.is_accepted) AS accepted_answers,
    AVG(aq.answer_length) AS avg_answer_length,
    SUM(aq.code_blocks) AS total_code_blocks,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pm.ViewCount) AS median_views,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY pm.Score) AS score_75th_percentile,
    SUBSTRING(ue.top_tags FROM 1 FOR 100) AS primary_tags
FROM user_expertise ue
LEFT JOIN post_metrics pm ON pm.Id IN (
    SELECT p2.Id
    FROM top_user_posts p2
    WHERE p2.OwnerUserId = ue.user_id
    ORDER BY p2.Score DESC
    LIMIT 10
)
LEFT JOIN answer_quality aq ON aq.OwnerUserId = ue.user_id
WHERE ue.total_posts > 50
GROUP BY ue.DisplayName, ue.Reputation, ue.join_year, ue.total_posts, 
         ue.questions, ue.answers, ue.avg_score, ue.gold_badges, 
         ue.silver_badges, ue.top_tags
HAVING COUNT(DISTINCT pm.Id) > 0
ORDER BY ue.Reputation DESC, SUM(aq.is_accepted) DESC
LIMIT 100;