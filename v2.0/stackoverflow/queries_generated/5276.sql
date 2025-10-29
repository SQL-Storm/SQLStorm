-- {"query": "5276.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 676} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Location,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  COALESCE(b.TotalBadges, 0) AS TotalBadges,
  COALESCE(vp.TotalVotesOnPosts, 0) AS TotalVotesOnPosts,
  COALESCE(pq.QualifiedQuestionCount, 0) AS QualifiedQuestionCount,
  COALESCE(qa.AnswerCountFromOwner, 0) AS AnswerCountFromOwner,
  STRING_AGG(DISTINCT tmt.Name, ',') AS TopBadgesByName,
  MAX(CASE WHEN Voted.OnTime IS TRUE THEN Voted.OnTime ELSE FALSE END) AS HasOnTimeVote
FROM
  Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT
      OwnerUserId,
      SUM(Score) AS TotalVotesOnPosts
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    WHERE v.VoteTypeId IN (2, 3) -- UpMod / DownMod
    GROUP BY OwnerUserId
  ) vp ON vp.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId,
           COUNT(*) AS QualifiedQuestionCount
    FROM Posts q
    WHERE q.PostTypeId = 1 -- Questions
      AND q.Score >= 5
      AND q.CloseReasonId IS NULL
    GROUP BY OwnerUserId
  ) pq ON pq.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId,
           COUNT(*) AS AnswerCountFromOwner
    FROM Posts a
    WHERE a.PostTypeId = 2 -- Answers
    GROUP BY OwnerUserId
  ) qa ON qa.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      p.OwnerUserId,
      STRING_AGG(t.Name, ',') AS TopBadgeNames
    FROM Posts p
    JOIN Badges b2 ON b2.UserId = p.OwnerUserId
    JOIN Tags t ON t.Id = b2.TagBased -- approximate mapping for tag badges
    WHERE b2.Class = 1
    GROUP BY p.OwnerUserId
  ) tmt ON tmt.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      UserId,
      MAX(CASE WHEN PostHistoryTypeId = 52 THEN TRUE ELSE FALSE END) AS OnTime
    FROM PostHistory ph
    GROUP BY UserId
  ) Voted ON Voted.UserId = u.Id
WHERE
  u.Id < 1000000
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Location,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  b.TotalBadges,
  vp.TotalVotesOnPosts,
  pq.QualifiedQuestionCount,
  qa.AnswerCountFromOwner;