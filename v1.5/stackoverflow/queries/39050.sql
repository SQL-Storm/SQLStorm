-- {"query": "39050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3041} 
WITH
TopTags AS (
    SELECT t.TagName,
           COUNT(*)                   AS QuestionCount,
           AVG(p.Score)               AS AvgScore
    FROM Posts p
    JOIN Tags t
      ON p.PostTypeId = 1
     AND p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName
    HAVING COUNT(*) > 100
),
UserActivity AS (
    SELECT u.Id                        AS UserId,
           u.DisplayName,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
           COUNT(v.Id)            FILTER (WHERE v.VoteTypeId = 2) AS UpvotesReceived,
           COUNT(v.Id)            FILTER (WHERE v.VoteTypeId = 3) AS DownvotesReceived,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)    AS RepRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId       = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT b.UserId,
           COUNT(*)                  AS TotalBadges,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           STRING_AGG(b.Name, ',')   AS BadgesList
    FROM Badges b
    GROUP BY b.UserId
),
LinkCounts AS (
    SELECT p.Id AS PostId,
           COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
           COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount
    FROM Posts p
    LEFT JOIN PostLinks pl
      ON pl.PostId = p.Id
    GROUP BY p.Id
),
VoteStats AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
           SUM(CASE WHEN v.VoteTypeId = 4 THEN 1 ELSE 0 END) AS OffensiveVotes
    FROM Votes v
    GROUP BY v.PostId
),
CommentStats AS (
    SELECT c.PostId,
           COUNT(*)        AS CommentCount,
           MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.UpvotesReceived,
    ua.DownvotesReceived,
    ua.RepRank,
    bs.TotalBadges,
    bs.GoldBadges,
    bs.BadgesList,
    lt.TagName   AS TopTag,
    lt.QuestionCount,
    lt.AvgScore,
    vc.UpVotes,
    vc.DownVotes,
    vc.OffensiveVotes,
    lc.LinkedCount,
    lc.DuplicateCount,
    cs.CommentCount,
    cs.LastCommentDate
FROM UserActivity ua
LEFT JOIN BadgeStats bs
  ON bs.UserId = ua.UserId
LEFT JOIN LATERAL (
    SELECT tt.TagName, tt.QuestionCount, tt.AvgScore
    FROM TopTags tt
    ORDER BY tt.QuestionCount DESC
    LIMIT 1
) lt ON TRUE
LEFT JOIN VoteStats vc
  ON vc.PostId = (
      SELECT p2.Id
      FROM Posts p2
      WHERE p2.OwnerUserId = ua.UserId
      ORDER BY p2.Score DESC
      LIMIT 1
  )
LEFT JOIN LinkCounts lc
  ON lc.PostId = (
      SELECT p3.Id
      FROM Posts p3
      WHERE p3.OwnerUserId = ua.UserId
      ORDER BY p3.ViewCount DESC
      LIMIT 1
  )
LEFT JOIN CommentStats cs
  ON cs.PostId = (
      SELECT p4.Id
      FROM Posts p4
      WHERE p4.OwnerUserId = ua.UserId
      ORDER BY p4.CreationDate DESC
      LIMIT 1
  )
WHERE ua.QuestionsAsked > 20
ORDER BY ua.RepRank
FETCH FIRST 100 ROWS ONLY;