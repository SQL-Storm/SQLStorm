-- {"query": "4566.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3580}
WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostDate,
      SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalComments,
      AVG(c.Score) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountyStartCount,
      MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  UserBadgeCounts AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount,
      MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY
      b.UserId
  ),
  PostHistorySummary AS (
    SELECT
      ph.UserId,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditsMade,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 END) AS ModerationActions,
      MAX(ph.CreationDate) AS LastHistoryEntryDate
    FROM PostHistory ph
    WHERE
      ph.UserId IS NOT NULL
    GROUP BY
      ph.UserId
  ),
  DetailedUserStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      ups.TotalPosts,
      ups.QuestionCount,
      ups.AnswerCount,
      ups.AvgPostScore,
      ups.LastPostDate,
      ups.TotalViews AS PostTotalViews,
      ucs.TotalComments,
      ucs.AvgCommentScore,
      ucs.LastCommentDate,
      uvs.UpVoteCount,
      uvs.DownVoteCount,
      uvs.BountyStartCount,
      uvs.LastVoteDate,
      ubc.GoldBadgeCount,
      ubc.SilverBadgeCount,
      ubc.BronzeBadgeCount,
      ubc.LastBadgeDate,
      phs.EditsMade,
      phs.ModerationActions,
      phs.LastHistoryEntryDate,
      pht.Name AS LastPostHistoryTypeName,
      u.WebsiteUrl,
      u.AboutMe,
      u.Location
    FROM Users u
    LEFT JOIN UserPostStats ups
      ON u.Id = ups.OwnerUserId
    LEFT JOIN UserCommentStats ucs
      ON u.Id = ucs.UserId
    LEFT JOIN UserVoteStats uvs
      ON u.Id = uvs.UserId
    LEFT JOIN UserBadgeCounts ubc
      ON u.Id = ubc.UserId
    LEFT JOIN PostHistorySummary phs
      ON u.Id = phs.UserId
    LEFT JOIN PostHistory ph_last
      ON u.Id = ph_last.UserId AND ph_last.CreationDate = phs.LastHistoryEntryDate
    LEFT JOIN PostHistoryTypes pht
      ON ph_last.PostHistoryTypeId = pht.Id
  )
SELECT
  dus.UserId,
  dus.DisplayName,
  dus.Reputation,
  dus.UserCreationDate,
  dus.UserViews,
  dus.UserUpVotes,
  dus.UserDownVotes,
  COALESCE(dus.TotalPosts, 0) AS CalculatedTotalPosts,
  COALESCE(dus.QuestionCount, 0) AS CalculatedQuestionCount,
  COALESCE(dus.AnswerCount, 0) AS CalculatedAnswerCount,
  dus.AvgPostScore,
  dus.PostTotalViews,
  COALESCE(dus.TotalComments, 0) AS CalculatedTotalComments,
  dus.AvgCommentScore,
  dus.UpVoteCount,
  dus.DownVoteCount,
  dus.BountyStartCount,
  dus.GoldBadgeCount,
  dus.SilverBadgeCount,
  dus.BronzeBadgeCount,
  dus.EditsMade,
  dus.ModerationActions,
  CASE
    WHEN CAST('2024-10-01 12:34:56' AS TIMESTAMP) - dus.UserCreationDate > INTERVAL '365 days' THEN 'Experienced'
    WHEN CAST('2024-10-01 12:34:56' AS TIMESTAMP) - dus.UserCreationDate BETWEEN INTERVAL '90 days' AND INTERVAL '365 days' THEN 'Intermediate'
    ELSE 'New'
  END AS UserExperienceLevel,
  CASE
    WHEN dus.LastPostDate IS NULL AND dus.LastCommentDate IS NULL THEN 'No Activity'
    WHEN dus.LastPostDate IS NULL THEN 'Commenter Only'
    WHEN dus.LastCommentDate IS NULL THEN 'Poster Only'
    ELSE 'Active Poster & Commenter'
  END AS ActivityType,
  CASE
    WHEN dus.AvgPostScore > 10 AND dus.Reputation > 5000 THEN 'High Impact User'
    WHEN dus.AvgPostScore <= 0 AND dus.Reputation < 1000 THEN 'Low Impact User'
    ELSE 'Standard User'
  END AS UserImpactCategory,
  CASE
    WHEN dus.DisplayName LIKE '%Admin%' OR dus.DisplayName LIKE '%Moderator%' THEN 'Potential Admin/Mod'
    ELSE 'Regular User'
  END AS DisplayNameCategory,
  CASE
    WHEN dus.GoldBadgeCount > 5 THEN 'Elite Gold'
    WHEN dus.SilverBadgeCount > 10 THEN 'Elite Silver'
    ELSE 'Standard Badges'
  END AS BadgeTier,
  LEAST(COALESCE(dus.TotalPosts, 0), COALESCE(dus.TotalComments, 0), COALESCE(dus.UpVoteCount, 0)) AS MinActivityMetric,
  GREATEST(COALESCE(dus.TotalPosts, 0), COALESCE(dus.TotalComments, 0), COALESCE(dus.UpVoteCount, 0)) AS MaxActivityMetric,
  ROW_NUMBER() OVER (ORDER BY dus.Reputation DESC, dus.UserCreationDate ASC) AS RankByReputation,
  LAG(dus.DisplayName, 1, 'No Previous User') OVER (ORDER BY dus.UserCreationDate) AS PreviousUserDisplayName,
  LEAD(dus.DisplayName, 1, 'No Next User') OVER (ORDER BY dus.UserCreationDate) AS NextUserDisplayName,
  dus.LastPostDate,
  dus.LastCommentDate,
  dus.LastVoteDate,
  dus.LastBadgeDate,
  dus.LastHistoryEntryDate,
  dus.LastPostHistoryTypeName,
  CASE
    WHEN dus.WebsiteUrl IS NOT NULL AND LENGTH(dus.WebsiteUrl) > 5 THEN 'Has Website'
    ELSE 'No Website'
  END AS HasWebsite,
  SUBSTRING(COALESCE(dus.AboutMe, 'No description'), 1, 50) AS AboutMeSnippet,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = dus.UserId AND p2.ClosedDate IS NOT NULL
    ) THEN 'HasClosedPosts'
    ELSE 'NoClosedPosts'
  END AS PostClosureStatus,
  (
    SELECT COUNT(*) FROM Comments c2 WHERE c2.UserId = dus.UserId AND c2.Score < 0
  ) AS NegativeScoreCommentCount,
  (
    SELECT COUNT(*) FROM Votes v2 WHERE v2.UserId = dus.UserId AND v2.VoteTypeId = 3
  ) AS MyDownVoteCount,
  CASE
    WHEN EXISTS (SELECT 1 FROM Badges b2 WHERE b2.UserId = dus.UserId AND b2.Name = 'Editor') THEN 'HasEditorBadge'
    ELSE 'NoEditorBadge'
  END AS EditorBadgeStatus,
  CASE
    WHEN dus.UserCreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months') AND COALESCE(dus.EditsMade, 0) < 5 THEN 'InactiveLongTerm'
    WHEN dus.UserCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months') AND COALESCE(dus.TotalPosts, 0) < 10 THEN 'NewishLowActivity'
    ELSE 'Regular Activity Profile'
  END AS ActivityProfileType,
  (
    SELECT SUM(p3.Score) FROM Posts p3 WHERE p3.OwnerUserId = dus.UserId
  ) AS TotalScoreOfAllUserPosts,
  (
    SELECT p4.Title
    FROM Posts p4
    WHERE p4.OwnerUserId = dus.UserId AND p4.PostTypeId = 1
    ORDER BY p4.Score DESC
    FETCH FIRST 1 ROWS ONLY
  ) AS TopQuestionTitle,
  CASE
    WHEN dus.DisplayName LIKE '%?' OR dus.DisplayName LIKE '%!%' THEN 'Contains Punctuation'
    ELSE 'No Special Punctuation'
  END AS DisplayNamePunctuation,
  COALESCE(dus.AvgPostScore, 0) + COALESCE(dus.AvgCommentScore, 0) AS CombinedAvgScore,
  CASE
    WHEN COALESCE(dus.GoldBadgeCount, 0) * 3 + COALESCE(dus.SilverBadgeCount, 0) * 2 + COALESCE(dus.BronzeBadgeCount, 0) > 10 THEN 'High Badge Score'
    ELSE 'Low Badge Score'
  END AS BadgeScoreCategory,
  CASE
    WHEN (
      SELECT COUNT(*) FROM PostLinks pl
      WHERE pl.PostId IN (
        SELECT p5.Id FROM Posts p5 WHERE p5.OwnerUserId = dus.UserId
      ) AND pl.LinkTypeId = 3
    ) > 0 THEN 'HasDuplicateLinks'
    ELSE 'NoDuplicateLinks'
  END AS DuplicateLinkStatus,
  CASE
    WHEN dups.AnswerCount IS NOT NULL AND dups.AnswerCount > 0 THEN (
      SELECT AVG(p6.Score) FROM Posts p6
      WHERE p6.ParentId IN (
        SELECT p7.Id FROM Posts p7 WHERE p7.OwnerUserId = dus.UserId AND p7.PostTypeId = 1
      )
    )
    ELSE NULL
  END AS AvgScoreOfUserAnswersToHisQuestions,
  CASE
    WHEN UPPER(COALESCE(dus.Location, '')) LIKE '%USA%' THEN 'Likely US Based'
    WHEN UPPER(COALESCE(dus.Location, '')) LIKE '%UK%' THEN 'Likely UK Based'
    ELSE 'Location Unspecified or Other'
  END AS LocationRegion
FROM DetailedUserStats dus
LEFT JOIN Users u
  ON dus.UserId = u.Id
LEFT JOIN (
  SELECT
    OwnerUserId,
    COUNT(Id) AS AnswerCount
  FROM Posts
  WHERE
    PostTypeId = 2
  GROUP BY
    OwnerUserId
) dups
  ON dus.UserId = dups.OwnerUserId
WHERE
  dus.Reputation > 0 AND (dus.TotalPosts IS NULL OR dus.TotalPosts > 0) AND (dus.TotalComments IS NULL OR dus.TotalComments > 0)

UNION ALL

SELECT
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  0 AS CalculatedTotalPosts,
  0 AS CalculatedQuestionCount,
  0 AS CalculatedAnswerCount,
  NULL AS AvgPostScore,
  0 AS PostTotalViews,
  0 AS CalculatedTotalComments,
  NULL AS AvgCommentScore,
  0 AS UpVoteCount,
  0 AS DownVoteCount,
  0 AS BountyStartCount,
  0 AS GoldBadgeCount,
  0 AS SilverBadgeCount,
  0 AS BronzeBadgeCount,
  0 AS EditsMade,
  0 AS ModerationActions,
  'New' AS UserExperienceLevel,
  'No Activity' AS ActivityType,
  'Standard User' AS UserImpactCategory,
  'Regular User' AS DisplayNameCategory,
  'Standard Badges' AS BadgeTier,
  0 AS MinActivityMetric,
  0 AS MaxActivityMetric,
  ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RankByReputation,
  'No Previous User' AS PreviousUserDisplayName,
  'No Next User' AS NextUserDisplayName,
  NULL AS LastPostDate,
  NULL AS LastCommentDate,
  NULL AS LastVoteDate,
  NULL AS LastBadgeDate,
  NULL AS LastHistoryEntryDate,
  NULL AS LastPostHistoryTypeName,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND LENGTH(u.WebsiteUrl) > 5 THEN 'Has Website'
    ELSE 'No Website'
  END AS HasWebsite,
  SUBSTRING(COALESCE(u.AboutMe, 'No description'), 1, 50) AS AboutMeSnippet,
  'NoClosedPosts' AS PostClosureStatus,
  0 AS NegativeScoreCommentCount,
  0 AS MyDownVoteCount,
  'NoEditorBadge' AS EditorBadgeStatus,
  'NewishLowActivity' AS ActivityProfileType,
  0 AS TotalScoreOfAllUserPosts,
  NULL AS TopQuestionTitle,
  'No Special Punctuation' AS DisplayNamePunctuation,
  0 AS CombinedAvgScore,
  'Low Badge Score' AS BadgeScoreCategory,
  'NoDuplicateLinks' AS DuplicateLinkStatus,
  NULL AS AvgScoreOfUserAnswersToHisQuestions,
  CASE
    WHEN UPPER(COALESCE(u.Location, '')) LIKE '%USA%' THEN 'Likely US Based'
    WHEN UPPER(COALESCE(u.Location, '')) LIKE '%UK%' THEN 'Likely UK Based'
    ELSE 'Location Unspecified or Other'
  END AS LocationRegion
FROM Users u
WHERE
  u.Id NOT IN (
    SELECT UserId FROM DetailedUserStats
  ) AND u.Reputation > 0;