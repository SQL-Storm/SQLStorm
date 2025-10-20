-- {"query": "48.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 736} 
WITH
  recent_closed AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.LastActivityDate,
      p.Score,
      p.ViewCount,
      p.OwnerUserId,
      p.Tags,
      ct.ClosedDate,
      ph.Text AS CloseReasonComment,
      ph.CreationDate AS HistoryDate
    FROM Posts p
    LEFT JOIN (SELECT PostId, MAX(CreationDate) AS LastCloseDate
               FROM PostHistory
               WHERE PostHistoryTypeId = 10
               GROUP BY PostId) h ON p.Id = h.PostId
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
      AND ph.PostHistoryTypeId = 10
      AND ph.CreationDate = h.LastCloseDate
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(SUBSTRING(ph.Comment, 1, 3) AS int)
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NOT NULL
  ),
  top_voters AS (
    SELECT
      v.PostId,
      v.VoteTypeId,
      v.UserId,
      v.CreationDate,
      u.DisplayName,
      ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    JOIN Users u ON u.Id = v.UserId
    WHERE v.VoteTypeId IN (2, 3) -- UpMod / DownMod
  ),
  tag_agg AS (
    SELECT
      p.Id AS PostId,
      t.TagName,
      COUNT(*) AS TagCount
    FROM Posts p
    CROSS APPLY (SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><'))) AS t(TagName)
    GROUP BY p.Id, t.TagName
  ),
  author_stats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(*) AS PostsCreated,
      SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositivePosts
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
  )
SELECT
  rp.PostId,
  rp.Title,
  rp.CreationDate AS PostCreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.OwnerUserId,
  au.DisplayName AS OwnerDisplayName,
  au.Reputation AS OwnerReputation,
  rp.Tags,
  rp.ClosedDate,
  rp.CloseReasonComment,
  rp.HistoryDate,
  tv.rn AS IsLatestCloseVotePosition,
  tv.VoteTypeId AS LastCloseVoteType,
  ta.TagName,
  ta.TagCount,
  asr.DisplayName AS LastEditorName,
  asr.Reputation AS LastEditorReputation,
  as_user.DisplayName AS CommunityOwner
FROM recent_closed rp
LEFT JOIN top_voters tv ON tv.PostId = rp.PostId AND tv.rn = 1
LEFT JOIN tag_agg ta ON ta.PostId = rp.PostId
LEFT JOIN author_stats au ON au.UserId = rp.OwnerUserId
LEFT JOIN Users asr ON asr.Id = rp.OwnerUserId
LEFT JOIN Users as_user ON as_user.Id = rp.OwnerUserId
ORDER BY rp.LastActivityDate DESC
LIMIT 100;