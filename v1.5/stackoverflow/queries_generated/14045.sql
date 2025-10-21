-- {"query": "14045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 107410, "output_tokens": 45090} 
WITH cte AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostType,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      ELSE 'Open'
    END AS PostStatus,
    CASE
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      ELSE 'Not Community Owned'
    END AS CommunityOwned,
    COALESCE(ph.Comment, '') AS CloseReason,
    COALESCE(ph.Text, '') AS PostHistoryText,
    COALESCE(l.Name, '') AS LinkType,
    COALESCE(vt.Name, '') AS VoteType,
    COALESCE(pht.Name, '') AS PostHistoryType,
    COALESCE(cr.Name, '') AS CloseReasonType
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    AND ph.PostHistoryTypeId = 10 -- Post Closed
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN LinkTypes l ON pl.LinkTypeId = l.Id
  LEFT JOIN Votes v ON p.Id = v.PostId
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  LEFT JOIN CloseReasonTypes cr ON CAST(ph.Comment AS INT) = cr.Id
)
SELECT
  PostId,
  Title,
  Body,
  Tags,
  OwnerUserId,
  OwnerDisplayName,
  Reputation,
  UserViews,
  UserUpVotes,
  UserDownVotes,
  PostType,
  PostStatus,
  CommunityOwned,
  CloseReason,
  PostHistoryText,
  LinkType,
  VoteType,
  PostHistoryType,
  CloseReasonType
FROM cte
WHERE PostType = 'Question'
  AND PostStatus = 'Closed'
  AND CommunityOwned = 'Not Community Owned'
ORDER BY Reputation DESC, UserViews DESC, UserUpVotes DESC, UserDownVotes DESC
LIMIT 100;