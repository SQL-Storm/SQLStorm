WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180' DAY
),
top_tags AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS total_score,
    AVG(p.ViewCount) AS avg_views,
    COUNT(*) AS questions
  FROM Posts p,
       LATERAL (
         SELECT REGEXP_REPLACE(TRIM(BOTH '<>' FROM tag_part), '[<>]', '') AS tagname
         FROM UNNEST(string_to_array(COALESCE(p.Tags, ''), '>')) AS tag_part
       ) taglist
  JOIN Tags t ON t.TagName = taglist.tagname
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
complex_calc AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    q.CreationDate AS QuestionCreationDate,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    (q.Score * 0.6) + (q.ViewCount * 0.4) AS engagement_score,
    CASE
      WHEN q.Score > 0 THEN 'positive'
      WHEN q.Score = 0 THEN 'neutral'
      ELSE 'negative'
    END AS score_trend,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.PostId AND a.PostTypeId = 2) AS answer_count,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 2) AS upvotes_received,
    (SELECT STRING_AGG(cv.Name, ',') FROM Votes v2 JOIN VoteTypes cv ON cv.Id = v2.VoteTypeId WHERE v2.PostId = q.PostId AND v2.VoteTypeId = 2) AS upvote_types,
    q.Tags
  FROM recent_questions q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  WHERE q.rn = 1
),
outer_join_demo AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.Reputation,
    c.UserCreationDate,
    c.QuestionCreationDate,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.engagement_score,
    c.score_trend,
    c.answer_count,
    c.upvotes_received,
    c.upvote_types,
    CONCAT(COALESCE(c.Title, ''), ' | ', COALESCE(c.Tags, '')) AS title_and_tags,
    b.Name AS badge_name,
    b.Date AS badge_date
  FROM complex_calc c
  LEFT JOIN Badges b ON b.UserId = c.OwnerUserId AND b.Class = 1
  ORDER BY c.engagement_score DESC
  LIMIT 100
)
SELECT
  oj.PostId,
  oj.Title,
  oj.OwnerUserId,
  oj.Reputation,
  oj.UserCreationDate,
  oj.QuestionCreationDate,
  oj.LastActivityDate,
  oj.Score,
  oj.ViewCount,
  oj.engagement_score,
  oj.score_trend,
  oj.answer_count,
  oj.upvotes_received,
  oj.upvote_types,
  oj.title_and_tags,
  oj.badge_name,
  oj.badge_date
FROM outer_join_demo oj
WHERE oj.engagement_score > (
  SELECT AVG(engagement_score) FROM outer_join_demo
) OR oj.badge_name IS NOT NULL
ORDER BY oj.engagement_score DESC, (oj.badge_date IS NULL) ASC, oj.badge_date;