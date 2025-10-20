WITH recent_posts AS (
  SELECT p.Id, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.AnswerCount, p.CommentCount, p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
    AND p.PostTypeId = 1
  ORDER BY p.CreationDate DESC
  LIMIT 100000
),
user_activity AS (
  SELECT u.Id AS UserId, SUM(v.BountyAmount) AS TotalBountyOffered, COUNT(v.Id) AS TotalVotes, COUNT(DISTINCT p.Id) AS TotalPosts
  FROM Users u
  LEFT JOIN Votes v ON u.Id = v.UserId
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
  GROUP BY u.Id
),
tag_popularity AS (
  SELECT t.TagName, COUNT(pt.Id) AS TagUsageCount
  FROM Tags t
  LEFT JOIN Posts pt ON pt.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    AND pt.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
  GROUP BY t.TagName
  ORDER BY COUNT(pt.Id) DESC
  LIMIT 1000
),
post_history AS (
  SELECT ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.UserDisplayName, ph.Comment, ph.Text
  FROM PostHistory ph
  WHERE ph.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
    AND ph.PostHistoryTypeId IN (4, 5, 6)
),
post_tags AS (
  -- expand tags per post to enable joining with tag_popularity without joining to a subquery in ON
  SELECT p.Id AS PostId, t.TagName
  FROM Posts p
  JOIN tag_popularity t ON p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
  WHERE p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
)
SELECT
  rp.Id AS PostId,
  rp.CreationDate AS PostCreationDate,
  rp.Score AS PostScore,
  rp.ViewCount AS PostViewCount,
  rp.OwnerUserId AS OwnerUserId,
  rp.AnswerCount AS AnswerCount,
  rp.CommentCount AS CommentCount,
  rp.FavoriteCount AS FavoriteCount,
  ua.TotalBountyOffered AS TotalBountyOffered,
  ua.TotalVotes AS TotalVotes,
  ua.TotalPosts AS TotalPosts,
  tp.TagName AS TopTags,
  tp.TagUsageCount AS TagUsageCount,
  ph.PostHistoryTypeId AS HistoryTypeId,
  ph.CreationDate AS HistoryCreationDate,
  ph.UserId AS HistoryUserId,
  ph.UserDisplayName AS HistoryUserDisplayName,
  ph.Comment AS HistoryComment,
  ph.Text AS HistoryText
FROM recent_posts rp
LEFT JOIN user_activity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN post_tags pt ON rp.Id = pt.PostId
LEFT JOIN tag_popularity tp ON pt.TagName = tp.TagName
LEFT JOIN post_history ph ON rp.Id = ph.PostId
GROUP BY
  rp.Id,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.OwnerUserId,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  ua.TotalBountyOffered,
  ua.TotalVotes,
  ua.TotalPosts,
  tp.TagName,
  tp.TagUsageCount,
  ph.PostHistoryTypeId,
  ph.CreationDate,
  ph.UserId,
  ph.UserDisplayName,
  ph.Comment,
  ph.Text
ORDER BY rp.CreationDate DESC;