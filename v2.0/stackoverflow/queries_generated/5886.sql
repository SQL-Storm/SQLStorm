-- {"query": "5886.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 784} 
WITH
  recent_users AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate
    FROM Users u
    WHERE u.Reputation > 1000
  ),
  top_posts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.OwnerUserId,
      p.Tags,
      p.PostTypeId,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.LastActivityDate
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions
      AND p.CreationDate >= (CURRENT_DATE - INTERVAL '180 days')
      AND p.ViewCount > 0
  ),
  last_edits AS (
    SELECT
      ph.PostId,
      ph.Id AS RevisionId,
      ph.CreationDate AS RevisionDate,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.UserDisplayName,
      ph.Comment
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,16,50) -- some common edit/notice types
  ),
  linked_counts AS (
    SELECT
      pl.PostId,
      COUNT(*) AS LinkedCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1 -- Linked
    GROUP BY pl.PostId
  ),
  badge_counts AS (
    SELECT
      b.UserId,
      COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date >= (CURRENT_DATE - INTERVAL '365 days')
    GROUP BY b.UserId
  ),
  vote_agg AS (
    SELECT
      v.PostId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts,
      SUM(CASE WHEN v.VoteTypeId = 9 THEN 1 ELSE 0 END) AS BountyCloses
    FROM Votes v
    GROUP BY v.PostId
  )
SELECT
  rp.DisplayName AS AskedBy,
  rp.Reputation AS AskedByRep,
  rp.LastAccessDate AS AskedByLastAccess,
  tp.PostId,
  tp.Title,
  tp.CreationDate AS QuestionDate,
  tp.Score,
  tp.ViewCount,
  tc.LinkedCount,
  bc.BadgeCount,
  va.UpVotes,
  va.DownVotes,
  va.BountyStarts,
  va.BountyCloses,
  ne.RevisionDate AS LastEditDate,
  ne.PostHistoryTypeId AS LastEditType,
  ne.UserDisplayName AS LastEditorName,
  ne.Comment AS EditComment,
  to_char(tp.LastActivityDate, 'YYYY-MM-DD HH24:MI:SS') AS LastActivity,
  UNNEST(string_to_array(tp.Tags, '<>')) AS Tag
FROM top_posts tp
LEFT JOIN Users rp ON tp.OwnerUserId = rp.Id
LEFT JOIN linked_counts tc ON tp.Id = tc.PostId
LEFT JOIN badge_counts bc ON rp.Id = bc.UserId
LEFT JOIN vote_agg va ON tp.Id = va.PostId
LEFT JOIN last_edits ne ON tp.Id = ne.PostId
WHERE
  (rp.Reputation > 0 OR rp.Id IS NULL)
  AND tp.Tags IS NOT NULL
ORDER BY
  tp.CreationDate DESC,
  va.UpVotes DESC
LIMIT 100;