WITH
question_tag_agg AS (
  SELECT
    p.Id AS QuestionId,
    unnest(
      string_to_array(
        substring(p.Tags, 2, length(p.Tags) - 2),
        '><'
      )
    ) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
top_tags AS (
  SELECT
    Tag,
    COUNT(*) AS TagCount
  FROM question_tag_agg
  GROUP BY Tag
  ORDER BY TagCount DESC
  LIMIT 10
),
user_activity AS (
  SELECT
    u.Id,
    u.DisplayName,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
    COUNT(c.Id) AS Comments,
    SUM(
      CASE
        WHEN v.VoteTypeId = 2 THEN  1
        WHEN v.VoteTypeId = 3 THEN -1
        ELSE 0
      END
    ) AS VoteBalance
  FROM Users u
  LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId      = u.Id
  LEFT JOIN Votes v    ON v.UserId      = u.Id
  GROUP BY u.Id, u.DisplayName
),
tag_popularity AS (
  SELECT
    qta.Tag,
    COUNT(DISTINCT p.Id) AS PostsCount,
    AVG(p.Score)           AS AvgScore
  FROM question_tag_agg qta
  JOIN Posts p ON p.Id = qta.QuestionId
  GROUP BY qta.Tag
),
question_duplicates AS (
  SELECT
    p.Id,
    COUNT(pl.Id) AS DuplicateCount
  FROM Posts p
  LEFT JOIN PostLinks pl
    ON pl.PostId    = p.Id
   AND pl.LinkTypeId = 3
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
)
SELECT
  tt.Tag,
  tp.PostsCount,
  tp.AvgScore,
  qd.DuplicateCount,
  topq.QuestionId,
  topq.Title,
  topq.EditCount,
  ua.DisplayName AS TopUser,
  ua.Questions,
  ua.Answers,
  ua.Comments,
  ua.VoteBalance
FROM top_tags tt
JOIN tag_popularity tp
  ON tp.Tag = tt.Tag
JOIN LATERAL (
  SELECT
    p.Id    AS QuestionId,
    p.Title,
    COUNT(ph.Id) AS EditCount,
    MAX(p.Score)  AS Score_for_order
  FROM Posts p
  LEFT JOIN PostHistory ph
    ON ph.PostId            = p.Id
   AND ph.PostHistoryTypeId IN (4,5,6)
  WHERE p.PostTypeId = 1
    AND p.Tags LIKE '%<' || tt.Tag || '>%'
  GROUP BY p.Id, p.Title
  ORDER BY Score_for_order DESC
  LIMIT 1
) AS topq ON TRUE
JOIN question_duplicates qd
  ON qd.Id = topq.QuestionId
JOIN user_activity ua
  ON ua.Id = (
       SELECT OwnerUserId
       FROM Posts p2
       WHERE p2.Id = topq.QuestionId
     )
ORDER BY
  tp.PostsCount DESC,
  tp.AvgScore   DESC,
  qd.DuplicateCount DESC;