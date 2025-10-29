-- {"query": "5002.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 819} 
WITH RankedPosts AS (
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
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.CreateDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.WebsiteUrl,
    u.EmailHash,
    u.AccountId,
    -- Subqueries / expressions
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentDensity,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AvgBounty,
    (SELECT STRING_AGG(t.Name, ',') FROM (
        SELECT CASE
                 WHEN pt.Name IS NOT NULL THEN pt.Name
                 ELSE NULL
               END AS Name
         FROM UNNEST(string_to_array(p.Tags, '><')) AS t(Name)
        ) AS t_names
     WHERE t_names.Name IS NOT NULL) AS TagList
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
Windowed AS (
  SELECT
    rp.*,
    ROW_NUMBER() OVER (
      PARTITION BY rp.OwnerUserId
      ORDER BY rp.LastActivityDate DESC, rp.CreationDate DESC
    ) AS rn,
    RANK() OVER (
      ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.CommentDensity DESC
    ) AS score_rank
  FROM RankedPosts rp
),
Agg AS (
  SELECT
    w.OwnerUserId,
    COUNT(*) AS TotalQuestions,
    SUM(w.Score) AS SumScores,
    AVG(w.Score) AS AvgScore,
    MAX(w.ViewCount) AS MaxViews,
    MIN(w.CreationDate) AS FirstQuestionDate,
    MAX(w.LastActivityDate) AS LastActive
  FROM Windowed w
  GROUP BY w.OwnerUserId
),
Filtered AS (
  SELECT
    w.*,
    a.TotalQuestions,
    a.SumScores,
    a.AvgScore,
    a.MaxViews,
    a.FirstQuestionDate,
    a.LastActive
  FROM Windowed w
  LEFT JOIN Agg a ON w.OwnerUserId = a.OwnerUserId
  WHERE w.rn <= 5 -- top 5 latest by user
    AND w.score_rank >= 1
  UNION ALL
  SELECT
    w.*,
    a.TotalQuestions,
    a.SumScores,
    a.AvgScore,
    a.MaxViews,
    a.FirstQuestionDate,
    a.LastActive
  FROM Windowed w
  LEFT JOIN Agg a ON w.OwnerUserId = a.OwnerUserId
  WHERE w.OwnerUserId IS NULL
),
Final AS (
  SELECT
    f.PostId,
    f.Title,
    f.Tags,
    f.CreationDate,
    f.LastActivityDate,
    f.Score,
    f.ViewCount,
    f.CommentCount,
    f.AnswerCount,
    f.FavoriteCount,
    f.Reputation,
    f.DisplayName,
    f.TagList,
    f.TotalQuestions,
    f.SumScores,
    f.AvgScore,
    f.MaxViews,
    f.FirstQuestionDate,
    f.LastActive
  FROM Filtered f
  ORDER BY
    f.LastActivityDate DESC NULLS LAST,
    f.Score DESC,
    f.ViewCount DESC
)
SELECT *
FROM Final
LIMIT 100;