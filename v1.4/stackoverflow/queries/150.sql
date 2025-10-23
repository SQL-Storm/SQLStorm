-- {"query": "150.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2604} 
WITH
-- Top-level per-user recent activity and profile context
UserProfile AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(u.WebsiteUrl, '') AS WebsiteUrl,
    COALESCE(u.AboutMe, '') AS AboutMe,
    -- Number of questions recently opened by the user (PostTypeId = 1) in last 180 days
    SUM(CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days' THEN 1 ELSE 0 END) AS RecentQuestions
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes, u.WebsiteUrl, u.AboutMe
),
-- Per-user last activity post with computed windowed rankings
UserPostRank AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        p.LastActivityDate DESC NULLS LAST,
        p.CreationDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- focus on questions and answers for benchmarking
),
-- Aggregated vote statistics per post (sum of bounty amounts and counts)
PostVotes AS (
  SELECT
    v.PostId,
    SUM(v.BountyAmount) AS TotalBounty,
    COUNT(*) AS VoteEvents,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  GROUP BY v.PostId
),
-- Tag statistics enriched from Tags and their associated posts
TagStats AS (
  SELECT
    tg.TagName,
    COUNT(*) AS TagPostCount
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.Id OR p.Id = tg.ExcerptPostId OR p.Id = tg.WikiPostId
  GROUP BY tg.TagName
),
-- Historical context: recent close/reopen activity to stress correlation
CloseActivity AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.Comment,
    ph.UserId
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10,11,52,53) -- Post Closed / Reopened / SelectedHotQuestion / RemovedHotQuestion
),
-- Build a complex derived set combining posts with user, votes, and tags
BenchmarkSet AS (
  SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.UserCreationDate,
    up.LastAccessDate,
    pr.PostId,
    pr.Title,
    pr.PostTypeId,
    pr.CreationDate AS PostCreationDate,
    pr.LastActivityDate,
    pr.Score,
    pr.ViewCount,
    pr.Tags,
    COALESCE(pv.TotalBounty, 0) AS TotalBounty,
    COALESCE(pv.VoteEvents, 0) AS VoteEvents,
    COALESCE(pv.UpVotes, 0) AS UpVotes,
    COALESCE(pv.DownVotes, 0) AS DownVotes,
    COALESCE(ts.TagPostCount, 0) AS AssociatedTagCount,
    ca.PostHistoryTypeId AS CloseTypeId,
    ca.CreationDate AS CloseDate
  FROM UserProfile up
  LEFT JOIN UserPostRank pr
    ON pr.OwnerUserId = up.UserId
  LEFT JOIN PostVotes pv
    ON pv.PostId = pr.PostId
  LEFT JOIN TagStats ts
    ON ts.TagName IN (SELECT UNNEST(string_to_array(pr.Tags, '><')) AS TagName)
  LEFT JOIN CloseActivity ca
    ON ca.PostId = pr.PostId
  WHERE pr.rn = 1 -- take latest activity per user
),
-- Complex correlated predicate set to stress conditions and NULL handling
Predicates AS (
  SELECT
    b.*,
    CASE
      WHEN b.TotalBounty > 0 THEN 1
      WHEN b.VoteEvents > 50 THEN 2
      ELSE 0
    END AS StressIndicator,
    CASE
      WHEN b.PostTypeId = 1 THEN 'Question'
      WHEN b.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    CASE
      WHEN b.CloseTypeId IS NULL THEN NULL
      ELSE (SELECT Name FROM CloseReasonTypes cr WHERE cr.Id = b.CloseTypeId)
    END AS CloseReason
  FROM BenchmarkSet b
)
SELECT
  p.UserId,
  p.DisplayName,
  p.Reputation,
  p.UserCreationDate,
  p.LastAccessDate,
  p.PostId,
  p.Title,
  p.PostTypeId,
  p.PostCreationDate,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.TotalBounty,
  p.VoteEvents,
  p.UpVotes,
  p.DownVotes,
  p.AssociatedTagCount,
  p.CloseDate,
  p.CloseReason,
  p.StressIndicator,
  p.PostKind
FROM Predicates p
ORDER BY p.Reputation DESC NULLS LAST,
         p.StressIndicator DESC,
         p.TotalBounty DESC,
         p.VoteEvents DESC
LIMIT 200;