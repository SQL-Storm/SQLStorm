-- {"query": "4114.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2170}
WITH
  PostActivity AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate AS PostLastActivityDate,
      p.Score AS PostScore,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      pt.Name AS PostTypeName,
      u.DisplayName AS OwnerDisplayName,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            Comments c
          WHERE
            c.PostId = p.Id AND c.CreationDate > p.CreationDate
        ),
        0
      ) AS CommentCountSinceCreation,
      COALESCE(
        (
          SELECT
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)  -- UpMod
            - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) -- DownMod
          FROM
            Votes v
          WHERE
            v.PostId = p.Id
        ),
        0
      ) AS NetVotes
    FROM
      Posts p
      JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
      LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
  ),
  UserContribution AS (
    SELECT
      ua.Id AS UserId,
      ua.DisplayName AS UserDisplayName,
      COUNT(DISTINCT pa.PostId) AS TotalPosts,
      SUM(pa.PostScore) AS TotalScore,
      AVG(pa.PostScore) AS AvgScore,
      SUM(pa.CommentCount) AS TotalComments,
      SUM(pa.FavoriteCount) AS TotalFavorites,
      SUM(pa.AnswerCount) AS TotalAnswersGiven,
      MAX(ua.Reputation) AS MaxReputation,
      MIN(ua.CreationDate) AS UserFirstCreationDate,
      COUNT(DISTINCT b.Id) AS TotalBadges,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
      AVG(pa.NetVotes) AS AvgNetVotes,
      SUM(pa.IsClosed) AS PostsClosed,
      (
        SELECT
          COUNT(*)
        FROM
          PostHistory ph
        WHERE
          ph.UserId = ua.Id AND ph.PostHistoryTypeId = 16 -- Community Owned
      ) AS CommunityOwnedCount
    FROM
      Users ua
      JOIN PostActivity pa
      ON ua.Id = pa.OwnerUserId
      LEFT JOIN Badges b
      ON ua.Id = b.UserId
    GROUP BY
      ua.Id,
      ua.DisplayName
  ),
  PostHistoryAnalysis AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      pht.Name AS HistoryTypeName,
      ph.CreationDate AS HistoryCreationDate,
      EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate)) AS TimeSincePostCreation,
      CASE
        WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 'Initial'
        WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 'Edit'
        WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 'Rollback'
        WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 'ModerationAction'
        WHEN ph.PostHistoryTypeId IN (35, 36) THEN 'Migration'
        ELSE 'Other'
      END AS HistoryCategory,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS RevisionNumber,
      LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryDate,
      ph.CreationDate AS pha_CreationDate -- include for grouping/window use
    FROM
      PostHistory ph
      JOIN PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
      JOIN Posts p
      ON ph.PostId = p.Id
    WHERE
      ph.UserId IS NOT NULL
  ),
  AggregatedPostHistory AS (
    SELECT
      pha.PostId,
      COUNT(DISTINCT pha.UserId) AS DistinctEditors,
      SUM(CASE WHEN pha.HistoryCategory = 'Edit' THEN 1 ELSE 0 END) AS TotalEdits,
      SUM(CASE WHEN pha.HistoryCategory = 'ModerationAction' THEN 1 ELSE 0 END) AS TotalModerationActions,
      AVG(pha.TimeSincePostCreation) AS AvgTimeSincePostCreation,
      MAX(pha.RevisionNumber) AS TotalRevisions,
      SUM(CASE WHEN pha.HistoryTypeName LIKE '%Title%' THEN 1 ELSE 0 END) AS TitleChanges,
      SUM(CASE WHEN pha.HistoryTypeName LIKE '%Body%' THEN 1 ELSE 0 END) AS BodyChanges,
      SUM(CASE WHEN pha.HistoryTypeName LIKE '%Tags%' THEN 1 ELSE 0 END) AS TagChanges,
      AVG(EXTRACT(EPOCH FROM (pha.pha_CreationDate - pha.PreviousHistoryDate))) AS AvgTimeBetweenEdits
    FROM
      PostHistoryAnalysis pha
    GROUP BY
      pha.PostId
  )
SELECT
  pa.PostId,
  pa.PostTypeId,
  pa.PostTypeName,
  pa.PostCreationDate,
  pa.PostLastActivityDate,
  pa.PostScore,
  pa.CommentCount,
  pa.FavoriteCount,
  pa.IsClosed,
  pa.OwnerDisplayName,
  pa.CommentCountSinceCreation,
  pa.NetVotes,
  uc.UserDisplayName AS TopContributorDisplayName,
  uc.TotalPosts AS TopContributorTotalPosts,
  uc.TotalScore AS TopContributorTotalScore,
  uc.AvgScore AS TopContributorAvgScore,
  uc.TotalComments AS TopContributorTotalComments,
  uc.TotalFavorites AS TopContributorTotalFavorites,
  uc.TotalBadges AS TopContributorTotalBadges,
  uc.GoldBadges AS TopContributorGoldBadges,
  uc.SilverBadges AS TopContributorSilverBadges,
  uc.BronzeBadges AS TopContributorBronzeBadges,
  uc.AvgNetVotes AS TopContributorAvgNetVotes,
  uc.PostsClosed AS TopContributorPostsClosed,
  uc.CommunityOwnedCount AS TopContributorCommunityOwnedCount,
  COALESCE(aph.DistinctEditors, 0) AS PostDistinctEditors,
  COALESCE(aph.TotalEdits, 0) AS PostTotalEdits,
  COALESCE(aph.TotalModerationActions, 0) AS PostTotalModerationActions,
  aph.AvgTimeSincePostCreation,
  aph.TotalRevisions,
  aph.TitleChanges,
  aph.BodyChanges,
  aph.TagChanges,
  aph.AvgTimeBetweenEdits,
  (pa.PostTypeName || ' by ' || COALESCE(pa.OwnerDisplayName, 'Community')) AS PostSummary,
  CASE
    WHEN pa.PostScore > 100 THEN 'High Score'
    WHEN pa.PostScore > 0 THEN 'Positive Score'
    WHEN pa.PostScore < 0 THEN 'Negative Score'
    ELSE 'Zero Score'
  END AS ScoreCategory,
  (pa.PostLastActivityDate - pa.PostCreationDate) AS PostLifespan,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks pl
    WHERE
      pl.PostId = pa.PostId AND pl.LinkTypeId = 3 -- Duplicate
  ) AS DuplicateLinksToThisPost,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks pl
    WHERE
      pl.RelatedPostId = pa.PostId AND pl.LinkTypeId = 3 -- Duplicate
  ) AS DuplicateLinksFromThisPost,
  COALESCE(pa.AnswerCount, 0) + COALESCE(pa.CommentCount, 0) AS TotalInteractions
FROM
  PostActivity pa
  LEFT JOIN UserContribution uc
  ON pa.OwnerUserId = uc.UserId
  LEFT JOIN AggregatedPostHistory aph
  ON pa.PostId = aph.PostId
WHERE
  pa.PostCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  AND pa.PostScore > 0
  AND (
    pa.OwnerDisplayName IS NULL OR CHAR_LENGTH(pa.OwnerDisplayName) > 5
  )
  AND EXISTS (
    SELECT
      1
    FROM
      Tags t
    WHERE
      pa.PostTypeId = 1 -- Only for questions
      AND pa.PostId IN (
        SELECT
          p.Id
        FROM
          Posts p
        WHERE
          p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<performance>%')
  )
ORDER BY
  pa.PostScore DESC,
  pa.PostLastActivityDate DESC
LIMIT 100;