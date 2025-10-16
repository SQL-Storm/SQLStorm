-- {"query": "14001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 4670, "output_tokens": 1648} 
WITH cte AS (
    SELECT p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.ParentId, p.AcceptedAnswerId, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Score, p.ViewCount, p.Title, p.Tags, u.Reputation, u.CreationDate AS UserCreationDate, u.DisplayName, u.LastAccessDate, u.WebsiteUrl, u.Location, u.AboutMe, u.Views, u.UpVotes, u.DownVotes, u.ProfileImageUrl, u.EmailHash, u.AccountId
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
),
cte2 AS (
    SELECT c.Id, c.PostId, c.Score, c.Text, c.CreationDate, c.UserDisplayName, c.UserId
    FROM Comments c
    WHERE c.PostId IN (SELECT Id FROM cte WHERE PostTypeId = 1)
),
cte3 AS (
    SELECT b.Id, b.UserId, b.Name, b.Date, b.Class, b.TagBased
    FROM Badges b
    WHERE b.UserId IN (SELECT OwnerUserId FROM cte)
),
cte4 AS (
    SELECT l.Id, l.CreationDate, l.PostId, l.RelatedPostId, l.LinkTypeId
    FROM PostLinks l
    WHERE l.PostId IN (SELECT Id FROM cte WHERE PostTypeId = 1)
)
SELECT
    cte.Id AS PostId,
    cte.PostTypeId,
    cte.CreationDate AS PostCreationDate,
    cte.OwnerUserId,
    cte.ParentId,
    cte.AcceptedAnswerId,
    cte.AnswerCount,
    cte.CommentCount,
    cte.FavoriteCount,
    cte.Score,
    cte.ViewCount,
    cte.Title,
    cte.Tags,
    cte.Reputation AS OwnerReputation,
    cte.UserCreationDate,
    cte.DisplayName AS OwnerDisplayName,
    cte.LastAccessDate AS OwnerLastAccessDate,
    cte.WebsiteUrl AS OwnerWebsiteUrl,
    cte.Location AS OwnerLocation,
    cte.AboutMe AS OwnerAboutMe,
    cte.Views AS OwnerViews,
    cte.UpVotes AS OwnerUpVotes,
    cte.DownVotes AS OwnerDownVotes,
    cte.ProfileImageUrl AS OwnerProfileImageUrl,
    cte.EmailHash AS OwnerEmailHash,
    cte.AccountId AS OwnerAccountId,
    cte2.Id AS CommentId,
    cte2.Score AS CommentScore,
    cte2.Text AS CommentText,
    cte2.CreationDate AS CommentCreationDate,
    cte2.UserDisplayName AS CommentUserDisplayName,
    cte2.UserId AS CommentUserId,
    cte3.Id AS BadgeId,
    cte3.Name AS BadgeName,
    cte3.Date AS BadgeDate,
    cte3.Class AS BadgeClass,
    cte3.TagBased AS BadgeTagBased,
    cte4.Id AS PostLinkId,
    cte4.CreationDate AS PostLinkCreationDate,
    cte4.RelatedPostId,
    cte4.LinkTypeId
FROM cte
LEFT JOIN cte2 ON cte.Id = cte2.PostId
LEFT JOIN cte3 ON cte.OwnerUserId = cte3.UserId
LEFT JOIN cte4 ON cte.Id = cte4.PostId
ORDER BY cte.CreationDate DESC
LIMIT 100;