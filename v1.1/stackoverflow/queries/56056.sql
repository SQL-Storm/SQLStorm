WITH top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(DISTINCT p.Id) AS total_posts
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName
  ORDER BY total_posts DESC
  LIMIT 10
),
top_tags AS (
  SELECT t.TagName, COUNT(p.Id) AS total_questions
  FROM Tags t
  JOIN Posts p ON t.Id = (
    SELECT Id FROM Tags WHERE TagName = ANY(string_to_array(p.Tags, '<'))
  )
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  ORDER BY total_questions DESC
  LIMIT 10
),
post_history_stats AS (
  SELECT ph.PostHistoryTypeId, COUNT(ph.Id) AS total_history
  FROM PostHistory ph
  GROUP BY ph.PostHistoryTypeId
),
post_link_stats AS (
  SELECT pl.LinkTypeId, COUNT(pl.Id) AS total_links
  FROM PostLinks pl
  GROUP BY pl.LinkTypeId
)
SELECT 
  tu.DisplayName AS top_user,
  tu.total_posts,
  tt.TagName AS top_tag,
  tt.total_questions,
  phs.PostHistoryTypeId,
  phs.total_history,
  pls.LinkTypeId,
  pls.total_links,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount
FROM top_users tu
JOIN Posts p ON tu.Id = p.OwnerUserId
JOIN top_tags tt ON p.Id = (
  SELECT Id FROM Posts WHERE Tags LIKE '%' || tt.TagName || '%'
  LIMIT 1
)
JOIN post_history_stats phs ON p.Id = (
  SELECT PostId FROM PostHistory WHERE PostHistoryTypeId = phs.PostHistoryTypeId LIMIT 1
)
JOIN post_link_stats pls ON p.Id = (
  SELECT PostId FROM PostLinks WHERE LinkTypeId = pls.LinkTypeId LIMIT 1
)
GROUP BY
  tu.DisplayName,
  tu.total_posts,
  tt.TagName,
  tt.total_questions,
  phs.PostHistoryTypeId,
  phs.total_history,
  pls.LinkTypeId,
  pls.total_links,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount
ORDER BY tu.total_posts DESC, tt.total_questions DESC, phs.total_history DESC, pls.total_links DESC;