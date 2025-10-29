-- {"query": "5750.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 887} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.ParentId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.LastActivityDate,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
),
OwnerStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    COUNT(r.Id) AS QuestionCount,
    AVG(r.Score) AS AvgQuestionScore,
    SUM(r.ViewCount) AS TotalQuestionViews
  FROM Users u
  LEFT JOIN Posts r ON r.OwnerUserId = u.Id AND r.PostTypeId = 1
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Views, u.UpVotes, u.DownVotes, u.Location, u.WebsiteUrl, u.AboutMe,
    u.ProfileImageUrl, u.EmailHash, u.AccountId
),
TagHierarchy AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsWithTag
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
  GROUP BY t.TagName
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CommentCount,
    v.VoteTypeId,
    v.UserId AS VoterUserId,
    v.CreationDate AS VoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
),
ComplexFilters AS (
  SELECT
    rp.Id,
    rp.ParentId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.AcceptedAnswerId,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.CreationDate DESC) AS rownum
  FROM RankedPosts rp
  WHERE rp.rn_owner = 1
)
SELECT
  cf.Id AS QuestionId,
  cf.Title AS QuestionTitle,
  cf.Tags,
  cf.CreationDate AS CreatedAt,
  cf.Score AS QuestionScore,
  cf.ViewCount AS Views,
  cf.CommentCount AS CommentCount,
  cf.LastActivityDate AS LastActive,
  o.DisplayName AS OwnerDisplayName,
  o.Reputation AS OwnerReputation,
  o.TotalQuestionViews AS OwnerTotalViews,
  ta.QuestionsWithTag AS TagQuestionCount
FROM ComplexFilters cf
LEFT JOIN OwnerStats o ON o.UserId = cf.OwnerUserId
LEFT JOIN TagHierarchy ta ON true
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) AS QuestionsWithThisTag
  FROM Posts q
  CROSS JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS t(TagName)
  WHERE t.TagName = ANY(string_to_array(substring(cf.Tags, 2, length(cf.Tags)-2), '><'))
    AND q.PostTypeId = 1
) tcounts ON true
ORDER BY cf.Score DESC, cf.ViewCount DESC
LIMIT 100;