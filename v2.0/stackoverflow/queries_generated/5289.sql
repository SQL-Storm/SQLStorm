-- {"query": "5289.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 928} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    p.AnswerCount,
    p.CommentCount,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn_per_user
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 -- Questions
    AND p.IsDeleted IS NULL
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
    AND p.ViewCount > 0
),
PopularOwners AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    SUM(COALESCE(r.UpVotes,0) - COALESCE(r.DownVotes,0)) AS NetScore,
    COUNT(*) AS QuestionCount,
    MAX(r.CreationDate) AS LastActive
  FROM RecentTopPosts r
  JOIN Users u ON u.Id = r.OwnerUserId
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN UNNEST(string_to_array(REPLACE(p.Tags, '<',''), '>')) AS t(TagName)
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
CrossJoinStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    t.TagName,
    u.Reputation AS OwnerRep,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(CASE WHEN vh.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Tags tg ON tg.ExcerptPostId = p.Id OR tg.WikiPostId = p.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN PostHistory vh ON vh.PostId = p.Id
  LEFT JOIN UNNEST(string_to_array(REPLACE(p.Tags, '<',''), '>')) AS t(TagName) ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, t.TagName, u.Reputation
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.ViewCount,
  c.Score,
  c.OwnerUserId,
  c.TagName,
  c.OwnerRep,
  c.UpVotes,
  c.DownVotes,
  c.WasClosed,
  ro.Reputation AS TopRaterRep,
  ro.DisplayName AS TopRater
FROM CrossJoinStats c
LEFT JOIN (
  SELECT
    DISTINCT ON (p.OwnerUserId) p.OwnerUserId,
    u.Reputation,
    u.DisplayName
  FROM Posts p
  JOIN Votes v ON v.PostId = p.Id
  JOIN Users u ON u.Id = p.OwnerUserId
  ORDER BY p.OwnerUserId, v.CreationDate DESC
) ro ON ro.OwnerUserId = c.OwnerUserId
WHERE c.UpVotes - c.DownVotes > 0
ORDER BY c.CreationDate DESC, c.ViewCount DESC
LIMIT 100;