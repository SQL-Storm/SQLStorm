-- {"query": "4032.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2219} 

WITH
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            Comments c
          WHERE
            c.PostId = p.Id
        ),
        0
      ) AS ActualCommentCount,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            Votes v
          WHERE
            v.PostId = p.Id AND v.VoteTypeId = 2 /* UpMod */
        ),
        0
      ) AS UpVoteCount,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            Votes v
          WHERE
            v.PostId = p.Id AND v.VoteTypeId = 3 /* DownMod */
        ),
        0
      ) AS DownVoteCount,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            PostLinks pl
          WHERE
            pl.PostId = p.Id AND pl.LinkTypeId = 3 /* Duplicate */
        ),
        0
      ) AS DuplicateLinkCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed
    FROM
      Posts p
    WHERE
      p.PostTypeId IN (1, 2) /* Questions and Answers */
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      (
        SELECT
          COUNT(*)
        FROM
          Badges b
        WHERE
          b.UserId = u.Id AND b.Class = 1 /* Gold */
      ) AS GoldBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM
          Badges b
        WHERE
          b.UserId = u.Id AND b.Class = 2 /* Silver */
      ) AS SilverBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM
          Badges b
        WHERE
          b.UserId = u.Id AND b.Class = 3 /* Bronze */
      ) AS BronzeBadgeCount,
      COALESCE(
        (
          SELECT
            COUNT(DISTINCT ph.PostId)
          FROM
            PostHistory ph
          WHERE
            ph.UserId = u.Id AND ph.PostHistoryTypeId IN (2, 5) /* Initial Body, Edit Body */
        ),
        0
      ) AS BodyEditCount
    FROM
      Users u
  ),
  PostAnalysis AS (
    SELECT
      pe.PostId,
      pe.OwnerUserId,
      ua.DisplayName AS OwnerDisplayName,
      ua.Reputation AS OwnerReputation,
      pe.PostTypeId,
      pe.PostCreationDate,
      pe.PostScore,
      pe.PostViewCount,
      pe.PostFavoriteCount,
      pe.PostAnswerCount,
      pe.ActualCommentCount,
      pe.UpVoteCount,
      pe.DownVoteCount,
      pe.DuplicateLinkCount,
      pe.IsClosed,
      ua.GoldBadgeCount,
      ua.SilverBadgeCount,
      ua.BronzeBadgeCount,
      ua.BodyEditCount,
      CASE
        WHEN pe.PostScore > 0 THEN 'Positive'
        WHEN pe.PostScore < 0 THEN 'Negative'
        ELSE 'Neutral'
      END AS ScoreCategory,
      DATEDIFF(
        day,
        pe.PostCreationDate,
        GETDATE()
      ) AS DaysSinceCreation,
      ROW_NUMBER() OVER (
        PARTITION BY
          pe.PostTypeId
        ORDER BY
          pe.PostScore DESC,
          pe.PostFavoriteCount DESC
      ) AS RankByType,
      AVG(pe.PostScore) OVER (PARTITION BY pe.PostTypeId) AS AvgScoreByType,
      SUM(pe.PostViewCount) OVER (PARTITION BY pe.PostTypeId) AS TotalViewsByType,
      COUNT(pe.PostId) OVER (PARTITION BY pe.PostTypeId) AS PostCountByType,
      LAG(pe.PostScore, 1, 0) OVER (ORDER BY pe.PostCreationDate) AS PreviousPostScore,
      LEAD(pe.PostScore, 1, 0) OVER (ORDER BY pe.PostCreationDate) AS NextPostScore,
      CASE
        WHEN ua.UserCreationDate > '2010-01-01' THEN 'Newer User'
        ELSE 'Older User'
      END AS UserAgeGroup,
      ua.UserViews,
      ua.UserUpVotes,
      ua.UserDownVotes,
      pe.PostCreationDate + INTERVAL '1 hour' AS EstimatedEditWindow,
      ua.LastAccessDate AS UserLastAccess,
      CASE
        WHEN ua.LastAccessDate < DATE('now', '-365 day') THEN 'Inactive'
        ELSE 'Active'
      END AS UserActivityStatus
    FROM
      PostEngagement pe
      LEFT OUTER JOIN UserActivity ua ON pe.OwnerUserId = ua.UserId
  )
SELECT
  pa.PostId,
  pa.OwnerUserId,
  pa.OwnerDisplayName,
  pa.OwnerReputation,
  pa.PostTypeId,
  pt.Name AS PostTypeName,
  pa.PostCreationDate,
  pa.PostScore,
  pa.PostViewCount,
  pa.PostFavoriteCount,
  pa.PostAnswerCount,
  pa.ActualCommentCount,
  pa.UpVoteCount,
  pa.DownVoteCount,
  pa.DuplicateLinkCount,
  pa.IsClosed,
  pa.GoldBadgeCount,
  pa.SilverBadgeCount,
  pa.BronzeBadgeCount,
  pa.BodyEditCount,
  pa.ScoreCategory,
  pa.DaysSinceCreation,
  pa.RankByType,
  pa.AvgScoreByType,
  pa.TotalViewsByType,
  pa.PostCountByType,
  pa.PreviousPostScore,
  pa.NextPostScore,
  pa.UserAgeGroup,
  pa.UserViews,
  pa.UserUpVotes,
  pa.UserDownVotes,
  pa.EstimatedEditWindow,
  pa.UserLastAccess,
  pa.UserActivityStatus,
  CONCAT(
    pa.OwnerDisplayName,
    ' - Score: ',
    pa.PostScore,
    ' - Views: ',
    pa.PostViewCount
  ) AS CompositeInfo,
  CASE
    WHEN pa.PostScore > (pa.AvgScoreByType * 1.5)
    AND pa.PostViewCount > (pa.TotalViewsByType * 0.01) THEN 'High Performer'
    WHEN pa.PostScore < (pa.AvgScoreByType * 0.5)
    AND pa.PostViewCount < (pa.TotalViewsByType * 0.001) THEN 'Low Performer'
    ELSE 'Average Performer'
  END AS PerformanceTier,
  pa.PostScore - pa.PreviousPostScore AS ScoreChangeFromPrevious,
  pa.PostScore - pa.NextPostScore AS ScoreChangeFromNext,
  CASE
    WHEN pa.BodyEditCount > 5 THEN 'Frequent Editor'
    ELSE 'Infrequent Editor'
  END AS EditorFrequency,
  CASE
    WHEN pa.DuplicateLinkCount > 0 THEN 'Has Duplicates'
    ELSE 'No Duplicates Found'
  END AS DuplicateStatus,
  pa.PostScore + pa.PostFavoriteCount AS EngagementScore,
  pa.PostViewCount / NULLIF(pa.DaysSinceCreation, 0) AS ViewsPerDay,
  pa.ActualCommentCount * 10 AS CommentImpactFactor,
  CASE
    WHEN pa.IsClosed = 1 THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  CASE
    WHEN pa.OwnerReputation > 10000 THEN 'High Reputation'
    WHEN pa.OwnerReputation < 500 THEN 'Low Reputation'
    ELSE 'Medium Reputation'
  END AS ReputationLevel,
  pa.PostScore + pa.PostAnswerCount AS QAScore,
  pa.PostFavoriteCount / NULLIF(pa.PostAnswerCount, 0) AS FavoriteToAnswerRatio,
  pa.ActualCommentCount / NULLIF(pa.PostAnswerCount, 0) AS CommentToAnswerRatio,
  pa.UpVoteCount * 1.0 / NULLIF(pa.UpVoteCount + pa.DownVoteCount, 0) AS UpvoteRatio,
  CASE
    WHEN pa.UserActivityStatus = 'Inactive' AND pa.PostScore < 10 THEN 'Inactive Owner, Low Score'
    ELSE 'Other'
  END AS InactiveOwnerFlag,
  ua.UserCreationDate
FROM
  PostAnalysis pa
  JOIN PostTypes pt ON pa.PostTypeId = pt.Id
WHERE
  pa.OwnerReputation > 0
  OR pa.OwnerUserId IS NULL /* Handles community-owned posts */
  AND pa.PostScore >= -5
  AND pa.PostViewCount >= 10
ORDER BY
  pa.PostCreationDate DESC
LIMIT 100;
