-- {"query": "5636.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 743}
WITH
ActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate
  FROM Users u
  WHERE u.Reputation > 1000
),
TagWikis AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN v.BountyAmount ELSE NULL END) AS AvgUpvoteBounty
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.Tags IS NOT NULL
  GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Tags
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    STRING_AGG(COALESCE(vt.Name, '') || ':' || CAST(v.BountyAmount AS varchar), ',' ORDER BY v.CreationDate) AS VoteSummary
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score, p.AnswerCount, p.CommentCount
)
SELECT
  ua.Id AS UserId,
  ua.DisplayName AS UserName,
  ua.Reputation,
  ua.CreationDate AS UserCreated,
  ua.LastAccessDate AS LastSeen,
  ta.PostId,
  ta.Title AS QuestionTitle,
  ta.CreationDate AS QuestionCreated,
  ta.LastActivityDate AS QuestionLastActivity,
  ta.Tags,
  ta.Upvotes,
  ta.Downvotes,
  ta.AvgUpvoteBounty,
  ra.PostId AS RecentPostId,
  ra.Title AS RecentQuestion,
  ra.CreationDate AS RecentQuestionCreated,
  ra.LastActivityDate AS RecentQuestionLastActivity,
  ra.ViewCount AS RecentViews,
  ra.Score AS RecentScore,
  ra.AnswerCount AS RecentAnswers,
  ra.CommentCount AS RecentComments,
  ra.VoteSummary,
  tt.TagName,
  tt.Count,
  tt.rn
FROM ActiveUsers ua
LEFT JOIN TagWikis ta ON ta.OwnerUserId = ua.Id
LEFT JOIN (
  SELECT ra_inner.*
  FROM (
    SELECT
      ra.*,
      ROW_NUMBER() OVER (PARTITION BY ra.PostId ORDER BY ra.LastActivityDate DESC) AS rn_post
    FROM RecentActivity ra
  ) ra_inner
  WHERE ra_inner.rn_post = 1
) ra ON ra.OwnerUserId = ua.Id
LEFT JOIN TopTags tt ON tt.rn = 1
GROUP BY
  ua.Id, ua.DisplayName, ua.Reputation, ua.CreationDate, ua.LastAccessDate,
  ta.PostId, ta.Title, ta.CreationDate, ta.LastActivityDate, ta.Tags, ta.Upvotes, ta.Downvotes, ta.AvgUpvoteBounty,
  ra.PostId, ra.Title, ra.CreationDate, ra.LastActivityDate, ra.ViewCount, ra.Score, ra.AnswerCount, ra.CommentCount, ra.VoteSummary,
  tt.TagName, tt.Count, tt.rn
ORDER BY ua.Reputation DESC, ua.Id
LIMIT 100;