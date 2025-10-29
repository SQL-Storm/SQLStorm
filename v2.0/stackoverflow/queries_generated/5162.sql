-- {"query": "5162.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 839} 
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
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
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
    u.EmailHash,
    u.WebsiteUrl,
    u.Business AS DummyField -- placeholder to ensure complex expression
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
    LENGTH(coalesce(t.TagName, '')) AS TagLength
  FROM correlated_user_stats c
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(c.Tags, 2, length(c.Tags)-2), '><')) AS TagName
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
    AND v.CreationDate >= NOW() - INTERVAL '365 days'
    AND v.VoteTypeId IN (2,3,8,9,10,11,12)
)
SELECT
  p.PostId,
  p.Title,
  p.Tags,
  p.OwnerUserId AS OwnerId,
  p.UserDisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  u.Location AS OwnerLocation,
  p.Views AS ViewCount,
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
ORDER BY p.Score DESC, p.LastActivityDate DESC
LIMIT 100;