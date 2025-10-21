-- {"query": "54074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1185} 
WITH question_tags AS (
    SELECT 
        p.Id            AS question_id,
        t.TagName,
        p.OwnerUserId
    FROM Posts p
    JOIN Tags t 
        ON POSITION(t.TagName IN p.Tags) > 0
    WHERE p.PostTypeId = 1
),
last_edit AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS last_edit_date
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)          -- Edit Title, Body or Tags
    GROUP BY ph.PostId
),
tag_stats AS (
    SELECT
        qt.TagName,
        COUNT(*)                                 AS question_count,
        SUM(p.ViewCount)                         AS total_views,
        AVG(p.Score)                             AS avg_score,
        COUNT(a.Id)                              AS answer_count,
        AVG(a.Score)                             AS avg_answer_score,
        MAX(le.last_edit_date)                   AS last_edit_date
    FROM question_tags qt
    JOIN Posts p ON p.Id = qt.question_id
    LEFT JOIN Posts a ON a.ParentId = qt.question_id
                       AND a.PostTypeId = 2
    LEFT JOIN last_edit le ON le.PostId = p.Id
    GROUP BY qt.TagName
),
top_users AS (
    SELECT
        qt.TagName,
        u.Id            AS user_id,
        u.DisplayName,
        COUNT(*)        AS questions_in_tag,
        RANK() OVER (PARTITION BY qt.TagName ORDER BY COUNT(*) DESC) AS rk
    FROM question_tags qt
    JOIN Users u ON u.Id = qt.OwnerUserId
    GROUP BY qt.TagName, u.Id, u.DisplayName
)
SELECT
    ts.TagName,
    ts.question_count,
    ts.answer_count,
    ts.total_views,
    ts.avg_score,
    ts.avg_answer_score,
    ts.last_edit_date,
    tu.DisplayName AS top_user,
    tu.questions_in_tag AS top_user_questions
FROM tag_stats ts
LEFT JOIN top_users tu
    ON ts.TagName = tu.TagName AND tu.rk = 1
ORDER BY ts.question_count DESC
LIMIT 100;