-- {"query": "5457.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1001} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
TopActiveAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.Views,
    u.EmailHash,
    u.ProfileImageUrl,
    u.AccountId,
    COUNT(*) FILTER (WHERE p.rn = 1) AS LatestPostCount,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore
  FROM Users u
  LEFT JOIN RecentActivePosts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.UpVotes, u.DownVotes, u.Location, u.Views, u.EmailHash,
    u.ProfileImageUrl, u.AccountId
),
ComplexQuery AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    p1.Id AS Qid,
    p1.Title AS QTitle,
    p1.CreationDate AS QCreated,
    p1.Score AS QScore,
    p1.ViewCount AS QViews,
    COALESCE(p1.Tags, '') AS QTags,
    (SELECT COUNT(*) FROM Posts a WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2) AS NumAnswers,
    (SELECT AVG(v.BountyAmount) FROM Votes v
     WHERE v.UserId = u.Id AND v.VoteTypeId = 8) AS AvgBounty,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = u.Id) AS LastVoteDate,
    CASE WHEN u.Location IS NULL THEN 'Unknown' ELSE u.Location END AS UserLocation,
    CASE
      WHEN p1.Score > 0 THEN 'Prolific'
      WHEN p1.Score = 0 THEN 'Neutral'
      ELSE 'LowImpact'
    END AS ActivityBracket,
    (SELECT STRING_AGG(CONCAT(t.Name, ':', t.Count), ',')
     FROM Tags t
     JOIN Posts tt ON tt.Id = t.WikiPostId
     WHERE tt.OwnerUserId = u.Id) AS TagSummary
  FROM TopActiveAuthors u
  LEFT JOIN Posts p1 ON p1.OwnerUserId = u.Id AND p1.PostTypeId = 1
  WHERE p1.Id IS NOT NULL
),
JoinedSet AS (
  SELECT
    cq.UserId,
    cq.DisplayName,
    cq.Reputation,
    cq.Qid,
    cq.QTitle,
    cq.QCreated,
    cq.QScore,
    cq.QViews,
    cq.QTags,
    cq.NumAnswers,
    cq.AvgBounty,
    cq.LastVoteDate,
    cq.UserLocation,
    cq.ActivityBracket,
    cq.TagSummary,
    (SELECT MAX(LastEditDate) FROM Posts WHERE Id = cq.Qid) AS LastEditForQuestion,
    (SELECT COUNT(*) FROM Comments WHERE PostId = cq.Qid) AS CommentCount
  FROM ComplexQuery cq
)
SELECT
  j.UserId,
  j.DisplayName,
  j.Reputation,
  j.Qid AS QuestionId,
  j.QTitle,
  j.QCreated,
  j.QScore,
  j.QViews,
  j.QTags,
  j.NumAnswers,
  j.AvgBounty,
  j.LastVoteDate,
  j.UserLocation,
  j.ActivityBracket,
  j.TagSummary,
  j.LastEditForQuestion,
  j.CommentCount,
  (SELECT COUNT(*) FROM Votes v
   WHERE v.PostId = j.Qid AND v.VoteTypeId = 6) AS CloseVotes,
  (SELECT COUNT(*) FROM PostLinks pl
   WHERE pl.PostId = j.Qid AND pl.LinkTypeId = 1) AS LinkedCount,
  (SELECT STRING_AGG(CONCAT(ut.Name, '|', v.VoteTypeId, '=', v.BountyAmount), ';')
   FROM Votes v
   JOIN VoteTypes ut ON ut.Id = v.VoteTypeId
   WHERE v.PostId = j.Qid) AS VoteProfile
FROM JoinedSet j
ORDER BY j.Reputation DESC, j.QCreated DESC
LIMIT 200;