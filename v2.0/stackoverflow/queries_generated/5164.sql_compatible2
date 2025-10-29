WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    bt.Name AS BadgeName,
    bt.Date AS BadgeDate,
    bt.Class AS BadgeClass,
    lt.Name AS LinkTypeName,
    pl.RelatedPostId,
    pl.CreationDate AS LinkCreationDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC
    ) AS rn_owner
  FROM
    Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges bt ON u.Id = bt.UserId
      AND bt.Class IN (1,2,3)
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
      AND pl.LinkTypeId IN (1,3)
    LEFT JOIN Posts rp ON pl.RelatedPostId = rp.Id
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE
    p.PostTypeId IN (1,2)
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months'
    AND (p.FavoriteCount IS NULL OR p.FavoriteCount >= 1)
),
latest_posts AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.LastActivityDate,
    r.Tags,
    r.AnswerCount,
    r.CommentCount,
    r.FavoriteCount,
    r.Body,
    r.UserId,
    r.UserName,
    r.Reputation,
    r.UserCreationDate,
    r.LastAccessDate,
    r.BadgeName,
    r.BadgeDate,
    r.BadgeClass,
    r.LinkTypeName,
    r.RelatedPostId,
    r.LinkCreationDate,
    r.rn_owner
  FROM
    ranked_posts r
  WHERE
    r.rn_owner = 1
),
agg AS (
  SELECT
    lp.PostId,
    lp.Title,
    lp.CreationDate,
    lp.ViewCount,
    lp.Score,
    lp.OwnerUserId,
    lp.UserName,
    lp.Reputation,
    lp.LastActivityDate,
    lp.Tags,
    lp.AnswerCount,
    lp.CommentCount,
    lp.FavoriteCount,
    lp.Body,
    COALESCE(string_to_array(lp.Tags, '<>'), CAST(ARRAY[] AS varchar[])) AS tag_array,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FILTER (WHERE v.VoteTypeId IS NOT NULL AND v.VoteTypeId = 2), 0) AS UpVotesGivenByPostOwner,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FILTER (WHERE v.VoteTypeId IS NOT NULL AND v.VoteTypeId = 3), 0) AS DownVotesGivenByPostOwner,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    lp.RelatedPostId,
    lp.LinkCreationDate,
    lp.LinkTypeName,
    lp.BadgeName,
    lp.BadgeDate,
    lp.BadgeClass
  FROM
    latest_posts lp
    LEFT JOIN Votes v ON v.PostId = lp.PostId
  GROUP BY
    lp.PostId, lp.Title, lp.CreationDate, lp.ViewCount, lp.Score, lp.OwnerUserId,
    lp.UserName, lp.Reputation, lp.LastActivityDate, lp.Tags, lp.AnswerCount,
    lp.CommentCount, lp.FavoriteCount, lp.Body, lp.RelatedPostId, lp.LinkCreationDate,
    lp.LinkTypeName, lp.BadgeName, lp.BadgeDate, lp.BadgeClass
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerUserId AS OwnerId,
  a.UserName AS OwnerDisplayName,
  a.Reputation AS OwnerReputation,
  a.CreationDate,
  a.LastActivityDate,
  a.ViewCount,
  a.Score,
  a.AnswerCount,
  a.CommentCount,
  a.FavoriteCount,
  a.Body,
  a.Tags,
  COALESCE(a.TotalUpVotes,0) AS TotalUpVotes,
  COALESCE(a.TotalDownVotes,0) AS TotalDownVotes,
  COALESCE(a.UpVotesGivenByPostOwner,0) AS UpVotesGivenByPostOwner,
  COALESCE(a.DownVotesGivenByPostOwner,0) AS DownVotesGivenByPostOwner,
  (CASE WHEN COALESCE(a.TotalUpVotes,0) > COALESCE(a.TotalDownVotes,0) THEN 'UpBumped' ELSE 'Neutral' END) AS MomentumLabel,
  (CASE WHEN array_length(a.tag_array, 1) >= 2 THEN true ELSE false END) AS MultiTagFlag,
  (a.LinkTypeName IS NOT NULL) AS HasLinks,
  a.RelatedPostId AS CoReferencedPost,
  a.LinkCreationDate
FROM agg a
ORDER BY a.LastActivityDate DESC, a.Score DESC
LIMIT 100;