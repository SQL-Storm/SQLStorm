-- {"query": "5211.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1022}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_pop AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount
  FROM Tags t
  GROUP BY t.TagName
),
activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    LEAD(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate) AS NextActivity
  FROM Posts p
  WHERE p.PostTypeId = 1
),
complex_metrics AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.AnswerCount,
    v.VoteCount_Up AS Upvotes,
    v.VoteCount_Down AS Downvotes,
    (v.VoteCount_Up - v.VoteCount_Down) AS NetScore,
    CASE
      WHEN r.OwnerUserId IS NULL THEN 'Anonymous'
      ELSE u.DisplayName
    END AS OwnerDisplayName,
    CASE
      WHEN u.Reputation >= 1000 THEN 'Trusted'
      WHEN u.Reputation >= 100 THEN 'Learner'
      ELSE 'Newbie'
    END AS ReputationTier,
    r.OwnerUserId
  FROM recent_questions r
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS VoteCount_Up,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS VoteCount_Down
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = r.PostId
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
),
string_ops AS (
  SELECT
    cm.PostId,
    cm.Title,
    cm.Upvotes,
    cm.Downvotes,
    cm.NetScore,
    '[' || COALESCE(STRING_AGG(t.TagName, ',' ORDER BY t.TagName), '') || ']' AS TagsArray,
    UPPER(SUBSTR(cm.OwnerDisplayName, 1, 1)) || LOWER(SUBSTR(cm.OwnerDisplayName, 2)) AS OwnerNameNormalized
  FROM complex_metrics cm
  LEFT JOIN Posts p ON p.Id = cm.PostId
  LEFT JOIN Tags t ON EXISTS (
      SELECT 1
      FROM UNNEST(STRING_TO_ARRAY(CAST(p.Tags AS varchar), ',')) AS tagid
      WHERE CAST(tagid AS varchar) = CAST(t.Id AS varchar)
  )
  GROUP BY cm.PostId, cm.Title, cm.Upvotes, cm.Downvotes, cm.NetScore, cm.OwnerDisplayName
),
outer_join_example AS (
  SELECT
    qr.PostId,
    qr.Title,
    qr.CreationDate,
    qr.LastActivityDate,
    qr.Score,
    qr.ViewCount,
    qr.CommentCount,
    qr.AnswerCount,
    a.NextActivity,
    u.DisplayName AS OwnerName,
    qr.OwnerUserId
  FROM recent_questions qr
  LEFT JOIN activity a ON a.PostId = qr.PostId
  LEFT JOIN Users u ON u.Id = qr.OwnerUserId
),
window_calc AS (
  SELECT
    oje.PostId,
    oje.Title,
    oje.OwnerName,
    oje.LastActivityDate,
    oje.ViewCount,
    oje.Score,
    ROW_NUMBER() OVER (PARTITION BY oje.OwnerName ORDER BY oje.LastActivityDate DESC) AS rn_last_activity,
    AVG(oje.ViewCount) OVER (PARTITION BY oje.OwnerName) AS avg_views_per_owner,
    MAX(oje.Score) OVER () AS max_overall_score
  FROM outer_join_example oje
)
SELECT
  w.PostId,
  w.Title,
  w.OwnerName,
  w.LastActivityDate,
  w.ViewCount,
  w.Score,
  w.avg_views_per_owner,
  w.max_overall_score,
  w.rn_last_activity,
  s.TagsArray,
  w.OwnerName AS canonical_owner
FROM window_calc w
LEFT JOIN string_ops s ON s.PostId = w.PostId
WHERE
  w.rn_last_activity = 1
  AND w.ViewCount > 0
  AND w.Score >= 0
ORDER BY w.max_overall_score DESC, w.LastActivityDate DESC
LIMIT 100;