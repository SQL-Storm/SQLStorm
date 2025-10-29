WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.Body
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
top_tags AS (
  SELECT
    q.TagName,
    COUNT(*) AS QCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName, p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) q
  JOIN Tags t ON LOWER(q.TagName) = LOWER(t.TagName)
  JOIN Posts p ON p.Id = q.Id
  GROUP BY q.TagName
),
complex_derived AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    CASE
      WHEN r.ViewCount > 1000 THEN TRUE
      ELSE FALSE
    END AS IsPopular,
    CASE
      WHEN r.Score >= 5 THEN 'High'
      WHEN r.Score BETWEEN 0 AND 4 THEN 'Medium'
      ELSE 'Low'
    END AS QualityBand,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 3) AS Downvotes
  FROM recent_questions r
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
),
joined AS (
  SELECT
    c.PostId,
    c.Title,
    c.CreationDate,
    c.OwnerUserId,
    c.DisplayName,
    c.Reputation,
    c.IsPopular,
    c.QualityBand,
    c.CommentCount,
    c.Upvotes,
    c.Downvotes,
    ll.DisplayName AS LastEditor,
    p.Tags AS TagsRaw,
    p.ViewCount
  FROM complex_derived c
  LEFT JOIN Posts p ON p.Id = c.PostId
  LEFT JOIN Users ll ON ll.Id = p.LastEditorUserId
  ORDER BY c.CreationDate DESC
  LIMIT 200
),
windowed AS (
  SELECT
    j.PostId,
    j.Title,
    j.CreationDate,
    j.OwnerUserId,
    j.DisplayName,
    j.Reputation,
    j.IsPopular,
    j.QualityBand,
    j.CommentCount,
    j.Upvotes,
    j.Downvotes,
    j.LastEditor,
    j.TagsRaw,
    j.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY j.QualityBand ORDER BY j.Reputation DESC, j.ViewCount DESC) AS rn_band
  FROM joined j
)
SELECT
  w.PostId,
  w.Title,
  w.CreationDate,
  w.OwnerUserId,
  w.DisplayName,
  w.Reputation,
  w.IsPopular,
  w.QualityBand,
  w.CommentCount,
  w.Upvotes,
  w.Downvotes,
  w.LastEditor,
  w.TagsRaw,
  w.ViewCount
FROM windowed w
WHERE w.rn_band <= 3
  OR w.QualityBand = 'High'
ORDER BY w.QualityBand DESC, w.Reputation DESC, w.ViewCount DESC, w.CreationDate DESC;