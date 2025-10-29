-- {"query": "5082.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 791}
WITH
RecentPopularQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    AVG(CASE WHEN c.Id IS NOT NULL THEN c.Score END) AS AvgCommentScore
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON p.Id = v.PostId
  LEFT JOIN Comments c ON p.Id = c.PostId
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180' DAY)
  GROUP BY
    p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount,
    p.OwnerUserId, u.DisplayName
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN Tags t ON 1=1
  WHERE p.PostTypeId = 1
    AND LOWER(p.Tags) LIKE '%' || '<' || LOWER(t.TagName) || '>' || '%'
  GROUP BY t.TagName
),
Coalesced AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.OwnerName,
    r.UpVotes,
    r.DownVotes,
    r.AvgCommentScore,
    row_number() OVER (
      ORDER BY (r.UpVotes - r.DownVotes) DESC,
               r.ViewCount DESC,
               r.AvgCommentScore DESC
    ) AS rn
  FROM RecentPopularQuestions r
),
Final AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.Score,
    c.ViewCount,
    c.OwnerUserId,
    c.OwnerName,
    c.UpVotes,
    c.DownVotes,
    c.AvgCommentScore,
    ta.TagPostCount,
    ta.TotalViews,
    ta.AvgScore,
    ((c.UpVotes - c.DownVotes) * 1.0) / NULLIF(c.ViewCount, 0) AS EngagementRatio,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = c.PostId) AS LinkedCount,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = c.PostId AND v2.VoteTypeId = 10) AS DeletionVotes
  FROM Coalesced c
  LEFT JOIN TagActivity ta
    ON LOWER(c.Tags) LIKE '%' || '<' || LOWER(ta.TagName) || '>' || '%'
  WHERE c.rn <= 100
)
SELECT
  PostId,
  Title,
  Tags,
  CreationDate,
  Score,
  ViewCount,
  OwnerUserId,
  OwnerName,
  UpVotes,
  DownVotes,
  AvgCommentScore,
  TagPostCount,
  TotalViews,
  AvgScore,
  EngagementRatio,
  LinkedCount,
  DeletionVotes
FROM Final
ORDER BY EngagementRatio DESC, ViewCount DESC
LIMIT 50;