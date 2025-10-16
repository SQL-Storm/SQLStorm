-- {"query": "24001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1880} 

WITH question_stats AS (
    SELECT
        p.Id                AS question_id,
        p.OwnerUserId,
        p.Score             AS question_score,
        p.ViewCount,
        p.Tags,
        COALESCE(v.total_votes,0) AS vote_score,
        u.Reputation
    FROM Posts p
    LEFT JOIN Users u                 ON u.Id = p.OwnerUserId
    LEFT JOIN (
          SELECT
              v.PostId,
              SUM(CASE WHEN vt.Name = 'UpMod'  THEN  1
                       WHEN vt.Name = 'DownMod' THEN -1
                       ELSE 0 END) AS total_votes
          FROM Votes v
          JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
          GROUP BY v.PostId
    ) v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
),
tag_agg AS (
    SELECT
        t.TagName,
        COUNT(q.question_id)   AS question_count,
        SUM(q.question_score)  AS total_score,
        AVG(q.question_score)  AS avg_score,
        SUM(q.vote_score)      AS total_votes
    FROM Tags t
    JOIN question_stats q
      ON q.Tags LIKE CONCAT('%<', t.TagName, '>%' )
    GROUP BY t.TagName
    HAVING COUNT(q.question_id) > 50
),
recent_posts AS (
    SELECT
        t.TagName,
        COUNT(*)               AS recent_cnt
    FROM Posts p
    JOIN Tags t
      ON p.Tags LIKE CONCAT('%<', t.TagName, '>%' )
    WHERE p.LastActivityDate > NOW() - INTERVAL '30 days'
    GROUP BY t.TagName
),
required_tags AS (
    SELECT TagName FROM Tags WHERE IsRequired = 1 OR IsModeratorOnly = 1
),
combined AS (
    SELECT
        a.TagName,
        a.question_count,
        a.total_score,
        a.avg_score,
        a.total_votes,
        COALESCE(r.recent_cnt,0) AS recent_cnt,
        CASE WHEN r.recent_cnt > 10 THEN 1 ELSE 0 END AS recent_flag
    FROM tag_agg a
    LEFT JOIN recent_posts r ON r.TagName = a.TagName
)
SELECT
    c.TagName,
    c.question_count,
    c.total_score,
    c.avg_score,
    c.total_votes,
    c.recent_cnt,
    STRING_AGG(DISTINCT CASE WHEN ct.TagName IS NOT NULL THEN ct.TagName END,
               ', ') WITHIN GROUP (ORDER BY ct.TagName) AS required_or_recent_tags,
    SUM(CASE WHEN c.recent_flag = 1 THEN 1 ELSE 0 END) OVER () AS recent_tag_total
FROM combined c
LEFT JOIN required_tags ct ON ct.TagName = c.TagName
WHERE c.question_count > 100
  AND (c.total_score > 0 OR c.total_votes IS NOT NULL)
GROUP BY c.TagName, c.question_count, c.total_score, c.avg_score, c.total_votes, c.recent_cnt
ORDER BY c.total_score DESC
LIMIT 100;
