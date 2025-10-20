-- {"query": "341.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 25229} 
WITH
UnionedPosts AS (
  -- Include some workload by combining questions and answers
  (SELECT p.Id, p.Title, p.Tags, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount
   FROM Posts p
   WHERE p.PostTypeId = 1
     AND p.LastActivityDate > NOW() - INTERVAL '90 days')
  UNION ALL
  (SELECT p.Id, p.Title, p.Tags, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount
   FROM Posts p
   WHERE p.PostTypeId = 2
     AND p.LastActivityDate > NOW() - INTERVAL '90 days')
),
OrderedUnion AS (
  SELECT up.*,
         ROW_NUMBER() OVER (PARTITION BY up.PostTypeId ORDER BY up.LastActivityDate DESC, up.Score DESC) AS TypeRank
  FROM UnionedPosts up
),
TagList AS (
  SELECT ou.Id AS PostId,
         t.TagName
  FROM OrderedUnion ou
  CROSS JOIN LATERAL unnest(string_to_array(substring(ou.Tags, 2, length(ou.Tags) - 2), '><')) AS t(TagName)
),
TagStats AS (
  SELECT TagName, COUNT(*) AS TagPostCount
  FROM TagList
  GROUP BY TagName
  ORDER BY TagPostCount DESC
  LIMIT 50
),
PostComments AS (
  SELECT p.Id AS PostId, COUNT(*) AS CommentCount
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.Id
),
PostVotes AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  GROUP BY v.PostId
),
LastEdits AS (
  SELECT DISTINCT ON (ph.PostId) ph.PostId,
         ph.RevisionGUID,
         ph.UserDisplayName AS LastEditorDisplayName,
         ph.CreationDate AS EditDate
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,16,10)
  ORDER BY ph.PostId, ph.CreationDate DESC
),
CloseInfo AS (
  SELECT ph.PostId,
         cr.Name AS CloseReasonName,
         ph.CreationDate AS CloseDate
  FROM PostHistory ph
  LEFT JOIN CloseReasonTypes cr ON cr.Id = CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^[0-9]+$'
                                              THEN CAST(ph.Comment AS int) ELSE NULL END
  WHERE ph.PostHistoryTypeId = 10
)
SELECT
  ou.Id AS PostId,
  ou.Title,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  ou.ViewCount,
  ou.Score,
  ou.CreationDate,
  ou.LastActivityDate,
  COALESCE(pc.CommentCount, 0) AS CommentCount,
  COALESCE(pv.UpVotes, 0) AS UpVotes,
  COALESCE(pv.DownVotes, 0) AS DownVotes,
  COALESCE(pv.UpVotes, 0) - COALESCE(pv.DownVotes, 0) AS NetVotes,
  le.RevisionGUID AS LastEditRevision,
  le.LastEditorDisplayName AS LastEditorDisplayName,
  le.EditDate,
  ci.CloseReasonName AS CloseReasonName,
  ci.CloseDate AS CloseDate,
  COALESCE((SELECT STRING_AGG(tl.TagName, ',') FROM TagList tl WHERE tl.PostId = ou.Id), '') AS TagsForPost,
  COALESCE((SELECT json_agg(json_build_object('TagName', ts.TagName, 'TagPostCount', ts.TagPostCount)) FROM TagStats ts), '[]') AS TopTagsSummary,
  ou.TypeRank
FROM OrderedUnion ou
JOIN Users u ON ou.OwnerUserId = u.Id
JOIN PostTypes pt ON pt.Id = ou.PostTypeId
LEFT JOIN PostComments pc ON pc.PostId = ou.Id
LEFT JOIN PostVotes pv ON pv.PostId = ou.Id
LEFT JOIN LastEdits le ON le.PostId = ou.Id
LEFT JOIN CloseInfo ci ON ci.PostId = ou.Id
ORDER BY ou.TypeRank, ou.LastActivityDate DESC
LIMIT 200;