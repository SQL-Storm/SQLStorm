-- {"query": "4099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1422} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      p.PostTypeId,
      p.AcceptedAnswerId,
      p.ClosedDate,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.FavoriteCount DESC) AS RowNum,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
      AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForPostType,
      SUM(p.ViewCount) OVER () AS TotalViewCount
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.Score > 0
      AND p.CreationDate >= '2023-01-01'
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      p.PostTypeId,
      p.AcceptedAnswerId,
      p.ClosedDate
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
      MAX(ph.CreationDate) AS LastPostHistoryDate,
      COUNT(CASE WHEN pht.Name = 'Edit Body' THEN ph.PostId ELSE NULL END) AS BodyEdits,
      COUNT(CASE WHEN pht.Name = 'Edit Title' THEN ph.PostId ELSE NULL END) AS TitleEdits,
      COUNT(CASE WHEN pht.Name = 'Post Closed' THEN ph.PostId ELSE NULL END) AS CloseVotes
    FROM Users AS u
    INNER JOIN PostHistory AS ph
      ON u.Id = ph.UserId
    INNER JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.CreationDate >= DATE('now', '-365 days')
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      t.Count AS TagPostCount,
      COUNT(p.Id) AS QuestionsWithTag,
      RANK() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags AS t
    LEFT JOIN Posts AS p
      ON ',' + p.Tags + ',' LIKE '%,' + t.TagName + ',%' AND p.PostTypeId = 1
    GROUP BY
      t.TagName,
      t.Count
  ),
  HighScoringQuestions AS (
    SELECT
      rp.PostId,
      rp.Title,
      rp.OwnerUserId,
      rp.Score,
      rp.CommentCountForPost,
      rp.CreationDate,
      rp.AvgScoreForPostType,
      rp.TotalViewCount,
      rp.RowNum,
      rp.PostTypeId,
      rp.AcceptedAnswerId
    FROM RankedPosts AS rp
    WHERE
      rp.RowNum <= 1000 AND rp.PostTypeId = 1
  )
SELECT
  hsq.PostId,
  hsq.Title AS QuestionTitle,
  u.DisplayName AS QuestionOwner,
  hsq.Score,
  hsq.CommentCountForPost,
  hsq.CreationDate,
  hsq.AvgScoreForPostType,
  hsq.TotalViewCount,
  hsq.AcceptedAnswerId,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
  COALESCE(ua.PostHistoryCount, 0) AS UserTotalPostHistory,
  ua.LastPostHistoryDate,
  ua.BodyEdits,
  ua.TitleEdits,
  ua.CloseVotes,
  tp.TagName,
  tp.TagPostCount,
  tp.TagRank,
  CASE
    WHEN hsq.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN hsq.Score > 100 THEN 'Highly Rated'
    WHEN hsq.CommentCountForPost > 50 THEN 'Active Discussion'
    ELSE 'Standard'
  END AS PostStatusCategory
FROM HighScoringQuestions AS hsq
JOIN Users AS u
  ON hsq.OwnerUserId = u.Id
LEFT JOIN Votes AS v
  ON hsq.PostId = v.PostId AND v.VoteTypeId IN (2, 3)
LEFT JOIN UserActivity AS ua
  ON hsq.OwnerUserId = ua.UserId
LEFT JOIN TagPopularity AS tp
  ON ',' + hsq.Tags + ',' LIKE '%,' + tp.TagName + '%' AND tp.TagRank <= 10
WHERE
  u.Reputation > 5000
  AND hsq.Score > hsq.AvgScoreForPostType * 1.5
  AND (hsq.Title LIKE '%SQL%' OR hsq.Title LIKE '%Performance%')
  AND tp.TagRank IS NOT NULL
GROUP BY
  hsq.PostId,
  hsq.Title,
  u.DisplayName,
  hsq.Score,
  hsq.CommentCountForPost,
  hsq.CreationDate,
  hsq.AvgScoreForPostType,
  hsq.TotalViewCount,
  hsq.AcceptedAnswerId,
  ua.PostHistoryCount,
  ua.LastPostHistoryDate,
  ua.BodyEdits,
  ua.TitleEdits,
  ua.CloseVotes,
  tp.TagName,
  tp.TagPostCount,
  tp.TagRank,
  hsq.ClosedDate
HAVING
  COUNT(v.Id) > 0 OR hsq.CommentCountForPost > 0;
