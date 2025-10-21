-- {"query": "268.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6786} 
WITH
PostBase AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.OwnerUserId,
         COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
         p.PostTypeId,
         p.CreationDate,
         p.LastActivityDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         p.AcceptedAnswerId,
         p.ParentId,
         p.LastEditorUserId,
         p.LastEditorDisplayName
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
),
CommentAgg AS (
  SELECT p.Id AS PostId,
         COUNT(c.Id) AS CommentCount
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.Id
),
VoteAgg AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  GROUP BY v.PostId
),
TagCount AS (
  SELECT p.Id AS PostId,
         CASE WHEN p.Tags IS NULL THEN 0
              ELSE 0
                   + array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1)
         END AS TagCount
  FROM Posts p
),
LastEditor AS (
  SELECT Id,
         LastEditorUserId,
         LastEditorDisplayName
  FROM Posts
),
Combined AS (
  SELECT pb.PostId,
         pb.Title,
         pb.OwnerUserId,
         pb.OwnerName,
         pb.PostTypeId,
         pb.CreationDate,
         pb.LastActivityDate,
         pb.Score,
         pb.ViewCount,
         COALESCE(ca.CommentCount, 0) AS CommentCount,
         COALESCE(va.UpVotes, 0) AS UpVotes,
         COALESCE(va.DownVotes, 0) AS DownVotes,
         COALESCE(tc.TagCount, 0) AS TagCount,
         COALESCE(le.LastEditorUserId, pb.OwnerUserId) AS LastEditorUserId,
         COALESCE(le.LastEditorDisplayName, pb.OwnerName) AS LastEditorName
  FROM PostBase pb
  LEFT JOIN CommentAgg ca ON ca.PostId = pb.PostId
  LEFT JOIN VoteAgg va ON va.PostId = pb.PostId
  LEFT JOIN TagCount tc ON tc.PostId = pb.PostId
  LEFT JOIN LastEditor le ON le.Id = pb.PostId
),
Ranked AS (
  SELECT c.*,
         ROW_NUMBER() OVER (PARTITION BY c.OwnerUserId ORDER BY c.Score DESC, c.LastActivityDate DESC) AS rk
  FROM Combined c
)
SELECT *
FROM (
  SELECT PostId,
         Title,
         OwnerName,
         Score,
         ViewCount,
         CommentCount,
         UpVotes,
         DownVotes,
         TagCount,
         LastEditorName,
         LastActivityDate,
         'A' AS Source
  FROM Ranked
  WHERE Score > 50
    AND LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
  UNION ALL
  SELECT PostId,
         Title,
         OwnerName,
         Score,
         ViewCount,
         CommentCount,
         UpVotes,
         DownVotes,
         TagCount,
         LastEditorName,
         LastActivityDate,
         'B' AS Source
  FROM Ranked
  WHERE TagCount >= 4
) AS s
ORDER BY Score DESC, LastActivityDate DESC
LIMIT 200;