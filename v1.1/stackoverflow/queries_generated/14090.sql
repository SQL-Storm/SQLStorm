-- {"query": "14090.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 212485, "output_tokens": 91476} 
WITH cte AS (
  SELECT 
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    CASE WHEN p.ClosedDate IS NOT NULL THEN (SELECT Name FROM CloseReasonTypes WHERE Id = CAST(SUBSTRING(ph.Text, 1, CHARINDEX(',', ph.Text) - 1) AS INT))
         ELSE NULL END AS CloseReason,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN ph.UserId ELSE p.OwnerUserId END AS OwnerUserId,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community' ELSE u.DisplayName END AS OwnerDisplayName,
    DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS OwnerPostRank,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community' ELSE u.Location END AS Location,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN NULL ELSE u.AboutMe END AS AboutMe,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN NULL ELSE u.WebsiteUrl END AS WebsiteUrl,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN NULL ELSE u.ProfileImageUrl END AS ProfileImageUrl,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN NULL ELSE u.EmailHash END AS EmailHash,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN NULL ELSE u.AccountId END AS AccountId,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS Favorites,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCount,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN NULL ELSE u.Reputation END AS Reputation
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
),
post_tags AS (
  SELECT 
    PostId,
    STRING_AGG(t.TagName, ',') AS Tags
  FROM Posts p
  CROSS APPLY STRING_SPLIT(p.Tags, '><') t
  WHERE t.value <> ''
  GROUP BY PostId
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerUserId,
  c.CreationDate,
  c.LastActivityDate,
  pt.Tags,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.ClosedDate,
  c.CommunityOwnedDate,
  c.CloseReason,
  c.OwnerDisplayName,
  c.OwnerPostRank,
  c.Location,
  c.AboutMe,
  c.WebsiteUrl,
  c.ProfileImageUrl,
  c.EmailHash,
  c.AccountId,
  c.UpVotes,
  c.DownVotes,
  c.Favorites,
  c.CommentCount AS CommentCountFromComments,
  c.Reputation
FROM cte c
LEFT JOIN post_tags pt ON c.PostId = pt.PostId
ORDER BY c.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;