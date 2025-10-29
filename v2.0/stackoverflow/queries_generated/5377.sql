-- {"query": "5377.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 832} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ACCOUNTID
  FROM Users u
  WHERE u.Reputation > 1000
),
tag_engagement AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
recent_comments AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.UserId,
    c.Score,
    c.CreationDate,
    c.Text
  FROM Comments c
  WHERE c.CreationDate >= NOW() - INTERVAL '30 days'
),
history AS (
  SELECT
    ph.PostId,
    MAX(ph.CreationDate) AS LastRevisionDate
  FROM PostHistory ph
  GROUP BY ph.PostId
),
linked_posts AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    p1.Title AS PostTitle,
    p2.Title AS RelatedPostTitle
  FROM PostLinks pl
  JOIN Posts p1 ON pl.PostId = p1.Id
  JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  WHERE pl.LinkTypeId IN (1,3)
)
SELECT
  rq.PostId,
  rq.Title AS QuestionTitle,
  rq.Tags,
  rq.CreationDate AS QuestionCreationDate,
  rq.Score AS QuestionScore,
  rq.ViewCount AS QuestionViews,
  rq.AnswerCount,
  rq.CommentCount,
  uc.UserId AS OwnerId,
  uc.DisplayName AS OwnerDisplayName,
  uc.Reputation AS OwnerReputation,
  uc.CreationDate AS OwnerCreationDate,
  uc.LastAccessDate AS OwnerLastAccessDate,
  uc.Views AS OwnerViews,
  hc.LastRevisionDate,
  (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 8) AS AvgBountyStarted,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 16) AS ModeratorReviews,
  (SELECT COUNT(*) FROM PostLinks pl2 WHERE pl2.PostId = rq.PostId) AS TotalLinks,
  (SELECT STRING_AGG(cl.Name, ',') 
     FROM PostLinks pl3
     JOIN Posts p3 ON pl3.RelatedPostId = p3.Id
     LEFT JOIN LinkTypes lt ON pl3.LinkTypeId = lt.Id
     LEFT JOIN PostHistory ph ON ph.PostId = p3.Id
     LEFT JOIN CloseReasonTypes cl ON ph.Comment LIKE CONCAT('%', cl.Id, '%')
     WHERE pl3.PostId = rq.PostId) AS RelatedPostLinkTypes
FROM recent_questions rq
JOIN top_users uc ON rq.OwnerUserId = uc.UserId
LEFT JOIN history hc ON rq.PostId = hc.PostId
LEFT JOIN recent_comments rc ON rc.PostId = rq.PostId
LEFT JOIN linked_posts lp ON rq.PostId = lp.PostId
ORDER BY rq.CreationDate DESC
LIMIT 100;