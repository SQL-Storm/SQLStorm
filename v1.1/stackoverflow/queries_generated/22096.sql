-- {"query": "22096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 2071} 
WITH
  UserStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
      SUM(p.Score) AS TotalScore,
      AVG(p.Score) AS AvgScore,
      MIN(p.CreationDate) AS FirstPostDate,
      MAX(p.LastActivityDate) AS LastActivityDate,
      STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE p.PostTypeId = 1 AND t.TagName IS NOT NULL) AS PopularTags,
      COUNT(DISTINCT b.Id) AS TotalBadges,
      SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS BadgePoints
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN (
      SELECT p.Id AS PostId, UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName
      FROM Posts p
      WHERE p.Tags IS NOT NULL
    ) pt ON p.Id = pt.PostId
    LEFT JOIN Tags t ON pt.TagName = t.TagName
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),
  PostVoteStats AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      COUNT(v.Id) AS TotalVotes,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
      COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites,
      SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountiesOffered,
      SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS TotalBountiesAwarded
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.OwnerUserId
  ),
  CommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalComments,
      SUM(c.Score) AS CommentScoreSum,
      AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    GROUP BY c.UserId
  ),
  TopUsers AS (
    SELECT
      us.UserId,
      us.DisplayName,
      us.Reputation,
      us.TotalPosts,
      us.QuestionsAsked,
      us.AnswersGiven,
      us.TotalScore,
      us.AvgScore,
      pvs.TotalVotes,
      pvs.UpVotes,
      pvs.DownVotes,
      pvs.Favorites,
      pvs.TotalBountiesOffered,
      pvs.TotalBountiesAwarded,
      cs.TotalComments,
      cs.CommentScoreSum,
      cs.AvgCommentLength,
      us.PopularTags,
      us.TotalBadges,
      us.BadgePoints,
      CASE
        WHEN us.LastActivityDate IS NULL THEN 'Inactive'
        WHEN us.LastActivityDate > NOW() - INTERVAL '30 days' THEN 'Active'
        ELSE 'Semi-Active'
      END AS ActivityStatus,
      EXTRACT(YEAR FROM us.FirstPostDate) AS RegistrationYear,
      ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) AS RepRank,
      DENSE_RANK() OVER (ORDER BY us.TotalScore DESC) AS ScoreRank,
      RANK() OVER (ORDER BY us.TotalBadges DESC) AS BadgeRank
    FROM UserStats us
    LEFT JOIN PostVoteStats pvs ON us.UserId = pvs.OwnerUserId
    LEFT JOIN CommentStats cs ON us.UserId = cs.UserId
    WHERE us.TotalPosts > 0
      AND (us.Reputation > 1000 OR us.TotalBadges > 5)
      AND (us.AvgScore IS NULL OR us.AvgScore > 0)
  ),
  EditsAndHistory AS (
    SELECT
      ph.UserId,
      COUNT(ph.Id) AS EditCount,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13,14,15,19,20,35,36) THEN 1 END) AS ModActions,
      MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.UserId
  ),
  LinkedPosts AS (
    SELECT
      pl.PostId,
      COUNT(pl.Id) AS LinksCreated,
      COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicatesMarked
    FROM PostLinks pl
    GROUP BY pl.PostId
  )
SELECT
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.TotalPosts,
  tu.QuestionsAsked,
  tu.AnswersGiven,
  tu.TotalScore,
  ROUND(tu.AvgScore, 2) AS AvgScore,
  COALESCE(tu.TotalVotes, 0) AS TotalVotes,
  COALESCE(tu.UpVotes, 0) AS UpVotes,
  COALESCE(tu.DownVotes, 0) AS DownVotes,
  COALESCE(tu.Favorites, 0) AS Favorites,
  COALESCE(tu.TotalBountiesOffered, 0) AS TotalBountiesOffered,
  COALESCE(tu.TotalBountiesAwarded, 0) AS TotalBountiesAwarded,
  COALESCE(tu.TotalComments, 0) AS TotalComments,
  COALESCE(tu.CommentScoreSum, 0) AS CommentScoreSum,
  ROUND(COALESCE(tu.AvgCommentLength, 0), 2) AS AvgCommentLength,
  COALESCE(tu.PopularTags, 'None') AS PopularTags,
  tu.TotalBadges,
  tu.BadgePoints,
  tu.ActivityStatus,
  tu.RegistrationYear,
  tu.RepRank,
  tu.ScoreRank,
  tu.BadgeRank,
  eh.EditCount,
  eh.ModActions,
  eh.LastEditDate,
  lp.LinksCreated,
  lp.DuplicatesMarked,
  CASE
    WHEN tu.RepRank <= 10 THEN 'Elite'
    WHEN tu.ScoreRank <= 50 THEN 'High Contributor'
    ELSE 'Regular'
  END AS UserCategory,
  ROUND(
    (tu.TotalScore + COALESCE(tu.CommentScoreSum, 0) + tu.BadgePoints * 10) / NULLIF(tu.TotalPosts, 0),
    2
  ) AS CompositeScore
FROM TopUsers tu
LEFT JOIN EditsAndHistory eh ON tu.UserId = eh.UserId
LEFT JOIN LinkedPosts lp ON tu.UserId = (
  SELECT p.OwnerUserId
  FROM Posts p
  WHERE p.Id = lp.PostId
)
WHERE tu.TotalPosts > 10
  AND (eh.EditCount IS NULL OR eh.EditCount > 5)
  AND (lp.LinksCreated IS NULL OR lp.LinksCreated > 0)
UNION ALL
SELECT
  NULL AS UserId,
  'Summary' AS DisplayName,
  AVG(tu.Reputation) AS Reputation,
  SUM(tu.TotalPosts) AS TotalPosts,
  SUM(tu.QuestionsAsked) AS QuestionsAsked,
  SUM(tu.AnswersGiven) AS AnswersGiven,
  SUM(tu.TotalScore) AS TotalScore,
  AVG(tu.AvgScore) AS AvgScore,
  SUM(COALESCE(tu.TotalVotes, 0)) AS TotalVotes,
  SUM(COALESCE(tu.UpVotes, 0)) AS UpVotes,
  SUM(COALESCE(tu.DownVotes, 0)) AS DownVotes,
  SUM(COALESCE(tu.Favorites, 0)) AS Favorites,
  SUM(COALESCE(tu.TotalBountiesOffered, 0)) AS TotalBountiesOffered,
  SUM(COALESCE(tu.TotalBountiesAwarded, 0)) AS TotalBountiesAwarded,
  SUM(COALESCE(tu.TotalComments, 0)) AS TotalComments,
  SUM(COALESCE(tu.CommentScoreSum, 0)) AS CommentScoreSum,
  AVG(COALESCE(tu.AvgCommentLength, 0)) AS AvgCommentLength,
  'Aggregated' AS PopularTags,
  SUM(tu.TotalBadges) AS TotalBadges,
  SUM(tu.BadgePoints) AS BadgePoints,
  'All' AS ActivityStatus,
  AVG(tu.RegistrationYear) AS RegistrationYear,
  NULL AS RepRank,
  NULL AS ScoreRank,
  NULL AS BadgeRank,
  SUM(eh.EditCount) AS EditCount,
  SUM(eh.ModActions) AS ModActions,
  MAX(eh.LastEditDate) AS LastEditDate,
  SUM(lp.LinksCreated) AS LinksCreated,
  SUM(lp.DuplicatesMarked) AS DuplicatesMarked,
  'Aggregate' AS UserCategory,
  AVG(ROUND(
    (tu.TotalScore + COALESCE(tu.CommentScoreSum, 0) + tu.BadgePoints * 10) / NULLIF(tu.TotalPosts, 0),
    2
  )) AS CompositeScore
FROM TopUsers tu
LEFT JOIN EditsAndHistory eh ON tu.UserId = eh.UserId
LEFT JOIN LinkedPosts lp ON tu.UserId = (
  SELECT p.OwnerUserId
  FROM Posts p
  WHERE p.Id = lp.PostId
)
ORDER BY RepRank NULLS LAST, UserId NULLS FIRST;