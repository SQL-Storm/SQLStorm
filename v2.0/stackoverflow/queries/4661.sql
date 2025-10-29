-- {"query": "4661.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2674}
WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      p.PostTypeId,
      COUNT(p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
      SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId,
      p.PostTypeId
  ),
  UserEngagement AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      SUM(c.Score) AS TotalCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE
      c.UserId IS NOT NULL AND c.UserId <> -1
    GROUP BY
      c.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id END) AS UpVoteCount,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id END) AS DownVoteCount,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN v.Id END) AS FavoriteCount,
      MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  UserBadgeSummary AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgeCount,
      COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadgeCount,
      COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadgeCount,
      MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY
      b.UserId
  ),
  UserPostHistory AS (
    SELECT
      ph.UserId,
      COUNT(ph.Id) AS PostHistoryCount,
      MAX(ph.CreationDate) AS LastPostHistoryDate
    FROM PostHistory ph
    WHERE
      ph.UserId IS NOT NULL AND ph.UserId <> -1
    GROUP BY
      ph.UserId
  ),
  UserPostLinkActivity AS (
    SELECT
      pl.PostId,
      COUNT(pl.Id) AS PostLinkCount
    FROM PostLinks pl
    GROUP BY
      pl.PostId
  ),
  UserReputationChange AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      LAG(u.Reputation, 1, u.Reputation) OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate) AS PreviousReputation,
      u.CreationDate,
      u.LastAccessDate
    FROM Users u
  ),
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.ViewCount,
      p.AnswerCount,
      p.Score,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore,
      DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS OwnerViewRank,
      (
        SELECT
          COUNT(*)
        FROM PostLinks pl
        WHERE
          pl.PostId = p.Id AND pl.LinkTypeId = 3
      ) AS DuplicateLinkCount
    FROM Posts p
    WHERE
      p.PostTypeId = 1
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE u.WebsiteUrl END AS WebsiteStatus,
  SUBSTRING(u.AboutMe FROM 1 FOR 50) AS AboutMeSnippet,
  COALESCE(UQS.GoldBadgeCount, 0) AS GoldBadges,
  COALESCE(UQS.SilverBadgeCount, 0) AS SilverBadges,
  COALESCE(UQS.BronzeBadgeCount, 0) AS BronzeBadges,
  COALESCE(UAQ.PostCount, 0) AS TotalPosts,
  COALESCE(UQ.TotalQuestionViews, 0) AS TotalQuestionViews,
  COALESCE(UA.TotalAnswerScore, 0) AS TotalAnswerScore,
  COALESCE(UE.CommentCount, 0) AS TotalComments,
  COALESCE(UE.TotalCommentScore, 0) AS TotalCommentScore,
  COALESCE(UVS.UpVoteCount, 0) AS TotalUpvotesGiven,
  COALESCE(UVS.DownVoteCount, 0) AS TotalDownvotesGiven,
  COALESCE(UVS.FavoriteCount, 0) AS TotalFavoritesGiven,
  COALESCE(UQ.PostCount, 0) AS QuestionCount,
  COALESCE(UA.PostCount, 0) AS AnswerCount,
  COALESCE(UPH.PostHistoryCount, 0) AS PostHistoryEdits,
  COALESCE(UPHL.PostLinkCount, 0) AS PostsLinkedTo,
  CASE
    WHEN UQR.OwnerViewRank <= 5 THEN 'Top 5 Questioner by Views'
    WHEN UQR.OwnerViewRank <= 10 THEN 'Top 10 Questioner by Views'
    ELSE 'Other'
  END AS QuestionerTier,
  ROUND(
    (
      CAST(u.Views AS NUMERIC) / (
        (EXTRACT(EPOCH FROM cast('2024-10-01 12:34:56' as timestamp)) - EXTRACT(EPOCH FROM u.CreationDate))
      )
    ),
    4
  ) AS ViewsPerSecond,
  CASE
    WHEN URR.Reputation > URR.PreviousReputation THEN 'Increased'
    WHEN URR.Reputation < URR.PreviousReputation THEN 'Decreased'
    ELSE 'Unchanged'
  END AS ReputationChangeStatus,
  (
    SELECT
      COUNT(*)
    FROM Posts p
    WHERE
      p.OwnerUserId = u.Id AND p.ClosedDate IS NOT NULL
  ) AS ClosedPostCount,
  COALESCE(
    (
      SELECT
        SUM(p.AnswerCount)
      FROM Posts p
      WHERE
        p.OwnerUserId = u.Id AND p.PostTypeId = 1
    ),
    0
  ) AS TotalAnswersOnOwnQuestions,
  CASE
    WHEN UQS.LastBadgeDate > UE.LastCommentDate AND UQS.LastBadgeDate > UVS.LastVoteDate THEN 'Badge Activity Dominant'
    WHEN UE.LastCommentDate > UQS.LastBadgeDate AND UE.LastCommentDate > UVS.LastVoteDate THEN 'Comment Activity Dominant'
    WHEN UVS.LastVoteDate > UQS.LastBadgeDate AND UVS.LastVoteDate > UE.LastCommentDate THEN 'Vote Activity Dominant'
    ELSE 'Mixed or No Recent Activity'
  END AS DominantActivityType,
  (
    SELECT
      COUNT(*)
    FROM Posts p
    JOIN PostHistory ph
      ON p.Id = ph.PostId
    WHERE
      p.OwnerUserId = u.Id AND ph.PostHistoryTypeId IN (5, 8) AND ph.Text LIKE '%```sql%'
  ) AS SqlCodeSnippetEdits,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM Posts p
      WHERE
        p.OwnerUserId = u.Id AND p.Title LIKE '%[SQL]%'
    ),
    0
  ) AS TitleContainsSqlTag,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM RankedQuestions rq
      WHERE
        rq.OwnerUserId = u.Id AND rq.DuplicateLinkCount > 0
    ),
    0
  ) AS QuestionsWithDuplicateLinks,
  COALESCE(
    (
      SELECT
        MAX(p.Score)
      FROM Posts p
      WHERE
        p.OwnerUserId = u.Id AND p.PostTypeId = 1
    ),
    0
  ) AS HighestScoringQuestionScore
FROM Users u
LEFT JOIN UserPostActivity UQA
  ON u.Id = UQA.OwnerUserId AND UQA.PostTypeId = 1
LEFT JOIN UserPostActivity UQA_A
  ON u.Id = UQA_A.OwnerUserId AND UQA_A.PostTypeId = 2
LEFT JOIN UserEngagement UE
  ON u.Id = UE.UserId
LEFT JOIN UserVoteStats UVS
  ON u.Id = UVS.UserId
LEFT JOIN UserBadgeSummary UQS
  ON u.Id = UQS.UserId
LEFT JOIN UserPostHistory UPH
  ON u.Id = UPH.UserId
LEFT JOIN (
  SELECT
    OwnerUserId,
    SUM(PostCount) AS PostCount
  FROM UserPostActivity
  GROUP BY
    OwnerUserId
) UAQ
  ON u.Id = UAQ.OwnerUserId
LEFT JOIN (
  SELECT
    OwnerUserId,
    PostCount,
    TotalQuestionViews
  FROM UserPostActivity
  WHERE
    PostTypeId = 1
) UQ
  ON u.Id = UQ.OwnerUserId
LEFT JOIN (
  SELECT
    OwnerUserId,
    PostCount,
    TotalAnswerScore
  FROM UserPostActivity
  WHERE
    PostTypeId = 2
) UA
  ON u.Id = UA.OwnerUserId
LEFT JOIN UserReputationChange URR
  ON u.Id = URR.UserId
LEFT JOIN RankedQuestions UQR
  ON u.Id = UQR.OwnerUserId
LEFT JOIN (
  SELECT
    pl.RelatedPostId,
    COUNT(pl.Id) AS PostLinkCount
  FROM PostLinks pl
  WHERE
    pl.LinkTypeId = 1
  GROUP BY
    pl.RelatedPostId
) UPHL
  ON u.Id = UPHL.RelatedPostId
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.WebsiteUrl,
  u.AboutMe,
  UQS.GoldBadgeCount,
  UQS.SilverBadgeCount,
  UQS.BronzeBadgeCount,
  UAQ.PostCount,
  UQ.TotalQuestionViews,
  UA.TotalAnswerScore,
  UE.CommentCount,
  UE.TotalCommentScore,
  UVS.UpVoteCount,
  UVS.DownVoteCount,
  UVS.FavoriteCount,
  UQ.PostCount,
  UA.PostCount,
  UPH.PostHistoryCount,
  UPHL.PostLinkCount,
  UQR.OwnerViewRank,
  u.Views,
  URR.Reputation,
  URR.PreviousReputation,
  URR.CreationDate,
  URR.LastAccessDate,
  UQS.LastBadgeDate,
  UE.LastCommentDate,
  UVS.LastVoteDate
ORDER BY
  u.Reputation DESC
LIMIT 100;