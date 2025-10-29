WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE (t.IsModeratorOnly = FALSE OR t.IsModeratorOnly IS NULL)
),
activity_summary AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.OwnerUserId,
    rq.Tags,
    rq.LastActivityDate,
    rq.AnswerCount,
    rq.CommentCount,
    rq.FavoriteCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COALESCE(bp.TotalBadges, 0) AS BadgeCount,
    COALESCE(vk.TotalVotes, 0) AS TotalVotes
  FROM recent_questions rq
  LEFT JOIN Users u ON rq.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) bp ON rq.OwnerUserId = bp.UserId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS TotalVotes
    FROM Votes
    GROUP BY PostId
  ) vk ON rq.PostId = vk.PostId
),
cross_refs AS (
  SELECT
    a.PostId,
    a.Title,
    a.OwnerUserId,
    a.TotalVotes,
    c.RelatedPostId,
    ldt.Name AS LinkTypeName
  FROM activity_summary a
  LEFT JOIN PostLinks c ON a.PostId = c.PostId
  LEFT JOIN LinkTypes ldt ON c.LinkTypeId = ldt.Id
),
complex_expr AS (
  SELECT
    ar.PostId,
    ar.Title,
    ar.OwnerUserId,
    ar.TotalVotes,
    ARRAY_AGG(DISTINCT t.TagName) AS TagNames,
    (ar.TotalVotes + COALESCE(ar.ViewCount, 0) * 0.5) AS EngagementScore,
    (SELECT COUNT(*) FROM Comments co WHERE co.PostId = ar.PostId) AS CommentCountForPost
  FROM activity_summary ar
  LEFT JOIN Posts p ON ar.PostId = p.Id
  LEFT JOIN LATERAL (
    SELECT unnest_tag
    FROM UNNEST(string_to_array(p.Tags, '><')) AS u(unnest_tag)
  ) tagvals ON TRUE
  LEFT JOIN Tags t ON t.TagName = tagvals.unnest_tag
  GROUP BY ar.PostId, ar.Title, ar.OwnerUserId, ar.TotalVotes, ar.ViewCount
),
final AS (
  SELECT
    ce.PostId,
    ce.Title,
    ce.OwnerUserId,
    ce.TotalVotes,
    ce.TagNames,
    ce.EngagementScore,
    ce.CommentCountForPost,
    cr.RelatedPostId,
    cr.LinkTypeName,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName
  FROM complex_expr ce
  LEFT JOIN cross_refs cr ON ce.PostId = cr.PostId
  LEFT JOIN Users u ON ce.OwnerUserId = u.Id
  ORDER BY ce.EngagementScore DESC NULLS LAST
)
SELECT
  f.PostId,
  f.Title,
  f.OwnerDisplayName,
  f.Reputation,
  f.TotalVotes,
  f.TagNames,
  f.EngagementScore,
  f.CommentCountForPost,
  f.RelatedPostId,
  f.LinkTypeName
FROM final f
LIMIT 100;