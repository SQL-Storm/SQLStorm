-- {"query": "48007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 592} 
WITH RankedPostHistory AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId,
    ph.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) -- Considering initial and edit history types
),
PostEdits AS (
  SELECT
    rph.PostId,
    COUNT(CASE WHEN rph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS edit_count,
    MAX(CASE WHEN rph.PostHistoryTypeId IN (4, 5, 6) THEN rph.CreationDate ELSE NULL END) AS last_edit_date
  FROM RankedPostHistory rph
  WHERE rph.rn = 1 -- Focusing on the most recent revision for each post
  GROUP BY rph.PostId
)
SELECT
  p.Id AS post_id,
  pt.Name AS post_type,
  p.Title AS post_title,
  u.DisplayName AS owner_display_name,
  p.CreationDate AS post_creation_date,
  p.Score AS post_score,
  p.ViewCount AS post_view_count,
  pe.edit_count,
  pe.last_edit_date,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS comment_count,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS outgoing_link_count,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id) AS incoming_link_count,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS upvote_count,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS downvote_count,
  p.FavoriteCount AS favorite_count,
  p.AnswerCount AS answer_count,
  p.ClosedDate AS closed_date
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostEdits pe ON p.Id = pe.PostId
WHERE p.CreationDate >= NOW() - INTERVAL '30 day' -- Focusing on recent posts
ORDER BY p.CreationDate DESC
LIMIT 1000;