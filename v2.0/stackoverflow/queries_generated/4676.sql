-- {"query": "4676.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2530} 

WITH
  UserPostInteraction AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      COALESCE(p.Score, 0) AS PostScore,
      COALESCE(p.CommentCount, 0) AS PostCommentCount,
      COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
      COALESCE(p.AnswerCount, 0) AS PostAnswerCount,
      COALESCE(p.ViewCount, 0) AS PostViewCount,
      u.Reputation AS UserReputation,
      u.CreationDate AS UserCreationDate,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      (
        SELECT
          COUNT(*)
        FROM
          Comments c
        WHERE
          c.UserId = p.OwnerUserId
      ) AS UserCommentCount,
      (
        SELECT
          COUNT(*)
        FROM
          Badges b
        WHERE
          b.UserId = p.OwnerUserId
          AND b.Class = 1
      ) AS UserGoldBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM
          Badges b
        WHERE
          b.UserId = p.OwnerUserId
          AND b.Class = 2
      ) AS UserSilverBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM
          Votes v
        WHERE
          v.UserId = p.OwnerUserId
          AND v.VoteTypeId = 2
      ) AS UserUpVoteCount,
      (
        SELECT
          COUNT(*)
        FROM
          Votes v
        WHERE
          v.UserId = p.OwnerUserId
          AND v.VoteTypeId = 3
      ) AS UserDownVoteCount,
      (
        SELECT
          SUM(COALESCE(c.Score, 0))
        FROM
          Comments c
        WHERE
          c.UserId = p.OwnerUserId
      ) AS UserTotalCommentScore,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostSequence
    FROM
      Posts p
      LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
  ),
  PostEngagementMetrics AS (
    SELECT
      upi.PostId,
      upi.OwnerUserId,
      upi.PostTypeId,
      upi.PostCreationDate,
      upi.PostScore,
      upi.PostCommentCount,
      upi.PostFavoriteCount,
      upi.PostAnswerCount,
      upi.PostViewCount,
      upi.UserReputation,
      upi.UserCreationDate,
      upi.UserUpVotes,
      upi.UserDownVotes,
      upi.UserCommentCount,
      upi.UserGoldBadgeCount,
      upi.UserSilverBadgeCount,
      upi.UserUpVoteCount,
      upi.UserDownVoteCount,
      upi.UserTotalCommentScore,
      upi.UserPostSequence,
      (
        SELECT
          AVG(COALESCE(c.Score, 0))
        FROM
          Comments c
        WHERE
          c.PostId = upi.PostId
      ) AS AvgCommentScoreOnPost,
      (
        SELECT
          COUNT(*)
        FROM
          Votes v
        WHERE
          v.PostId = upi.PostId
          AND v.VoteTypeId = 2
      ) AS UpVoteCountOnPost,
      (
        SELECT
          COUNT(*)
        FROM
          Votes v
        WHERE
          v.PostId = upi.PostId
          AND v.VoteTypeId = 3
      ) AS DownVoteCountOnPost,
      (
        SELECT
          COUNT(DISTINCT pl.RelatedPostId)
        FROM
          PostLinks pl
        WHERE
          pl.PostId = upi.PostId
          AND pl.LinkTypeId = 1
      ) AS LinkedPostsCount,
      (
        SELECT
          COUNT(DISTINCT pl.RelatedPostId)
        FROM
          PostLinks pl
        WHERE
          pl.PostId = upi.PostId
          AND pl.LinkTypeId = 3
      ) AS DuplicateLinksCount,
      CASE
        WHEN upi.PostCreationDate < DATE('now', '-1 year') THEN 'Old'
        WHEN upi.PostCreationDate BETWEEN DATE('now', '-1 year') AND DATE('now', '-3 months') THEN 'Medium'
        ELSE 'Recent'
      END AS PostAgeCategory,
      SUBSTRING(pht.Name FROM 1 FOR 1) AS FirstLetterOfPostHistoryTypeName,
      CASE
        WHEN pht.Id IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 'ModAction'
        WHEN pht.Id IN (1, 2, 3, 4, 5, 6, 7, 8, 9) THEN 'ContentEdit'
        ELSE 'Other'
      END AS PostHistoryTypeCategory
    FROM
      UserPostInteraction upi
      LEFT JOIN PostHistory ph ON upi.PostId = ph.PostId
      LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  )
SELECT
  pem.PostId,
  pem.OwnerUserId,
  pem.PostTypeId,
  pem.PostCreationDate,
  pem.PostScore,
  pem.PostCommentCount,
  pem.PostFavoriteCount,
  pem.PostAnswerCount,
  pem.PostViewCount,
  pem.UserReputation,
  pem.UserCreationDate,
  pem.UserUpVotes,
  pem.UserDownVotes,
  pem.UserCommentCount,
  pem.UserGoldBadgeCount,
  pem.UserSilverBadgeCount,
  pem.UserUpVoteCount,
  pem.UserDownVoteCount,
  pem.UserTotalCommentScore,
  pem.UserPostSequence,
  pem.AvgCommentScoreOnPost,
  pem.UpVoteCountOnPost,
  pem.DownVoteCountOnPost,
  pem.LinkedPostsCount,
  pem.DuplicateLinksCount,
  pem.PostAgeCategory,
  pem.FirstLetterOfPostHistoryTypeName,
  pem.PostHistoryTypeCategory,
  CASE
    WHEN pem.UserReputation > 100000 THEN 'Legendary'
    WHEN pem.UserReputation > 50000 THEN 'Expert'
    WHEN pem.UserReputation > 10000 THEN 'Advanced'
    WHEN pem.UserReputation > 1000 THEN 'Intermediate'
    ELSE 'Beginner'
  END AS UserReputationTier,
  CASE
    WHEN pem.PostScore < 0 THEN 'Negative'
    WHEN pem.PostScore BETWEEN 0 AND 10 THEN 'Low'
    WHEN pem.PostScore BETWEEN 11 AND 100 THEN 'Medium'
    ELSE 'High'
  END AS PostScoreTier,
  COALESCE(NULLIF(TRIM(pem.PostAgeCategory), ''), 'Unknown') AS CleanedPostAgeCategory,
  UPPER(SUBSTRING(CAST(pem.PostCreationDate AS VARCHAR), 1, 7)) AS PostYearMonth,
  CASE
    WHEN pem.UserGoldBadgeCount >= 10 THEN 'Many Gold'
    WHEN pem.UserGoldBadgeCount >= 1 THEN 'Some Gold'
    ELSE 'No Gold'
  END AS GoldBadgeStatus,
  CASE
    WHEN (pem.UserUpVoteCount + pem.UserDownVoteCount) > 0 THEN CAST(pem.UserUpVoteCount AS REAL) / (pem.UserUpVoteCount + pem.UserDownVoteCount)
    ELSE 0
  END AS UpVoteRatio,
  CASE
    WHEN pem.PostFavoriteCount IS NULL THEN 0
    ELSE pem.PostFavoriteCount
  END AS NonNullFavoriteCount,
  CASE
    WHEN pem.PostAnswerCount > 0 AND pem.PostScore > 0 THEN CAST(pem.PostAnswerCount AS REAL) / pem.PostScore
    ELSE 0
  END AS AnswerToScoreRatio,
  CASE
    WHEN pem.PostTypeId = 1 THEN 'Question'
    WHEN pem.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS DetailedPostType,
  CASE
    WHEN pem.PostCreationDate < pem.UserCreationDate THEN 'Post Before User' -- Should not happen, but for robustness
    WHEN pem.PostCreationDate >= pem.UserCreationDate AND pem.PostCreationDate < DATE(pem.UserCreationDate, '+1 day') THEN 'Same Day'
    WHEN pem.PostCreationDate < DATE(pem.UserCreationDate, '+7 days') THEN 'Within Week'
    WHEN pem.PostCreationDate < DATE(pem.UserCreationDate, '+30 days') THEN 'Within Month'
    ELSE 'Later'
  END AS PostRelativeToUserCreation,
  CASE
    WHEN ph.PostHistoryTypeId = 10 THEN 'Closed'
    WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
    WHEN ph.PostHistoryTypeId = 12 THEN 'Deleted'
    WHEN ph.PostHistoryTypeId = 13 THEN 'Undeleted'
    WHEN ph.PostHistoryTypeId = 16 THEN 'CommunityOwned'
    ELSE 'OtherHistory'
  END AS SpecificPostHistoryType
FROM
  PostEngagementMetrics pem
LEFT JOIN
  PostHistory ph ON pem.PostId = ph.PostId
WHERE
  pem.PostCreationDate > '2010-01-01'
  AND pem.UserReputation > 100
  AND pem.PostScore > -5
  AND pem.PostCommentCount BETWEEN 0 AND 50
GROUP BY
  pem.PostId,
  pem.OwnerUserId,
  pem.PostTypeId,
  pem.PostCreationDate,
  pem.PostScore,
  pem.PostCommentCount,
  pem.PostFavoriteCount,
  pem.PostAnswerCount,
  pem.PostViewCount,
  pem.UserReputation,
  pem.UserCreationDate,
  pem.UserUpVotes,
  pem.UserDownVotes,
  pem.UserCommentCount,
  pem.UserGoldBadgeCount,
  pem.UserSilverBadgeCount,
  pem.UserUpVoteCount,
  pem.UserDownVoteCount,
  pem.UserTotalCommentScore,
  pem.UserPostSequence,
  pem.AvgCommentScoreOnPost,
  pem.UpVoteCountOnPost,
  pem.DownVoteCountOnPost,
  pem.LinkedPostsCount,
  pem.DuplicateLinksCount,
  pem.PostAgeCategory,
  pem.FirstLetterOfPostHistoryTypeName,
  pem.PostHistoryTypeCategory
ORDER BY
  pem.PostCreationDate DESC
LIMIT 1000;
