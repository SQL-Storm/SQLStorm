-- {"query": "5559.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 809} 
WITH flagged_and_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.Id AS UserId,
    u.DisplayName AS UserDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    COUNT(DISTINCT ph.Id) AS HistoryCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= DATEADD(year, -2, CURRENT_DATE)
  GROUP BY
    p.Id, p.Title, p.PostTypeId, p.CreationDate, p.LastActivityDate,
    p.OwnerUserId, p.Score, p.ViewCount, p.Tags, p.AnswerCount,
    p.CommentCount, p.FavoriteCount, u.Id, u.DisplayName, u.Reputation,
    u.CreationDate, u.LastAccessDate
),
complex_pred AS (
  SELECT
    f.*,
    CASE
      WHEN f.Score > 5 AND f.ViewCount > 1000 THEN 1
      WHEN f.Reputation IS NULL THEN 0
      ELSE 2
    END AS engagement_level,
    CASE
      WHEN f.Tags LIKE '%<c%>%'
           OR f.Tags LIKE '%<java>%'
           OR f.Tags LIKE '%<sql>%'
      THEN true
      ELSE false
    END AS contains_triple_tag
  FROM flagged_and_activity f
),
windowed AS (
  SELECT
    ca.*,
    ROW_NUMBER() OVER (
      PARTITION BY ca.OwnerUserId
      ORDER BY ca.LastActivityDate DESC, ca.CreationDate DESC
    ) AS rn_per_user,
    SUM(CASE WHEN ca.LastActivityDate > ca.CreationDate THEN 1 ELSE 0 END) OVER (
      PARTITION BY ca.OwnerUserId
      ORDER BY ca.LastActivityDate
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_activities
  FROM complex_pred ca
),
aggregated AS (
  SELECT
    w.OwnerUserId,
    MAX(w.Reputation) AS max_reputation,
    MIN(w.CreationDate) AS first_post_date,
    AVG(w.engagement_level) AS avg_engagement,
    SUM(CASE WHEN w.engagement_level = 2 THEN 1 ELSE 0 END) AS alt_level_count,
    SUM(CASE WHEN w.contains_triple_tag THEN 1 ELSE 0 END) AS has_triple_tag_posts,
    COUNT(*) AS total_questions,
    SUM(w.ViewCount) AS total_views,
    STRING_AGG(w.Title, ' | ' ORDER BY w.LastActivityDate DESC) AS sample_titles
  FROM windowed w
  GROUP BY w.OwnerUserId
),
qualified AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (ORDER BY total_views DESC, total_questions DESC) AS rn_rank
  FROM aggregated a
)
SELECT
  q.OwnerUserId AS user_id,
  u.DisplayName AS user_display_name,
  q.max_reputation,
  q.first_post_date,
  q.avg_engagement,
  q.alt_level_count,
  q.has_triple_tag_posts,
  q.total_questions,
  q.total_views,
  q.sample_titles,
  q.rn_rank
FROM qualified q
LEFT JOIN Users u ON q.OwnerUserId = u.Id
WHERE q.rn_rank <= 50
ORDER BY q.rn_rank;