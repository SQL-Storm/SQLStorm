WITH
-- recent top k posts by score with complex windowing
RecentTopPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    -- rank per day for cross-filtering
    ROW_NUMBER() OVER (PARTITION BY CAST(p.CreationDate AS DATE) ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn_day
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
-- compute average score and a complex derived metric per user
UserStats AS (
  SELECT
    u.Id AS UserId,
    AVG(p.Score) AS AvgPostScore,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS HeavilyViewedCount,
    COUNT(*) AS PostCount,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
-- correlated subquery: fetch latest revision per post history type 10 (Post Closed)
LatestCloseVotes AS (
  SELECT
    ph.PostId,
    ph.Id AS HistoryId,
    ph.CreationDate AS VoteDate,
    ph.UserId AS VoterId,
    ph.Comment AS ReasonComment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId = 10
),
-- aggregate recent activity with a mix of joins: users, posts, votes, links
Activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    COALESCE(vt.Name, 'Unknown') AS VoteTypeName,
    COUNT(v.Id) AS VoteCountForPost,
    COUNT(cl.RelatedPostId) AS LinkedCount
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN PostLinks cl ON cl.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY
    p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, vt.Name
),
-- pick the latest close vote per post using a window and filter in a wrapping query
LatestCloseVotesPerPost AS (
  SELECT *
  FROM (
    SELECT
      lcv.PostId,
      lcv.HistoryId,
      lcv.VoteDate,
      lcv.VoterId,
      lcv.ReasonComment,
      ROW_NUMBER() OVER (PARTITION BY lcv.PostId ORDER BY lcv.VoteDate DESC, lcv.HistoryId DESC) AS rn
    FROM LatestCloseVotes lcv
  ) s
  WHERE s.rn = 1
)
SELECT
  -- Outer join example: combine top recent questions with user stats and latest close votes
  rtp.Id AS QuestionId,
  rtp.Title AS QuestionTitle,
  rtp.Score,
  rtp.ViewCount,
  rtp.CreationDate,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  us.AvgPostScore,
  us.HeavilyViewedCount,
  us.PostCount,
  lcv.VoteDate AS LastCloseVoteDate,
  lcv.ReasonComment AS LastCloseReasonComment,
  a.VoteCountForPost,
  a.LinkedCount,
  -- Window function: cumulative sum of scores over the last 7 rows ordered by CreationDate
  SUM(rtp.Score) OVER (
    ORDER BY rtp.CreationDate
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  ) AS SevenDayCumulativeScore,
  -- Complex string expression: length of title and a tag-derived hint
  LENGTH(rtp.Title) AS TitleLength,
  CASE
    WHEN rtp.Tags IS NOT NULL THEN
      (SELECT COUNT(*) FROM UNNEST(string_to_array(SUBSTR(rtp.Tags, 2, LENGTH(rtp.Tags) - 2), '><')) AS t(tag))
    ELSE 0
  END AS TagCountHint,
  -- NULL logic: flag posts with missing owner or zero score
  CASE
    WHEN rtp.OwnerUserId IS NULL THEN TRUE
    WHEN rtp.Score = 0 THEN TRUE
    ELSE FALSE
  END AS IsEdgeCase
FROM RecentTopPosts rtp
LEFT JOIN Users u ON u.Id = rtp.OwnerUserId
LEFT JOIN UserStats us ON us.UserId = u.Id
LEFT JOIN LatestCloseVotesPerPost lcv ON lcv.PostId = rtp.Id
LEFT JOIN Activity a ON a.PostId = rtp.Id
WHERE rtp.rn_day = 1
  AND rtp.Score > 0
ORDER BY rtp.CreationDate DESC
LIMIT 100;