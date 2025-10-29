-- {"query": "5294.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 763} 
WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    pt.Name AS PostTypeName
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  WHERE pt.Id = 1 -- Questions only
),
tag_aggregate AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_question_count,
    AVG(p.Score) AS avg_score,
    MAX(p.ViewCount) AS max_views,
    MIN(p.CreationDate) AS first_question,
    STRING_AGG(p.OwnerDisplayName, ',') AS distinct_owners
  FROM (
    SELECT
      TRIM(BOTH '><' FROM q.Tag) AS TagName,
      q.Id,
      q.Score,
      q.ViewCount,
      q.OwnerDisplayName,
      q.CreationDate
    FROM top_questions q
    CROSS APPLY (
      SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS Tag
    ) AS t
  ) q
  JOIN Tags t ON t.TagName = q.TagName
  GROUP BY t.TagName
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.LastEditDate,
    p.AnswerCount,
    p.CommentCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_user
  FROM Posts p
  WHERE p.PostTypeId = 1
),
complex_pred AS (
  SELECT
    pr.PostId,
    pr.Title,
    pr.OwnerUserId,
    pr.LastActivityDate,
    pr.Score,
    pr.ViewCount,
    CASE
      WHEN pr.Score >= 100 THEN 'Elite'
      WHEN pr.Score >= 50 THEN 'Rising'
      WHEN pr.Score >= 0 THEN 'Popular'
      ELSE 'New'
    END AS popularity_band,
    CASE
      WHEN pr.ViewCount > 1000 THEN true
      ELSE false
    END AS high_visibility
  FROM top_questions pr
),
outer_join_demo AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.OwnerUserId,
    tq.OwnerDisplayName,
    tq.LastActivityDate,
    ca.avg_score,
    ca.max_views,
    ca.first_question
  FROM top_questions tq
  LEFT JOIN tag_aggregate ca ON true
),
final AS (
  SELECT
    oq.PostId,
    oq.Title,
    oq.OwnerUserId,
    oq.OwnerDisplayName,
    oq.LastActivityDate,
    oq.avg_score,
    oq.max_views,
    oq.first_question,
    ca.tag_question_count,
    ca.distinct_owners,
    pa.popularity_band,
    pa.high_visibility,
    TO_CHAR(oq.LastActivityDate, 'YYYY-MM-DD HH24:MI:SS') AS last_activity_str,
    CASE
      WHEN oq.Title IS NOT NULL THEN LENGTH(oq.Title)
      ELSE 0
    END AS title_length
  FROM outer_join_demo oq
  LEFT JOIN tag_aggregate ca ON TRUE
  LEFT JOIN complex_pred pa ON pa.PostId = oq.PostId
  ORDER BY oq.LastActivityDate DESC
  LIMIT 100
)
SELECT *
FROM final
;