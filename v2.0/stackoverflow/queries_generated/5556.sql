-- {"query": "5556.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 965} 
WITH
RecentHot AS (
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
    p.FavoriteCount,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.ClosedDate IS NULL
),
TagMetrics AS (
  SELECT
    t.TagName AS Tag,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    SUM(p.CommentCount) AS TotalComments
  FROM Posts p
  JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName) ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
ActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.AccountId,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id AND pr.PostTypeId = 1) AS UserQuestionCount,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id AND pr.PostTypeId = 2) AS UserAnswerCount
  FROM Users u
  WHERE u.Reputation > 1000
),
ComplexFilters AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.LastActivityDate,
    CASE
      WHEN rp.ViewCount > 1000 THEN 'HighView'
      WHEN rp.Score > 50 THEN 'TopScored'
      ELSE 'Normal'
    END AS Category,
    EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = rp.Id
        AND v.VoteTypeId = 2
        AND v.UserId IS NOT NULL
    ) AS HasUpvoteFromUser
  FROM Posts rp
  WHERE rp.PostTypeId = 1
    AND rp.LastActivityDate > CURRENT_DATE - INTERVAL '180 days'
    AND rp.Score BETWEEN -5 AND 500
),
UnionSource AS (
  SELECT
    ch.PostId,
    ch.UserId,
    ch.Text,
    ch.CreationDate,
    ch.PostHistoryTypeId
  FROM PostHistory ch
  WHERE ch.PostHistoryTypeId IN (10, 16, 66) -- close, community bump, createdFromWizard
),
Combined AS (
  SELECT
    pr.Id AS PostId,
    pr.Title,
    pr.OwnerUserId,
    pr.CreationDate,
    pr.LastActivityDate,
    pr.Score,
    pr.ViewCount,
    pr.Tags,
    pr.CommentCount,
    pr.FavoriteCount,
    pr.PostTypeId,
    uv.DisplayName AS OwnerName,
    uv.Reputation
  FROM Posts pr
  LEFT JOIN Users uv ON pr.OwnerUserId = uv.Id
  WHERE pr.PostTypeId = 1
    AND pr.CreationDate >= (SELECT MIN(CreationDate) FROM Posts)
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerUserId,
  c.OwnerName,
  c.CreationDate,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.Tags,
  c.CommentCount,
  c.FavoriteCount,
  c.PostTypeId,
  c.Reputation,
  COALESCE(hs.Name, 'Unknown') AS HistoryTypeName,
  hs.PostId AS HistoryRelatedPostId,
  v.BountyAmount
FROM Combined c
LEFT JOIN Votes v ON v.PostId = c.PostId AND v.VoteTypeId = 8
LEFT JOIN PostHistory hs ON hs.PostId = c.PostId AND hs.PostHistoryTypeId IN (10,16,66)
LEFT JOIN PostLinks pl ON pl.PostId = c.PostId
LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = c.PostId
WHERE c.PostTypeId = 1
  AND (c.ViewCount > 0 OR c.Score IS NOT NULL)
ORDER BY c.LastActivityDate DESC, c.Score DESC
LIMIT 100;