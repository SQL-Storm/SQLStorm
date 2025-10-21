-- {"query": "14078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1189}
WITH cte_post_history AS (
  SELECT ph.Id, ph.PostId, ph.RevisionGUID, ph.CreationDate, ph.UserId, ph.UserDisplayName, ph.Comment, ph.Text, ph.ContentLicense,
         CASE ph.PostHistoryTypeId
           WHEN 10 THEN (SELECT Name FROM CloseReasonTypes WHERE Id = CAST(ph.Comment AS int))
           WHEN 33, 34 THEN (SELECT Name FROM PostNotices WHERE Id = CAST(ph.Comment AS int))
           ELSE ph.Comment
         END AS comment_description
  FROM PostHistory ph
),
cte_post_links AS (
  SELECT pl.Id, pl.CreationDate, pl.PostId, pl.RelatedPostId, lt.Name AS link_type
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
cte_post_votes AS (
  SELECT v.Id, v.PostId, v.VoteTypeId, vt.Name AS vote_type, v.UserId, v.CreationDate, v.BountyAmount
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
),
cte_post_details AS (
  SELECT p.Id, p.PostTypeId, pt.Name AS post_type, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName AS owner_display_name,
         p.LastEditorUserId, u2.DisplayName AS last_editor_display_name, p.LastEditDate, p.LastActivityDate, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.ContentLicense
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users u2 ON p.LastEditorUserId = u2.Id
),
cte_post_badges AS (
  SELECT b.Id, b.UserId, b.Name, b.Date, b.Class, b.TagBased
  FROM Badges b
)
SELECT
  pd.Id AS post_id,
  pd.post_type,
  pd.Title,
  pd.Tags,
  pd.CreationDate,
  pd.LastEditDate,
  pd.LastActivityDate,
  pd.Score,
  pd.ViewCount,
  pd.AnswerCount,
  pd.CommentCount,
  pd.FavoriteCount,
  pd.ClosedDate,
  pd.CommunityOwnedDate,
  pd.ContentLicense,
  pd.owner_display_name,
  pd.last_editor_display_name,
  (SELECT COUNT(*) FROM cte_post_votes cpv WHERE cpv.PostId = pd.Id AND cpv.vote_type = 'UpMod') AS upvotes,
  (SELECT COUNT(*) FROM cte_post_votes cpv WHERE cpv.PostId = pd.Id AND cpv.vote_type = 'DownMod') AS downvotes,
  (SELECT COUNT(*) FROM cte_post_badges cpb WHERE cpb.UserId = pd.OwnerUserId AND cpb.TagBased = 0 AND cpb.Class = 1) AS gold_badges,
  (SELECT COUNT(*) FROM cte_post_badges cpb WHERE cpb.UserId = pd.OwnerUserId AND cpb.TagBased = 0 AND cpb.Class = 2) AS silver_badges,
  (SELECT COUNT(*) FROM cte_post_badges cpb WHERE cpb.UserId = pd.OwnerUserId AND cpb.TagBased = 0 AND cpb.Class = 3) AS bronze_badges,
  (SELECT COUNT(*) FROM cte_post_links cpl WHERE cpl.PostId = pd.Id AND cpl.link_type = 'Linked') AS linked_posts,
  (SELECT COUNT(*) FROM cte_post_links cpl WHERE cpl.PostId = pd.Id AND cpl.link_type = 'Duplicate') AS duplicate_posts,
  (SELECT STRING_AGG(comment_description, ', ') FROM cte_post_history cph WHERE cph.PostId = pd.Id) AS post_history
FROM cte_post_details pd
LEFT JOIN cte_post_votes cpv ON pd.Id = cpv.PostId
LEFT JOIN cte_post_badges cpb ON pd.OwnerUserId = cpb.UserId
LEFT JOIN cte_post_links cpl ON pd.Id = cpl.PostId
ORDER BY pd.Id;
