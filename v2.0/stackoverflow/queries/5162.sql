WITH
recent_top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
),
correlated_user_stats AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    u.Id AS UserId,
    u.DisplayName AS UserDisplayName,
    u.Reputation,
    u.AccountId,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AboutMe,
    u.ProfileImageUrl,
    u.WebsiteUrl
  FROM recent_top_questions r
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
),
tag_explosion AS (
  SELECT
    c.PostId,
    c.Title,
    t.TagName,
    CASE
      WHEN t.TagName IS NULL THEN 'untagged'
      ELSE t.TagName
    END AS TagUsed,
    LENGTH(COALESCE(t.TagName, '')) AS TagLength
  FROM correlated_user_stats c,
  LATERAL (
    SELECT unnest(string_to_array(substring(c.Tags FROM 2 FOR (char_length(c.Tags)-2)), '><')) AS TagName
  ) t
),
activity_summary AS (
  SELECT
    te.PostId,
    te.Title,
    te.TagUsed,
    te.TagLength,
    v.CreationDate AS VoteDate,
    v.VoteTypeId,
    v.BountyAmount,
    CASE
      WHEN v.VoteTypeId = 2 THEN 'Upvote'
      WHEN v.VoteTypeId = 3 THEN 'Downvote'
      WHEN v.VoteTypeId = 10 THEN 'Deletion'
      WHEN v.VoteTypeId = 11 THEN 'Undeletion'
      WHEN v.VoteTypeId = 8 THEN 'BountyStart'
      WHEN v.VoteTypeId = 9 THEN 'BountyClose'
      WHEN v.VoteTypeId = 12 THEN 'Spam'
      ELSE 'Other'
    END AS VoteLabel,
    ROW_NUMBER() OVER (PARTITION BY te.PostId ORDER BY v.CreationDate DESC) AS rn
  FROM tag_explosion te
  LEFT JOIN Votes v ON v.PostId = te.PostId
    AND v.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365' DAY)
    AND v.VoteTypeId IN (2,3,8,9,10,11,12)
)
SELECT
  p.Id AS PostId,
  p.Title,
  p.Tags,
  p.OwnerUserId AS OwnerId,
  u.UserDisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  u.Location AS OwnerLocation,
  p.ViewCount AS ViewCount,
  p.Score AS Score,
  p.AnswerCount AS Answers,
  p.CommentCount AS Comments,
  p.CreationDate AS CreatedAt,
  p.LastActivityDate AS LastActiveAt,
  a.TagUsed AS TopTag,
  a.TagLength AS TagLength,
  a.VoteDate,
  a.VoteLabel,
  a.BountyAmount,
  a.rn
FROM Posts p
LEFT JOIN correlated_user_stats u ON u.UserId = p.OwnerUserId
LEFT JOIN activity_summary a ON a.PostId = p.Id
WHERE p.Id IN (
  SELECT PostId FROM recent_top_questions
)
GROUP BY
  p.Id,
  p.Title,
  p.Tags,
  p.OwnerUserId,
  u.UserDisplayName,
  u.Reputation,
  u.Location,
  p.ViewCount,
  p.Score,
  p.AnswerCount,
  p.CommentCount,
  p.CreationDate,
  p.LastActivityDate,
  a.TagUsed,
  a.TagLength,
  a.VoteDate,
  a.VoteLabel,
  a.BountyAmount,
  a.rn
ORDER BY p.Score DESC, p.LastActivityDate DESC
LIMIT 100;