WITH
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    COALESCE(a.AvgUserRep, 0) AS AvgOwnerRep
  FROM Posts p
  LEFT JOIN (
    SELECT
      u.Id,
      AVG(u.Reputation) AS AvgUserRep
    FROM Users u
    GROUP BY u.Id
  ) a ON a.Id = p.OwnerUserId
),
tag_stats AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  JOIN LATERAL (
    SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
  ) t ON p.PostTypeId = 1
  WHERE p.ClosedDate IS NULL
  GROUP BY t.TagName
),
complex_filter AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.OwnerUserId,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.PostTypeId,
    rp.AvgOwnerRep,
    ROW_NUMBER() OVER (
      PARTITION BY rp.OwnerUserId
      ORDER BY rp.LastActivityDate DESC, rp.Score DESC
    ) AS rn_by_owner
  FROM recent_activity rp
  WHERE rp.Score > 0
    AND (rp.ViewCount IS NULL OR rp.ViewCount >= 0)
),
cross_joined AS (
  SELECT
    cf.PostId,
    cf.Title,
    cf.CreationDate,
    cf.LastActivityDate,
    cf.OwnerUserId,
    cf.Score,
    cf.ViewCount,
    cf.Tags,
    cf.PostTypeId,
    cf.AvgOwnerRep,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cf.PostId) AS CommentCount,
    (SELECT STRING_AGG(vt.Name, ',') FROM Votes v JOIN VoteTypes vt ON v.VoteTypeId = vt.Id WHERE v.PostId = cf.PostId) AS VoteTypesApplied
  FROM complex_filter cf
  WHERE cf.rn_by_owner = 1
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  u.DisplayName AS OwnerDisplayName,
  c.Score,
  c.ViewCount,
  c.Tags,
  c.PostTypeId,
  c.AvgOwnerRep,
  co.Name AS CloseReason,
  cl.LinkCount,
  tt.TagName AS TopTag,
  sc.TotalViews AS SumViewsForTag,
  ROW_NUMBER() OVER (ORDER BY c.LastActivityDate DESC) AS RowSeq
FROM cross_joined c
LEFT JOIN Users u ON c.OwnerUserId = u.Id
LEFT JOIN PostHistory ph ON ph.PostId = c.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN CloseReasonTypes co ON CAST(SUBSTRING(ph.Comment FROM 1 FOR 3) AS INTEGER) = co.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS LinkCount
  FROM PostLinks
  GROUP BY PostId
) cl ON cl.PostId = c.PostId
LEFT JOIN LATERAL (
  SELECT UNNEST(string_to_array(c.Tags, '<>')) AS TagName
) tt ON true
LEFT JOIN (
  SELECT t.TagName, SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  JOIN LATERAL (
    SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
  ) t ON true
  GROUP BY t.TagName
) sc ON sc.TagName = tt.TagName
LEFT JOIN tag_stats tgs ON tgs.TagName = tt.TagName
WHERE c.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days')
GROUP BY
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  u.DisplayName,
  c.Score,
  c.ViewCount,
  c.Tags,
  c.PostTypeId,
  c.AvgOwnerRep,
  co.Name,
  cl.LinkCount,
  tt.TagName,
  sc.TotalViews,
  tgs.TagName
ORDER BY c.LastActivityDate DESC, c.Score DESC
LIMIT 100;