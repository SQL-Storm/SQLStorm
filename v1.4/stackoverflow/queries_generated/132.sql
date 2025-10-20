-- {"query": "132.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2095} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  COALESCE(u.DisplayName, p.OwnerDisplayName) AS Owner,
  u.Reputation,
  p.Score,
  p.ViewCount,
  COUNT(DISTINCT c.Id) AS CommentCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  (SELECT array_agg(Text ORDER BY CreationDate DESC) FROM Comments cmt WHERE cmt.PostId = p.Id LIMIT 5) AS RecentComments,
  COALESCE(p.LastActivityDate, p.CreationDate) AS ActivityDate,
  SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2) AS RawTags,
  ARRAY_LENGTH(string_to_array(SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1) AS TagCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Comments c ON c.PostId = p.Id
WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  COALESCE(u.DisplayName, p.OwnerDisplayName),
  u.Reputation,
  p.Score,
  p.ViewCount,
  p.LastActivityDate,
  p.OwnerDisplayName,
  p.LastEditorDisplayName,
  p.LastEditDate,
  p.Tags;