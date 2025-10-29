-- {"query": "5509.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 983} 
WITH Agg AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body,
    p.ContentLicense,
    COALESCE(v1.CntUp,0) AS UpVotes,
    COALESCE(v2.CntDown,0) AS DownVotes,
    COALESCE(bg.BronzeCnt,0) AS BronzeBadges,
    COALESCE(gs.SilverCnt,0) AS SilverBadges,
    COALESCE(gd.GoldCnt,0) AS GoldBadges,
    -- window function: rank questions by score within day
    ROW_NUMBER() OVER (
      PARTITION BY DATE(p.CreationDate)
      ORDER BY p.Score DESC, p.ViewCount DESC
    ) AS DayRank
  FROM
    Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
      AND v.CreationDate = p.CreationDate -- slight correlation to exercise complex predicate
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS CntUp
      FROM Votes
      WHERE VoteTypeId = 2
      GROUP BY PostId
    ) v1 ON v1.PostId = p.Id
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS CntDown
      FROM Votes
      WHERE VoteTypeId = 3
      GROUP BY PostId
    ) v2 ON v2.PostId = p.Id
    LEFT JOIN (
      SELECT OwnerUserId,
             SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt,
             SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
             SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCnt
      FROM Badges
      GROUP BY OwnerUserId
    ) bg ON bg.OwnerUserId = p.OwnerUserId
    LEFT JOIN (
      SELECT UserId, COUNT(*) AS SilverCnt
      FROM Badges
      WHERE Class = 2
      GROUP BY UserId
    ) gs ON gs.UserId = p.OwnerUserId
    LEFT JOIN (
      SELECT UserId, COUNT(*) AS GoldCnt
      FROM Badges
      WHERE Class = 1
      GROUP BY UserId
    ) gd ON gd.UserId = p.OwnerUserId
  WHERE
    p.PostTypeId IN (1,2) -- questions and answers
    AND p.CreationDate >= TIMESTAMP '2020-01-01'
),
Filtered AS (
  SELECT
    a.*,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      ELSE 'Answer'
    END AS Kind,
    CASE
      WHEN a.ParentId IS NULL THEN NULL
      ELSE (SELECT Title FROM Posts WHERE Id = a.ParentId)
    END AS ParentTitle
  FROM Agg a
  JOIN Posts p ON p.Id = a.PostId
),
Computed AS (
  SELECT
    PostId,
    Kind,
    OwnerUserId,
    Title,
    Tags,
    CreationDate,
    LastActivityDate,
    Score,
    ViewCount,
    CommentCount,
    FavoriteCount,
    DayRank,
    BR.BronzeCnt,
    SV.SilverCnt,
    GD.GoldCnt,
    ParentTitle,
    Body,
    ContentLicense
  FROM Filtered
  LEFT JOIN (
    SELECT PostId, BronzeCnt FROM Agg
  ) BR ON BR.PostId = Filtered.PostId
  LEFT JOIN (
    SELECT PostId, SilverCnt FROM Agg
  ) SV ON SV.PostId = Filtered.PostId
  LEFT JOIN (
    SELECT PostId, GoldCnt FROM Agg
  ) GD ON GD.PostId = Filtered.PostId
)
SELECT
  PostId,
  Kind,
  OwnerUserId,
  Title,
  Tags,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  CommentCount,
  FavoriteCount,
  DayRank,
  BronzeCnt,
  SilverCnt,
  GoldCnt,
  ParentTitle,
  SUBSTRING(Body FROM 1 FOR 200) AS Snippet,
  ContentLicense
FROM Computed
WHERE
  (DayRank <= 50)
  AND (Score > 0 OR ViewCount > 100)
  AND (BronzeCnt + SilverCnt + GoldCnt) >= 1
ORDER BY DayRank, PostId;