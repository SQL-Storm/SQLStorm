-- {"query": "14057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 946}
WITH cte_post_history AS (
  SELECT 
    p.Id AS post_id, 
    p.PostTypeId, 
    p.CreationDate AS post_creation_date, 
    p.LastActivityDate,
    p.ClosedDate,
    ph.Id AS history_id,
    ph.PostHistoryTypeId,
    ph.CreationDate AS history_date,
    ph.UserId AS editor_id,
    ph.UserDisplayName AS editor_name,
    CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) THEN ph.Text ELSE NULL END AS vote_details,
    CASE WHEN ph.PostHistoryTypeId IN (33, 34) THEN ph.Text ELSE NULL END AS post_notice_id
  FROM Posts p
  JOIN PostHistory ph ON p.Id = ph.PostId
),
cte_post_links AS (
  SELECT
    pl.Id AS link_id,
    pl.CreationDate AS link_date,
    pl.PostId AS post_id,
    pl.RelatedPostId AS related_post_id,
    lt.Name AS link_type
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
cte_post_votes AS (
  SELECT
    v.Id AS vote_id,
    v.PostId AS post_id,
    v.VoteTypeId,
    v.UserId AS voter_id,
    v.CreationDate AS vote_date,
    vt.Name AS vote_type,
    v.BountyAmount
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
)
SELECT
  p.Id AS post_id,
  p.PostTypeId,
  p.CreationDate AS post_creation_date,
  p.LastActivityDate,
  p.ClosedDate,
  p.AcceptedAnswerId,
  p.ParentId,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.OwnerUserId,
  p.OwnerDisplayName,
  p.LastEditorUserId,
  p.LastEditorDisplayName,
  p.Title,
  p.Tags,
  COALESCE(u.DisplayName, p.OwnerDisplayName) AS post_author,
  COALESCE(u2.DisplayName, p.LastEditorDisplayName) AS last_editor,
  cph.history_id,
  cph.PostHistoryTypeId,
  cph.history_date,
  cph.editor_id,
  cph.editor_name,
  cph.vote_details,
  cph.post_notice_id,
  cpl.link_id,
  cpl.link_date,
  cpl.related_post_id,
  cpl.link_type,
  cpv.vote_id,
  cpv.VoteTypeId,
  cpv.voter_id,
  cpv.vote_date,
  cpv.vote_type,
  cpv.BountyAmount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Users u2 ON p.LastEditorUserId = u2.Id
LEFT JOIN cte_post_history cph ON p.Id = cph.post_id
LEFT JOIN cte_post_links cpl ON p.Id = cpl.post_id
LEFT JOIN cte_post_votes cpv ON p.Id = cpv.post_id
ORDER BY p.Id, cph.history_date, cpl.link_date, cpv.vote_date;
