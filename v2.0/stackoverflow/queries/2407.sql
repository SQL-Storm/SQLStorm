-- {"query": "2407.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1035}
WITH RECURSIVE RecursiveTagPostCounts AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    AVG(COALESCE(p.Score, 0)) AS AvgScore
  FROM Tags t
  LEFT JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
  GROUP BY t.Id, t.TagName

  UNION ALL

  SELECT
    rt.TagId,
    rt.TagName,
    rt.QuestionCount / 2,
    rt.TotalViews / 2,
    rt.AvgScore
  FROM RecursiveTagPostCounts rt
  WHERE rt.QuestionCount > 1000
  -- Removed LIMIT from recursive member; apply LIMIT at final query if desired
),
UserReputationChanges AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    p.Id AS PostId,
    p.Score,
    p.Title,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS PostRank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.Reputation >= 1000
),
FilteredPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    COALESCE(p.Score, 0) AS Score,
    COALESCE(p.ViewCount, 0) AS ViewCount,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserId AS EditorUserId,
    ph.Comment,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS LastEditRank
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)
  WHERE p.PostTypeId = 1 AND p.CreationDate >= DATE '2015-01-01'
),
RankedVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    COUNT(*) AS VoteCount,
    SUM(CASE WHEN v.UserId IS NULL THEN 0 ELSE 1 END) AS VotesWithUser,
    DENSE_RANK() OVER (PARTITION BY v.PostId ORDER BY COUNT(*) DESC) AS VoteRank
  FROM Votes v
  GROUP BY v.PostId, v.VoteTypeId
),
UserBadgeCounts AS (
  SELECT
    b.UserId,
    b.Class,
    COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId, b.Class
)
SELECT 
  u.DisplayName,
  rp.Title AS QuestionTitle,
  rp.Score AS QuestionScore,
  p.Score AS AnswerScore,
  rp.ViewCount,
  tc.TagName,
  ubc.GoldBadges,
  ubc.SilverBadges,
  ubc.BronzeBadges,
  COALESCE(rank_votes.VoteCounts, 0) AS TotalVotes,
  rp.LastEditRank,
  CASE
    WHEN rp.Score > 100 THEN 'Hot'
    WHEN rp.Score BETWEEN 50 AND 100 THEN 'Warm'
    ELSE 'Cold'
  END AS PopularityCategory,
  (COALESCE(rp.Title, 'No Title') || ' | ' || COALESCE(tc.TagName, 'No Tag') || ' | ' || 'Votes:' || COALESCE(CAST(rank_votes.VoteCounts AS VARCHAR), '0')) AS Summary
FROM UserReputationChanges u
LEFT JOIN Posts p ON p.ParentId = u.PostId AND p.PostTypeId = 2
LEFT JOIN FilteredPosts rp ON rp.Id = u.PostId AND rp.LastEditRank = 1
LEFT JOIN (
  SELECT
    rtp.TagName,
    rtp.QuestionCount,
    rtp.TotalViews,
    rtp.AvgScore
  FROM RecursiveTagPostCounts rtp
) tc ON rp.Tags LIKE ('%' || '<' || tc.TagName || '>' || '%')
LEFT JOIN (
  SELECT
    PostId,
    SUM(VoteCount) AS VoteCounts
  FROM RankedVotes
  WHERE VoteRank = 1
  GROUP BY PostId
) rank_votes ON rank_votes.PostId = rp.Id
LEFT JOIN (
  SELECT
    UserId,
    SUM(CASE WHEN Class = 1 THEN BadgeCount ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN Class = 2 THEN BadgeCount ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN Class = 3 THEN BadgeCount ELSE 0 END) AS BronzeBadges
  FROM UserBadgeCounts
  GROUP BY UserId
) ubc ON ubc.UserId = u.UserId
WHERE u.PostRank <= 3 AND COALESCE(rank_votes.VoteCounts, 0) > 50
ORDER BY rp.Score DESC, rank_votes.VoteCounts DESC
LIMIT 100;