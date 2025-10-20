-- {"query": "390.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 16495} 
WITH ScoreTop AS (
  SELECT
    p.Id AS PostId,
    p.Title AS Title,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    p.CreationDate AS CreationDate,
    p.ViewCount AS ViewCount,
    p.Score AS Score,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(v.TotalVotes, 0) AS TotalVotes,
    COALESCE(cnc.CommentCount, 0) AS CommentCount,
    p.LastEditDate AS LastEditDate,
    COALESCE(tag_info.TagList, '') AS TagList,
    pt.Name AS PostTypeName,
    COALESCE(lh.LastHistoryName, '') AS LastHistoryName,
    'ScoreTop' AS Source
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN (
     SELECT PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
            SUM(CASE WHEN VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
     FROM Votes
     GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN (
     SELECT PostId, COUNT(*) AS CommentCount
     FROM Comments
     GROUP BY PostId
  ) cnc ON cnc.PostId = p.Id
  LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
  LEFT JOIN LATERAL (
     SELECT string_agg(TagName, ',') AS TagList
     FROM regexp_split_to_table(coalesce(substr(p.Tags, 2, greatest(length(p.Tags) - 2, 0)), ''), '><') AS t(TagName)
  ) tag_info ON TRUE
  LEFT JOIN LATERAL (
     SELECT pht.Name AS LastHistoryName
     FROM PostHistory ph
     JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
     WHERE ph.PostId = p.Id
     ORDER BY ph.CreationDate DESC
     LIMIT 1
  ) lh ON TRUE
  WHERE p.CreationDate >= now() - interval '90 days'
  LIMIT 100
),
ScoreView AS (
  SELECT
    p.Id AS PostId,
    p.Title AS Title,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    p.CreationDate AS CreationDate,
    p.ViewCount AS ViewCount,
    p.Score AS Score,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(v.TotalVotes, 0) AS TotalVotes,
    COALESCE(cnc.CommentCount, 0) AS CommentCount,
    p.LastEditDate AS LastEditDate,
    COALESCE(tag_info.TagList, '') AS TagList,
    pt.Name AS PostTypeName,
    COALESCE(lh.LastHistoryName, '') AS LastHistoryName,
    'ViewTop' AS Source
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN (
     SELECT PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
            SUM(CASE WHEN VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
     FROM Votes
     GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN (
     SELECT PostId, COUNT(*) AS CommentCount
     FROM Comments
     GROUP BY PostId
  ) cnc ON cnc.PostId = p.Id
  LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
  LEFT JOIN LATERAL (
     SELECT string_agg(TagName, ',') AS TagList
     FROM regexp_split_to_table(coalesce(substr(p.Tags, 2, greatest(length(p.Tags) - 2, 0)), ''), '><') AS t(TagName)
  ) tag_info ON TRUE
  LEFT JOIN LATERAL (
     SELECT pht.Name AS LastHistoryName
     FROM PostHistory ph
     JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
     WHERE ph.PostId = p.Id
     ORDER BY ph.CreationDate DESC
     LIMIT 1
  ) lh ON TRUE
  WHERE p.CreationDate >= now() - interval '90 days'
  LIMIT 100
)
SELECT * FROM ScoreTop
UNION ALL
SELECT * FROM ScoreView;