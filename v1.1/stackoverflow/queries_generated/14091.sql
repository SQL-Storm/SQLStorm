-- {"query": "14091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 214820, "output_tokens": 92571} 
WITH cte AS (
  SELECT 
    p.Id, 
    p.PostTypeId, 
    p.AcceptedAnswerId,
    p.ParentId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    CASE WHEN p.PostTypeId = 1 THEN string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') ELSE NULL END AS question_tags,
    CASE WHEN p.PostTypeId = 2 THEN (
      SELECT 
        string_to_array(substring(pt.Tags, 2, length(pt.Tags)-2), '><')
      FROM Posts pt 
      WHERE pt.Id = p.ParentId
    ) ELSE NULL END AS parent_question_tags,
    CASE WHEN p.OwnerUserId IS NOT NULL THEN 
      (
        SELECT 
          COALESCE(SUM(v.UpVotes), 0) - COALESCE(SUM(v.DownVotes), 0)
        FROM Users u
        LEFT JOIN Votes v ON u.Id = v.UserId
        WHERE u.Id = p.OwnerUserId
      )
    ELSE 0 END AS owner_net_votes,
    CASE WHEN p.LastEditorUserId IS NOT NULL THEN
      (
        SELECT 
          COALESCE(SUM(v.UpVotes), 0) - COALESCE(SUM(v.DownVotes), 0)
        FROM Users u
        LEFT JOIN Votes v ON u.Id = v.UserId
        WHERE u.Id = p.LastEditorUserId  
      )
    ELSE 0 END AS last_editor_net_votes
  FROM Posts p
),
post_history AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Text,
    CASE WHEN ph.PostHistoryTypeId IN (10, 33, 34) THEN CAST(ph.Comment AS INT) ELSE NULL END AS close_reason_id,
    CASE WHEN ph.PostHistoryTypeId IN (33, 34) THEN CAST(ph.Comment AS INT) ELSE NULL END AS post_notice_id
  FROM PostHistory ph
),
post_links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1, 3)
)
SELECT
  cte.Id,
  cte.PostTypeId,
  cte.AcceptedAnswerId,
  cte.ParentId,
  cte.CreationDate,
  cte.Score,
  cte.ViewCount,
  cte.OwnerUserId,
  cte.LastEditorUserId,
  cte.LastEditDate,
  cte.LastActivityDate,
  cte.AnswerCount,
  cte.CommentCount,
  cte.FavoriteCount,
  cte.ClosedDate,
  cte.CommunityOwnedDate,
  cte.question_tags,
  cte.parent_question_tags,
  cte.owner_net_votes,
  cte.last_editor_net_votes,
  post_history.PostHistoryTypeId,
  post_history.CreationDate AS history_creation_date,
  post_history.UserId AS history_user_id,
  post_history.Text AS history_text,
  post_history.close_reason_id,
  post_history.post_notice_id,
  post_links.RelatedPostId AS linked_post_id,
  post_links.LinkTypeId AS link_type_id
FROM cte
LEFT JOIN post_history ON cte.Id = post_history.PostId
LEFT JOIN post_links ON cte.Id = post_links.PostId
ORDER BY cte.Id, post_history.CreationDate, post_links.Id;