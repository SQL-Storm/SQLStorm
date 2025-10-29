-- {"query": "5800.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 882}
WITH RECURSIVE
TagTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.ViewCount) AS AvgViews,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS MostRecentActivity
  FROM Posts p
  JOIN LATERAL unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName) ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
PostsWithRecentActivity AS (
  SELECT
    p.PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    pg.PrevBestTag,
    CASE
      WHEN p.ViewCount > 1000 THEN true
      ELSE false
    END AS IsPopular,
    DENSE_RANK() OVER (ORDER BY p.LastActivityDate DESC) AS recency_rank
  FROM TagTopPosts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      pt.Id AS PostId,
      MAX(t.TagName) AS PrevBestTag
    FROM Posts pt
    JOIN LATERAL unnest(string_to_array(substr(pt.Tags, 2, length(pt.Tags)-2), '><')) AS t(TagName) ON true
    WHERE pt.PostTypeId = 1
    GROUP BY pt.Id
  ) pg ON pg.PostId = p.PostId
),
FinalSet AS (
  SELECT
    pr.PostId,
    pr.Title,
    pr.OwnerUserId,
    pr.OwnerName,
    pr.Tags,
    pr.ViewCount,
    pr.Score,
    pr.CreationDate,
    pr.LastActivityDate,
    pr.IsPopular,
    pr.PrevBestTag,
    ts.TagName
  FROM PostsWithRecentActivity pr
  CROSS JOIN LATERAL (
    SELECT t.TagName
    FROM unnest(string_to_array(substr(pr.Tags, 2, length(pr.Tags)-2), '><')) AS t(TagName)
    ORDER BY t.TagName
    LIMIT 1
  ) AS ts
  LEFT JOIN TagStats ts2 ON ts2.TagName = ts.TagName
)
SELECT
  f.PostId,
  f.Title,
  f.OwnerUserId,
  f.OwnerName,
  f.ViewCount,
  f.Score,
  f.CreationDate,
  f.LastActivityDate,
  f.IsPopular,
  f.PrevBestTag,
  f.TagName,
  vh.SumUpVotes AS UpVotes,
  vh.SumDownVotes AS DownVotes,
  c.CommentCount,
  w.TotalBounties AS BountyTotal
FROM FinalSet f
LEFT JOIN (
  SELECT V.PostId, 
         SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS SumUpVotes,
         SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS SumDownVotes
  FROM Votes V
  GROUP BY V.PostId
) vh ON vh.PostId = f.PostId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
) c ON c.PostId = f.PostId
LEFT JOIN (
  SELECT PostId, SUM(BountyAmount) AS TotalBounties
  FROM Votes
  WHERE VoteTypeId = 8 OR VoteTypeId = 9
  GROUP BY PostId
) w ON w.PostId = f.PostId
ORDER BY f.LastActivityDate DESC
LIMIT 100;