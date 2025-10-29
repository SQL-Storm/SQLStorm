-- {"query": "5043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 866} 
WITH top_influencers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    MAX(p.CreationDate) AS LastPostDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.Score,
    p.Views,
    p.LastActivityDate,
    pc.Count AS CommentCount,
    COALESCE(al.AttachmentCount, 0) AS AttachmentCount
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Count
    FROM Comments
    GROUP BY PostId
  ) pc ON pc.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS AttachmentCount
    FROM PostLinks
    WHERE LinkTypeId = 1
    GROUP BY PostId
  ) al ON al.PostId = p.Id
  WHERE p.LastActivityDate > CURRENT_DATE - INTERVAL '90 days'
),
tag_aggregation AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
complex_pred AS (
  SELECT
    t.TagName,
    ta.PostId,
    ta.Title,
    ta.OwnerUserId,
    t.Count AS TagCount
  FROM (
    SELECT TagName, COUNT(*) AS Count
    FROM tag_aggregation
    GROUP BY TagName
  ) t
  JOIN tag_aggregation ta ON ta.TagName = t.TagName
),
windowed AS (
  SELECT
    po.PostId,
    po.Title,
    po.OwnerUserId,
    po.PostTypeId,
    po.Score,
    po.Views,
    ROW_NUMBER() OVER (PARTITION BY po.PostTypeId ORDER BY po.Score DESC, po.Views DESC) AS rn
  FROM recent_activity po
),
final_select AS (
  SELECT
    wu.UserId,
    wu.DisplayName,
    wi.ScoreSum,
    wi.PostCount,
    wi.UpvotesReceived,
    wi.DownvotesReceived,
    ra.PostId,
    ra.Title,
    ra.TagName,
    ra.PostTypeId,
    ra.Score,
    ra.Views,
    ra.LastPostDate
  FROM top_influencers wi
  LEFT JOIN users wu ON wu.Id = wi.UserId
  LEFT JOIN windowed ra ON ra.PostId = (SELECT MAX(PostId) FROM windowed w2 WHERE w2.OwnerUserId = wu.Id)
  WHERE wi.Reputation > 1000
  ORDER BY wi.ScoreSum DESC, wi.PostCount DESC
  LIMIT 100
)
SELECT
  f.UserId,
  f.DisplayName,
  f.ScoreSum AS TotalScore,
  f.PostCount AS TotalPosts,
  f.UpvotesReceived AS Upvotes,
  f.DownvotesReceived AS Downvotes,
  f.PostId,
  f.Title,
  f.TagName,
  CASE WHEN f.PostTypeId = 1 THEN 'Question' ELSE 'Other' END AS PostKind,
  f.Score,
  f.Views,
  f.LastPostDate
FROM final_select f
LEFT JOIN PostHistory ph ON ph.PostId = f.PostId
LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
WHERE ph.Id IS NULL OR ph.Id IS NOT NULL
ORDER BY f.TotalScore DESC, f.TotalPosts DESC
;