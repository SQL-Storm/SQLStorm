-- {"query": "18049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1691} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      u.DisplayName AS EditorDisplayName,
      ph.PostHistoryTypeId,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    JOIN
      Users AS u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  LatestEdits AS (
    SELECT
      PostId,
      UserId,
      EditorDisplayName,
      PostHistoryTypeId,
      EditDate
    FROM
      RankedPostEdits
    WHERE
      rn = 1
  ),
  PostEditCounts AS (
    SELECT
      ph.PostId,
      COUNT(DISTINCT ph.RevisionGUID) AS EditCount
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      ph.PostId
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgPostScore
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  UserBadgeSummary AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM
      Badges AS b
    GROUP BY
      b.UserId
  ),
  ComplexPostDetails AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      pt.Name AS PostTypeName,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      COALESCE(CAST(p.ClosedDate AS VARCHAR), 'Not Closed') AS CloseStatus,
      le.EditorDisplayName AS LastEditorDisplayName,
      le.EditDate AS LastEditDate,
      pec.EditCount AS TotalEdits,
      CONCAT(
        COALESCE(CAST(upa.QuestionCount AS VARCHAR), '0'),
        ' Q / ',
        COALESCE(CAST(upa.AnswerCount AS VARCHAR), '0'),
        ' A'
      ) AS UserPostSummary,
      COALESCE(ubs.GoldBadges, 0) AS UserGoldBadges,
      COALESCE(ubs.SilverBadges, 0) AS UserSilverBadges,
      COALESCE(ubs.BronzeBadges, 0) AS UserBronzeBadges,
      CASE
        WHEN p.OwnerUserId IS NOT NULL AND p.OwnerUserId = p.LastEditorUserId THEN 'Self-Edited'
        WHEN p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> p.LastEditorUserId THEN 'EditedByOther'
        ELSE 'NoEditsOrCommunity'
      END AS EditOwnershipType,
      CASE
        WHEN p.Title LIKE '%how%' OR p.Title LIKE '%what%' OR p.Title LIKE '%why%' THEN 'Inquisitive'
        WHEN p.Title LIKE '%question%' THEN 'DirectQuestion'
        ELSE 'Statement'
      END AS TitleQuestionType,
      ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS ActivityRank
    FROM
      Posts AS p
    JOIN
      PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN
      Users AS u
      ON p.OwnerUserId = u.Id
    LEFT JOIN
      LatestEdits AS le
      ON p.Id = le.PostId
    LEFT JOIN
      PostEditCounts AS pec
      ON p.Id = pec.PostId
    LEFT JOIN
      UserPostActivity AS upa
      ON p.OwnerUserId = upa.OwnerUserId
    LEFT JOIN
      UserBadgeSummary AS ubs
      ON p.OwnerUserId = ubs.UserId
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers only
      AND p.CreationDate >= '2023-01-01' -- Filter for recent posts
      AND p.Score > 0
      AND p.ViewCount > 100
  )
SELECT
  cpd.PostId,
  cpd.Title,
  cpd.PostTypeName,
  cpd.PostCreationDate,
  cpd.PostScore,
  cpd.PostViewCount,
  cpd.PostAnswerCount,
  cpd.PostCommentCount,
  cpd.PostFavoriteCount,
  cpd.OwnerDisplayName,
  cpd.OwnerReputation,
  cpd.CloseStatus,
  cpd.LastEditorDisplayName,
  cpd.LastEditDate,
  cpd.TotalEdits,
  cpd.UserPostSummary,
  cpd.UserGoldBadges,
  cpd.UserSilverBadges,
  cpd.UserBronzeBadges,
  cpd.EditOwnershipType,
  cpd.TitleQuestionType,
  CASE
    WHEN cpd.ActivityRank BETWEEN 1 AND 100 THEN 'Top 100 Active'
    WHEN cpd.ActivityRank BETWEEN 101 AND 500 THEN 'Next 400 Active'
    ELSE 'Other Activity'
  END AS ActivityTier
FROM
  ComplexPostDetails AS cpd
WHERE
  cpd.OwnerReputation > 1000
  OR cpd.TotalEdits > 5
UNION
SELECT
  NULL,
  '--- Summary ---',
  NULL,
  NULL,
  NULL,
  NULL,
  COUNT(CASE WHEN PostTypeName = 'Question' THEN 1 END),
  COUNT(CASE WHEN PostTypeName = 'Answer' THEN 1 END),
  AVG(CAST(PostFavoriteCount AS DECIMAL)),
  NULL,
  AVG(CAST(OwnerReputation AS DECIMAL)),
  NULL,
  NULL,
  NULL,
  AVG(CAST(TotalEdits AS DECIMAL)),
  NULL,
  AVG(CAST(UserGoldBadges AS DECIMAL)),
  AVG(CAST(UserSilverBadges AS DECIMAL)),
  AVG(CAST(UserBronzeBadges AS DECIMAL)),
  NULL,
  NULL,
  NULL
FROM
  ComplexPostDetails AS cpd
WHERE
  cpd.OwnerReputation > 1000
  OR cpd.TotalEdits > 5;
