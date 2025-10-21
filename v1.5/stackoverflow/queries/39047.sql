WITH TaggedQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate AS QuestionDate,
        unnest(
          string_to_array(
            substring(q.Tags, 2, LENGTH(q.Tags) - 2),
            '><'
          )
        ) AS Tag
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
),
AnswerStats AS (
    SELECT
        tq.Tag,
        a.OwnerUserId AS AnswererId,
        COUNT(*) AS NumAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - tq.QuestionDate))) AS AvgResponseSecs
    FROM TaggedQuestions tq
    JOIN Posts a
      ON a.ParentId = tq.QuestionId
     AND a.PostTypeId = 2
    GROUP BY tq.Tag, a.OwnerUserId
),
TopAnswerers AS (
    SELECT
        Tag,
        AnswererId,
        NumAnswers,
        AvgAnswerScore,
        AvgResponseSecs,
        ROW_NUMBER() OVER (
          PARTITION BY Tag
          ORDER BY NumAnswers DESC, AvgAnswerScore DESC
        ) AS RankInTag
    FROM AnswerStats
)
SELECT
    ta.Tag,
    u.DisplayName,
    ta.NumAnswers,
    ta.AvgAnswerScore,
    ta.AvgResponseSecs,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    COALESCE(c.CommentCount, 0) AS CommentCount,
    COALESCE(v.UpVotes, 0) AS TotalUpVotes,
    COALESCE(v.DownVotes, 0) AS TotalDownVotes
FROM TopAnswerers ta
JOIN Users u
  ON u.Id = ta.AnswererId
LEFT JOIN Badges b
  ON b.UserId = u.Id
LEFT JOIN (
    SELECT
        UserId,
        COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY UserId
) c
  ON c.UserId = u.Id
LEFT JOIN (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    JOIN Votes v
      ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
) v
  ON v.UserId = u.Id
WHERE ta.RankInTag <= 3
GROUP BY
    ta.Tag,
    u.DisplayName,
    ta.NumAnswers,
    ta.AvgAnswerScore,
    ta.AvgResponseSecs,
    COALESCE(c.CommentCount, 0),
    COALESCE(v.UpVotes, 0),
    COALESCE(v.DownVotes, 0)
ORDER BY ta.Tag, ta.NumAnswers DESC
LIMIT 100;