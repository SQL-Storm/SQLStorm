-- {"query": "215.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 13132} 
WITH
TagNames AS (
  SELECT p.Id AS PostId,
         COALESCE((SELECT string_agg(t2.TagName, ',')
                   FROM unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
                   JOIN Tags t2 ON t2.TagName = tag
                  ), '') AS TagList
  FROM Posts p
  WHERE p.PostTypeId = 1
),
UpDown AS (
  SELECT p.Id AS PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id
),
CommentCounts AS (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
),
LastClose AS (
  SELECT p.Id AS PostId,
         cr.Name AS CloseReason
  FROM Posts p
  LEFT JOIN LATERAL (
     SELECT ph.Comment
     FROM PostHistory ph
     WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
     ORDER BY ph.CreationDate DESC
     LIMIT 1
  ) ph ON true
  LEFT JOIN CloseReasonTypes cr ON cr.Id = CASE WHEN ph.Comment IS NULL THEN NULL ELSE CAST(ph.Comment AS int) END
),
Main AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    (SELECT Name FROM PostTypes pt WHERE pt.Id = p.PostTypeId) AS PostTypeName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    COALESCE(tn.TagList, '') AS TagList,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    p.LastEditorDisplayName,
    p.LastEditDate,
    COALESCE(cc.CommentCount, 0) AS CommentCount,
    COALESCE(ud.UpVotes, 0) AS UpVotes,
    COALESCE(ud.DownVotes, 0) AS DownVotes,
    (CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN true ELSE false END) AS HasAcceptedAnswer,
    lc.CloseReason,
    COALESCE(ob.LastBadgeName, '') AS LastBadgeName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS ActivityRank
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN UpDown ud ON ud.PostId = p.Id
  LEFT JOIN CommentCounts cc ON cc.PostId = p.Id
  LEFT JOIN LastClose lc ON lc.PostId = p.Id
  LEFT JOIN TagNames tn ON tn.PostId = p.Id
  LEFT JOIN LATERAL (
     SELECT badge.Name AS LastBadgeName
     FROM Badges badge
     WHERE badge.UserId = p.OwnerUserId
     ORDER BY badge.Date DESC
     LIMIT 1
  ) ob ON true
)
SELECT
  PostId,
  Title,
  PostTypeName,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  TagList,
  OwnerDisplayName,
  OwnerReputation,
  LastEditorDisplayName,
  LastEditDate,
  CommentCount,
  UpVotes,
  DownVotes,
  HasAcceptedAnswer,
  CloseReason,
  LastBadgeName,
  ActivityRank
FROM Main
WHERE PostTypeName = 'Question' AND LastActivityDate > current_timestamp - interval '365 days'
UNION ALL
SELECT
  PostId,
  Title,
  PostTypeName,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  TagList,
  OwnerDisplayName,
  OwnerReputation,
  LastEditorDisplayName,
  LastEditDate,
  CommentCount,
  UpVotes,
  DownVotes,
  HasAcceptedAnswer,
  CloseReason,
  LastBadgeName,
  ActivityRank
FROM Main
WHERE PostTypeName IN ('TagWikiExcerpt', 'TagWiki') AND LastActivityDate > current_timestamp - interval '180 days'
ORDER BY LastActivityDate DESC
LIMIT 400;