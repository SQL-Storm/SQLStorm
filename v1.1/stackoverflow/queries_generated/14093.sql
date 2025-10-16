-- {"query": "14093.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 219490, "output_tokens": 94995} 
WITH cte AS (
  SELECT p.Id, p.Title, p.Body, p.Tags, p.CreationDate, p.OwnerUserId, u.DisplayName, u.Reputation, u.Location, u.AboutMe, u.ProfileImageUrl, u.EmailHash,
         ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate) AS rn
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (2, 5, 8)
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
agg_cte AS (
  SELECT Id, Title, Body, Tags, CreationDate, OwnerUserId, DisplayName, Reputation, Location, AboutMe, ProfileImageUrl, EmailHash,
         STRING_AGG(CASE WHEN rn = 1 THEN Body ELSE NULL END, ' ') OVER (PARTITION BY Id) AS post_body,
         STRING_AGG(CASE WHEN rn = 2 THEN Body ELSE NULL END, ' ') OVER (PARTITION BY Id) AS edit_body,
         STRING_AGG(CASE WHEN rn = 3 THEN Body ELSE NULL END, ' ') OVER (PARTITION BY Id) AS rollback_body
  FROM cte
)
SELECT p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
       a.post_body, a.edit_body, a.rollback_body, a.DisplayName, a.Reputation, a.Location, a.AboutMe, a.ProfileImageUrl, a.EmailHash,
       STRING_AGG(DISTINCT t.TagName, ',') AS tags,
       STRING_AGG(DISTINCT CAST(l.Name AS VARCHAR(50)), ',') AS link_types,
       STRING_AGG(DISTINCT CAST(c.Name AS VARCHAR(50)), ',') AS close_reasons,
       STRING_AGG(DISTINCT CAST(v.Name AS VARCHAR(50)), ',') AS vote_types,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS upvotes,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS downvotes,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS favorites,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END), 0) AS close_votes,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 7 THEN 1 ELSE 0 END), 0) AS reopen_votes,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END), 0) AS deletion_votes,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 11 THEN 1 ELSE 0 END), 0) AS undeletion_votes,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 12 THEN 1 ELSE 0 END), 0) AS spam_votes,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 14 THEN 1 ELSE 0 END), 0) AS moderator_nomination_votes,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 15 THEN 1 ELSE 0 END), 0) AS moderator_review_votes
FROM Posts p
LEFT JOIN agg_cte a ON p.Id = a.Id
LEFT JOIN PostLinks l ON p.Id = l.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%<' + t.TagName + '>%'
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
LEFT JOIN CloseReasonTypes c ON CAST(ph.Comment AS INT) = c.Id
GROUP BY p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
         a.post_body, a.edit_body, a.rollback_body, a.DisplayName, a.Reputation, a.Location, a.AboutMe, a.ProfileImageUrl, a.EmailHash
ORDER BY p.CreationDate DESC;