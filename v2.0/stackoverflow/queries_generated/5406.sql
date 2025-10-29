-- {"query": "5406.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 704} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.LastActivityDate,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName) ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  ORDER BY PostCount DESC
  LIMIT 50
),
UserImpact AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    AVG(p.Score) AS AvgPostScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
MixedMetrics AS (
  SELECT
    rap.Id AS PostId,
    rap.Title,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    CASE
      WHEN rap.PostTypeId = 1 THEN 'Question'
      WHEN rap.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    wt.Name AS TopVoteType,
    ro.Name AS CloseReason,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rap.Id) AS CommentCount
  FROM RecentActivePosts rap
  LEFT JOIN Votes v ON v.PostId = rap.Id
  LEFT JOIN VoteTypes wt ON wt.Id = 1 -- placeholder to create variety in join
  LEFT JOIN PostHistory ph ON ph.PostId = rap.Id AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes ro ON ro.Id = CAST((ph.Comment) AS int) -- using JSON-like field as an odd cross-join for complexity
)
SELECT
  mp.PostId,
  mp.Title,
  mp.PostKind,
  mp.CreationDate,
  mp.LastActivityDate,
  mp.Score,
  mp.ViewCount,
  mp.CommentCount,
  COALESCE(uimp.DisplayName, 'Unknown') AS LastEditor,
  uimp.TotalViews AS EditorTotalViews,
  mt.TagName AS TopTag,
  mt.PostCount AS TagPostCount,
  mt.AvgScore AS TagAvgScore,
  mt.TotalViews AS TagTotalViews
FROM MixedMetrics mp
LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = mp.PostId)
LEFT JOIN (
  SELECT
    tu.PostId,
    tu.DisplayName
  FROM Posts tu
  LEFT JOIN Users u2 ON u2.Id = tu.OwnerUserId
) uimp ON uimp.PostId = mp.PostId
LEFT JOIN TopTags mt ON TRUE
ORDER BY mp.LastActivityDate DESC, mp.Score DESC
LIMIT 100;