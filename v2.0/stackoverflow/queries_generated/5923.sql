-- {"query": "5923.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 790} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    -- flag for posts with no owner (deleted users) and no last editor
    CASE WHEN p.OwnerUserId IS NULL THEN 1 ELSE 0 END AS IsOwnerMissing
  FROM Posts p
  WHERE p.CreationDate >= current_timestamp - interval '180 days'
),
TopQuestions AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.ViewCount,
    rp.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY (CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END)
      ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.LastActivityDate DESC
    ) AS rn
  FROM RecentActivePosts rp
  WHERE rp.PostTypeId = 1
),
TagPopularity AS (
  SELECT
    unnest(string_to_array(substr(rp.Tags, 2, length(rp.Tags)-2), '><')) AS TagName,
    rp.PostId
  FROM TopQuestions rp
  WHERE rp.rn = 1
),
TagScore AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    SUM(p.Score) AS TotalScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM TagPopularity t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
CommunityVote AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    u.DisplayName,
    u.Reputation
  FROM Votes v
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE v.VoteTypeId IN (2, 3) -- UpMod / DownMod
),
RecentCommentary AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserId,
    c.CreationDate,
    c.Text,
    u.DisplayName AS Commenter
  FROM Comments c
  LEFT JOIN Users u ON c.UserId = u.Id
  WHERE c.CreationDate >= current_timestamp - interval '7 days'
),
PostLinksAgg AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.LinkTypeId IN (1, 3)
),
ExposedSummary AS (
  SELECT
    q.PostId,
    q.Title,
    q.Score,
    q.ViewCount,
    q.LastActivityDate,
    tc.TagName,
    ts.TotalScore,
    ts.PostCount,
    ARRAY_AGG(DISTINCT lta.LinkTypeName) AS LinkTypes
  FROM TopQuestions q
  LEFT JOIN TagPopularity tp ON tp.PostId = q.PostId
  LEFT JOIN TagScore ts ON ts.TagName = tp.TagName
  LEFT JOIN PostLinksAgg lta ON lta.PostId = q.PostId
  GROUP BY q.PostId, q.Title, q.Score, q.ViewCount, q.LastActivityDate, tc.TagName, ts.TotalScore, ts.PostCount
)
SELECT
  es.PostId,
  es.Title,
  es.Score,
  es.ViewCount,
  es.LastActivityDate,
  es.TagName,
  es.TotalScore,
  es.PostCount,
  es.LinkTypes
FROM ExposedSummary es
ORDER BY es.LastActivityDate DESC
LIMIT 100;