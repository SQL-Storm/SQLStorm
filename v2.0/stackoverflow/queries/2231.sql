-- {"query": "2231.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1520}
WITH RECURSIVE RecursiveTagHierarchy AS (
  SELECT 
    t.Id,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    1 AS Level,
    CAST(t.TagName AS VARCHAR(255)) AS Path
  FROM Tags t
  WHERE t.IsModeratorOnly = false AND t.IsRequired = false
  UNION ALL
  SELECT 
    t.Id,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    r.Level + 1 AS Level,
    r.Path || '>' || t.TagName AS Path
  FROM Tags t
  JOIN RecursiveTagHierarchy r ON t.Id != r.Id AND t.Count < r.Count
  WHERE r.Level < 3
),
UserBadgeStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
    MAX(b.Date) AS LatestBadgeDate,
    (SELECT b2.Name
     FROM Badges b2
     WHERE b2.UserId = u.Id
     ORDER BY b2.Date DESC
     LIMIT 1) AS LatestBadgeName
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
PostScoreRanks AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.Title,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
    FIRST_VALUE(p.Title) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS TopPostTitle
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
TopPostsWithAnswers AS (
  SELECT
    q.Id AS QuestionId,
    q.Title AS QuestionTitle,
    q.Score AS QuestionScore,
    q.ViewCount AS QuestionViews,
    a.Id AS AnswerId,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerCreationDate,
    u.DisplayName AS AnswererDisplayName,
    ABS(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) / 3600 AS HoursToAnswer,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id AND c.CreationDate > a.CreationDate) AS CommentsAfterAnswer
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN Users u ON u.Id = a.OwnerUserId
  WHERE q.PostTypeId = 1
    AND q.Score > 100
    AND a.Score IS NOT NULL
),
VoteAggregates AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    COUNT(DISTINCT v.UserId) AS DistinctVoters,
    MAX(v.BountyAmount) AS MaxBounty
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id, p.PostTypeId
),
ClosedQuestionsWithReasons AS (
  SELECT
    ph.PostId,
    CAST(ph.Comment AS INTEGER) AS CloseReasonId,
    crt.Name AS CloseReasonName,
    COUNT(*) AS CloseVoteCount,
    MAX(ph.CreationDate) AS LastCloseVoteDate
  FROM PostHistory ph
  JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
  WHERE ph.PostHistoryTypeId = 10
  GROUP BY ph.PostId, CAST(ph.Comment AS INTEGER), crt.Name
),
FinalResult AS (
  SELECT 
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    u.DisplayName AS OwnerName,
    u.Reputation,
    COALESCE(v.Upvotes,0) AS Upvotes,
    COALESCE(v.Downvotes,0) AS Downvotes,
    COALESCE(v.DistinctVoters,0) AS DistinctVoters,
    COALESCE(v.MaxBounty,0) AS MaxBounty,
    COALESCE(ub.GoldBadges,0) AS GoldBadges,
    COALESCE(ub.SilverBadges,0) AS SilverBadges,
    COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
    ps.ScoreRank,
    ps.TopPostTitle,
    cq.CloseReasonName,
    cq.CloseVoteCount,
    tqh.Level AS TagComplexityLevel,
    tqh.Path AS TagHierarchyPath
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN VoteAggregates v ON v.PostId = p.Id
  LEFT JOIN UserBadgeStats ub ON ub.UserId = p.OwnerUserId
  LEFT JOIN PostScoreRanks ps ON ps.Id = p.Id
  LEFT JOIN ClosedQuestionsWithReasons cq ON cq.PostId = p.Id
  LEFT JOIN RecursiveTagHierarchy tqh ON POSITION('<' || tqh.TagName || '>' IN COALESCE(p.Tags, '')) > 0
  WHERE p.PostTypeId = 1
    AND (p.Score > 50 OR COALESCE(v.Upvotes,0) > 40)
)
SELECT DISTINCT
  fr.PostId,
  fr.Title,
  fr.OwnerName,
  fr.Reputation,
  fr.Upvotes,
  fr.Downvotes,
  fr.DistinctVoters,
  fr.MaxBounty,
  fr.GoldBadges,
  fr.SilverBadges,
  fr.BronzeBadges,
  fr.ScoreRank,
  fr.TopPostTitle,
  fr.CloseReasonName,
  fr.CloseVoteCount,
  fr.TagComplexityLevel,
  fr.TagHierarchyPath,
  (CASE 
    WHEN fr.CloseReasonName IS NOT NULL THEN 'Closed: ' || fr.CloseReasonName
    ELSE 'Open'
   END) AS PostStatus,
  COALESCE((
    SELECT AVG(CAST(a.Score AS NUMERIC))
    FROM Posts a
    WHERE a.ParentId = fr.PostId AND a.PostTypeId = 2
  ), 0) AS AverageAnswerScore,
  COALESCE((
    SELECT COUNT(*)
    FROM Comments c
    WHERE c.PostId = fr.PostId AND c.UserId IS NOT NULL
  ), 0) AS CommentCount,
  (
    SELECT STRING_AGG(DISTINCT u2.DisplayName, '; ')
    FROM Users u2
    JOIN Posts p2 ON p2.OwnerUserId = u2.Id 
    WHERE p2.Id IN (
      SELECT pl.RelatedPostId FROM PostLinks pl WHERE pl.PostId = fr.PostId AND pl.LinkTypeId = 1
    )
  ) AS LinkedPostOwners
FROM FinalResult fr
ORDER BY fr.Upvotes DESC, fr.Reputation DESC, fr.ScoreRank
LIMIT 50;