-- {"query": "9051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3415} 

WITH
  RecentQuestions AS (
    SELECT
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      t.Count,
      RANK() OVER (ORDER BY t.Count DESC) AS rk
    FROM Tags t
  ),
  UserBadges AS (
    SELECT
      u.Id          AS UserId,
      u.DisplayName,
      COUNT(b.Id)   AS TotalBadges,
      COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
      COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
      COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
  ),
  UserVoteStats AS (
    SELECT
      u.Id                                           AS UserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      COUNT(v.Id)                                     AS TotalVotes
    FROM Users u
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.PostId = p2.Id
    GROUP BY u.Id
  ),
  LatestComments AS (
    SELECT DISTINCT ON (c.PostId)
      c.PostId,
      c.Text        AS LatestComment,
      c.Score       AS CommentScore
    FROM Comments c
    ORDER BY c.PostId, c.CreationDate DESC
  )

SELECT
  ub.DisplayName                           AS UserName,
  rq.Title                                 AS LatestQuestionTitle,
  rq.CreationDate                          AS QuestionDate,
  COALESCE(ub.TotalBadges,0)               AS TotalBadges,
  ub.GoldCount,
  ub.SilverCount,
  ub.BronzeCount,
  COALESCE(uv.UpVotes,0)                   AS UpVotes,
  COALESCE(uv.DownVotes,0)                 AS DownVotes,
  COALESCE(lc.LatestComment, '(no comments)') AS LatestComment,
  tr.TagName                               AS MostPopularTag,
  ans.AnswerCount,
  ans.AcceptedScore,
  ROUND(
    100.0 * ans.AcceptedScore
    / NULLIF(ans.AnswerCount,0)
  ,2)                                      AS AcceptRatePct,
  taglist.TagList                          AS QuestionTags
FROM UserBadges ub
JOIN RecentQuestions rq
  ON rq.OwnerUserId = ub.UserId
 AND rq.rn = 1
LEFT JOIN UserVoteStats uv
  ON uv.UserId = ub.UserId
LEFT JOIN LatestComments lc
  ON lc.PostId = rq.Id
LEFT JOIN TagPopularity tr
  ON tr.rk = 1
LEFT JOIN LATERAL (
  SELECT
    COUNT(*)          AS AnswerCount,
    SUM(CASE WHEN a.Id = rq.AcceptedAnswerId THEN a.Score ELSE 0 END) AS AcceptedScore
  FROM Posts a
  WHERE a.ParentId = rq.Id
) ans ON TRUE
LEFT JOIN LATERAL (
  SELECT
    STRING_AGG(tag,'|') AS TagList
  FROM UNNEST(
         STRING_TO_ARRAY(
           SUBSTRING(COALESCE(rq.Tags,''),2,LENGTH(COALESCE(rq.Tags,''))-2)
         , '><')
       ) AS tag
) taglist ON TRUE
WHERE ub.TotalBadges > (
    SELECT AVG(TotalBadges)
    FROM UserBadges
    WHERE TotalBadges > 0
)
UNION ALL
SELECT
  'OVERALL_SUMMARY'      AS UserName,
  NULL                   AS LatestQuestionTitle,
  NULL                   AS QuestionDate,
  SUM(ub.TotalBadges),
  SUM(ub.GoldCount),
  SUM(ub.SilverCount),
  SUM(ub.BronzeCount),
  SUM(uv.UpVotes),
  SUM(uv.DownVotes),
  NULL,
  NULL,
  SUM(ans.AnswerCount),
  SUM(ans.AcceptedScore),
  NULL,
  NULL
FROM UserBadges ub
JOIN UserVoteStats uv
  ON uv.UserId = ub.UserId
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) AS AnswerCount,
    SUM(a.Score) FILTER (WHERE a.Id = rq.AcceptedAnswerId) AS AcceptedScore
  FROM Posts a
  JOIN RecentQuestions rq
    ON rq.Id = a.ParentId
) ans ON TRUE
ORDER BY QuestionDate DESC NULLS LAST
LIMIT 100;
