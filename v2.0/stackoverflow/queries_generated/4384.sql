-- {"query": "4384.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2787} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edits: Title, Body, Tags
  ),
  LatestPostEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS LastEditorUserId,
      rpe.CreationDate AS LastEditDate
    FROM RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
  ),
  UserReputation AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(b.Id) AS BadgeCount
    FROM Users AS u
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.Reputation,
      u.CreationDate
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      COUNT(c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    GROUP BY
      p.Id
  ),
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId AS QuestionOwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount AS QuestionAnswerCount,
      p.FavoriteCount AS QuestionFavoriteCount,
      p.ClosedDate AS QuestionClosedDate,
      pt.Name AS PostTypeName,
      COALESCE(lpe.LastEditDate, p.LastActivityDate) AS LastEditOrActivityDate,
      urs.Reputation AS QuestionOwnerReputation,
      urs.BadgeCount AS QuestionOwnerBadgeCount
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN LatestPostEdits AS lpe
      ON p.Id = lpe.PostId
    LEFT JOIN UserReputation AS urs
      ON p.OwnerUserId = urs.UserId
    WHERE
      p.PostTypeId = 1 -- Questions
  ),
  AnswerDetails AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswerOwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      p.PostTypeId AS AnswerPostTypeId,
      urs.Reputation AS AnswerOwnerReputation,
      urs.BadgeCount AS AnswerOwnerBadgeCount,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn_answer_score
    FROM Posts AS p
    LEFT JOIN UserReputation AS urs
      ON p.OwnerUserId = urs.UserId
    WHERE
      p.PostTypeId = 2 -- Answers
  ),
  AnsweredQuestions AS (
    SELECT
      qd.QuestionId,
      qd.QuestionTitle,
      qd.QuestionOwnerUserId,
      qd.QuestionCreationDate,
      qd.QuestionScore,
      qd.QuestionAnswerCount,
      qd.QuestionFavoriteCount,
      qd.QuestionClosedDate,
      qd.PostTypeName,
      qd.LastEditOrActivityDate,
      qd.QuestionOwnerReputation,
      qd.QuestionOwnerBadgeCount,
      MAX(CASE WHEN ad.rn_answer_score = 1 THEN ad.AnswerId ELSE NULL END) AS BestAnswerId,
      MAX(CASE WHEN ad.rn_answer_score = 1 THEN ad.AnswerScore ELSE NULL END) AS BestAnswerScore,
      MAX(CASE WHEN ad.rn_answer_score = 1 THEN ad.AnswerOwnerReputation ELSE NULL END) AS BestAnswerOwnerReputation,
      COUNT(ad.AnswerId) AS TotalAnswerCount,
      AVG(ad.AnswerScore) AS AverageAnswerScore,
      SUM(CASE WHEN ad.AnswerPostTypeId = 2 THEN 1 ELSE 0 END) AS ActualAnswerCount -- Ensure we only count answers
    FROM QuestionDetails AS qd
    LEFT JOIN AnswerDetails AS ad
      ON qd.QuestionId = ad.QuestionId
    GROUP BY
      qd.QuestionId,
      qd.QuestionTitle,
      qd.QuestionOwnerUserId,
      qd.QuestionCreationDate,
      qd.QuestionScore,
      qd.QuestionAnswerCount,
      qd.QuestionFavoriteCount,
      qd.QuestionClosedDate,
      qd.PostTypeName,
      qd.LastEditOrActivityDate,
      qd.QuestionOwnerReputation,
      qd.QuestionOwnerBadgeCount
  ),
  LinkedPosts AS (
    SELECT
      pl.PostId,
      pl.RelatedPostId,
      lt.Name AS LinkType
    FROM PostLinks AS pl
    JOIN LinkTypes AS lt
      ON pl.LinkTypeId = lt.Id
  )
SELECT
  aq.QuestionId,
  aq.QuestionTitle,
  aq.QuestionOwnerUserId,
  ur.DisplayName AS QuestionOwnerDisplayName,
  aq.QuestionCreationDate,
  aq.QuestionScore,
  aq.QuestionAnswerCount,
  aq.QuestionFavoriteCount,
  aq.QuestionClosedDate,
  aq.PostTypeName,
  aq.LastEditOrActivityDate,
  aq.QuestionOwnerReputation,
  aq.QuestionOwnerBadgeCount,
  aq.BestAnswerId,
  aq.BestAnswerScore,
  aq.BestAnswerOwnerReputation,
  aq.TotalAnswerCount,
  aq.AverageAnswerScore,
  aq.ActualAnswerCount,
  pe.CommentCount AS QuestionCommentCount,
  pe.UpVoteCount AS QuestionUpVoteCount,
  pe.DownVoteCount AS QuestionDownVoteCount,
  CASE
    WHEN aq.QuestionClosedDate IS NOT NULL THEN 'Closed'
    WHEN aq.QuestionScore > 100 THEN 'High Score'
    WHEN aq.QuestionFavoriteCount > 50 THEN 'Popular'
    WHEN aq.QuestionAnswerCount > 10 THEN 'Answered'
    ELSE 'Standard'
  END AS QuestionStatusCategory,
  lp1.RelatedPostId AS DuplicateOfPostId,
  lp1.LinkType AS DuplicateLinkType,
  lp2.RelatedPostId AS LinkedToPostId,
  lp2.LinkType AS LinkedLinkType,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c_sub
    WHERE
      c_sub.PostId = aq.QuestionId AND c_sub.UserId = aq.QuestionOwnerUserId
  ) AS OwnerCommentCount,
  (
    SELECT
      SUM(CASE WHEN v_sub.VoteTypeId = 2 THEN 1 ELSE 0 END)
    FROM Votes AS v_sub
    WHERE
      v_sub.PostId = aq.QuestionId AND v_sub.UserId = aq.QuestionOwnerUserId
  ) AS OwnerUpVoteCount,
  CASE
    WHEN aq.QuestionOwnerReputation IS NULL THEN 'Unknown'
    WHEN aq.QuestionOwnerReputation >= 100000 THEN 'Legendary'
    WHEN aq.QuestionOwnerReputation >= 50000 THEN 'Expert'
    WHEN aq.QuestionOwnerReputation >= 10000 THEN 'Experienced'
    WHEN aq.QuestionOwnerReputation >= 1000 THEN 'Proficient'
    ELSE 'Novice'
  END AS OwnerReputationTier
FROM AnsweredQuestions AS aq
LEFT JOIN Users AS ur
  ON aq.QuestionOwnerUserId = ur.Id
LEFT JOIN PostEngagement AS pe
  ON aq.QuestionId = pe.PostId
LEFT JOIN LinkedPosts AS lp1
  ON aq.QuestionId = lp1.PostId AND lp1.LinkType = 'Duplicate'
LEFT JOIN LinkedPosts AS lp2
  ON aq.QuestionId = lp2.PostId AND lp2.LinkType <> 'Duplicate'
WHERE
  aq.QuestionScore > 0
  AND aq.QuestionCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND aq.QuestionOwnerReputation > 100
  AND LOWER(aq.QuestionTitle) LIKE '%performance%'
UNION ALL
SELECT
  aq.QuestionId,
  aq.QuestionTitle,
  aq.QuestionOwnerUserId,
  ur.DisplayName AS QuestionOwnerDisplayName,
  aq.QuestionCreationDate,
  aq.QuestionScore,
  aq.QuestionAnswerCount,
  aq.QuestionFavoriteCount,
  aq.QuestionClosedDate,
  aq.PostTypeName,
  aq.LastEditOrActivityDate,
  aq.QuestionOwnerReputation,
  aq.QuestionOwnerBadgeCount,
  aq.BestAnswerId,
  aq.BestAnswerScore,
  aq.BestAnswerOwnerReputation,
  aq.TotalAnswerCount,
  aq.AverageAnswerScore,
  aq.ActualAnswerCount,
  pe.CommentCount AS QuestionCommentCount,
  pe.UpVoteCount AS QuestionUpVoteCount,
  pe.DownVoteCount AS QuestionDownVoteCount,
  CASE
    WHEN aq.QuestionClosedDate IS NOT NULL THEN 'Closed'
    WHEN aq.QuestionScore > 100 THEN 'High Score'
    WHEN aq.QuestionFavoriteCount > 50 THEN 'Popular'
    WHEN aq.QuestionAnswerCount > 10 THEN 'Answered'
    ELSE 'Standard'
  END AS QuestionStatusCategory,
  lp1.RelatedPostId AS DuplicateOfPostId,
  lp1.LinkType AS DuplicateLinkType,
  lp2.RelatedPostId AS LinkedToPostId,
  lp2.LinkType AS LinkedLinkType,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c_sub
    WHERE
      c_sub.PostId = aq.QuestionId AND c_sub.UserId = aq.QuestionOwnerUserId
  ) AS OwnerCommentCount,
  (
    SELECT
      SUM(CASE WHEN v_sub.VoteTypeId = 2 THEN 1 ELSE 0 END)
    FROM Votes AS v_sub
    WHERE
      v_sub.PostId = aq.QuestionId AND v_sub.UserId = aq.QuestionOwnerUserId
  ) AS OwnerUpVoteCount,
  CASE
    WHEN aq.QuestionOwnerReputation IS NULL THEN 'Unknown'
    WHEN aq.QuestionOwnerReputation >= 100000 THEN 'Legendary'
    WHEN aq.QuestionOwnerReputation >= 50000 THEN 'Expert'
    WHEN aq.QuestionOwnerReputation >= 10000 THEN 'Experienced'
    WHEN aq.QuestionOwnerReputation >= 1000 THEN 'Proficient'
    ELSE 'Novice'
  END AS OwnerReputationTier
FROM AnsweredQuestions AS aq
LEFT JOIN Users AS ur
  ON aq.QuestionOwnerUserId = ur.Id
LEFT JOIN PostEngagement AS pe
  ON aq.QuestionId = pe.PostId
LEFT JOIN LinkedPosts AS lp1
  ON aq.QuestionId = lp1.PostId AND lp1.LinkType = 'Duplicate'
LEFT JOIN LinkedPosts AS lp2
  ON aq.QuestionId = lp2.PostId AND lp2.LinkType <> 'Duplicate'
WHERE
  aq.QuestionAnswerCount > 0
  AND aq.QuestionCreationDate > '2024-01-01'
  AND aq.QuestionOwnerReputation <= 1000
  AND (
    aq.QuestionTitle LIKE '%optimization%' OR aq.QuestionTitle LIKE '%benchmark%'
  )
ORDER BY
  aq.QuestionCreationDate DESC
LIMIT 100;
