-- {"query": "44057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 130758, "output_tokens": 45420} 

WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.ContentLicense,
         u.Reputation, u.CreationDate AS UserCreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.ProfileImageUrl, u.EmailHash, u.AccountId,
         b.Id AS BadgeId, b.Name AS BadgeName, b.Date AS BadgeDate, b.Class AS BadgeClass, b.TagBased AS BadgeTagBased,
         c.Id AS CommentId, c.Score AS CommentScore, c.CreationDate AS CommentCreationDate, c.ContentLicense AS CommentContentLicense,
         pl.Id AS PostLinkId, pl.CreationDate AS PostLinkCreationDate, pl.LinkTypeId, 
         t.Id AS TagId, t.TagName, t.Count AS TagCount, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired,
         v.Id AS VoteId, v.VoteTypeId, v.CreationDate AS VoteCreationDate, v.BountyAmount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN Comments c ON p.Id = c.PostId
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN Tags t ON EXISTS (SELECT 1 FROM string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') WHERE value = t.TagName)
  LEFT JOIN Votes v ON p.Id = v.PostId
)
SELECT * 
FROM cte
WHERE p.Id IN (
  SELECT Id 
  FROM Posts
  WHERE PostTypeId = 1 -- Questions
  ORDER BY CreationDate DESC
  LIMIT 1000
)
ORDER BY p.CreationDate DESC
LIMIT 100;
