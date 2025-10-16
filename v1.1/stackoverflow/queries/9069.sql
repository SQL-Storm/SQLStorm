WITH RecentQuestions AS (
    SELECT
        p.Id           AS QuestionId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName,
        p.CreationDate,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) / (60*60*24) AS AgeDays
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
     AND pt.Name = 'Question'
    LEFT JOIN Users u
      ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days'
),
AnswerStats AS (
    SELECT
        ParentId            AS QuestionId,
        COUNT(*)            AS AnswerCount,
        SUM(CASE WHEN Score>0 THEN 1 ELSE 0 END) AS PositiveAnswers,
        AVG(Score)          AS AvgAnswerScore
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
),
CommentStats AS (
    SELECT
        c.PostId,
        COUNT(*)                    AS CommentCount,
        MAX(LENGTH(c.Text))         AS MaxCommentLength,
        AVG(LENGTH(c.Text))         AS AvgCommentLength
    FROM Comments c
    GROUP BY c.PostId
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
RankedQuestions AS (
    SELECT
        rq.QuestionId,
        rq.Title,
        rq.Tags,
        rq.OwnerUserId,
        rq.DisplayName,
        rq.CreationDate,
        rq.AgeDays,
        COALESCE(a.AnswerCount,0)      AS AnswerCount,
        COALESCE(c.CommentCount,0)     AS CommentCount,
        COALESCE(c.MaxCommentLength,0) AS MaxCommentLength,
        COALESCE(b.GoldBadges,0)       AS GoldBadges,
        COALESCE(b.SilverBadges,0)     AS SilverBadges,
        COALESCE(b.BronzeBadges,0)     AS BronzeBadges,
        ROW_NUMBER() OVER (
            ORDER BY
              COALESCE(a.AnswerCount,0) DESC,
              COALESCE(c.CommentCount,0) DESC
        ) AS PopularityRank
    FROM RecentQuestions rq
    LEFT JOIN AnswerStats    a ON rq.QuestionId = a.QuestionId
    LEFT JOIN CommentStats   c ON rq.QuestionId = c.PostId
    LEFT JOIN BadgeSummary   b ON rq.OwnerUserId = b.UserId
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.DisplayName,
    rq.CreationDate,
    rq.AgeDays,
    rq.AnswerCount,
    rq.CommentCount,
    rq.MaxCommentLength,
    (rq.GoldBadges || '/' || rq.SilverBadges || '/' || rq.BronzeBadges) AS BadgeTriplet,
    rq.PopularityRank,
    (
      SELECT COUNT(*)
      FROM (
        SELECT unnest(
                 string_to_array(
                   substring(rq.Tags FROM 2 FOR length(rq.Tags)-2)
                 , '><')
               ) AS tag
      ) AS sub
      JOIN Tags t ON sub.tag = t.TagName
    ) AS TagMatchCount
FROM RankedQuestions rq
WHERE rq.PopularityRank <= 100

UNION

SELECT
    rq.QuestionId,
    rq.Title,
    rq.DisplayName,
    rq.CreationDate,
    rq.AgeDays,
    rq.AnswerCount,
    rq.CommentCount,
    rq.MaxCommentLength,
    (rq.GoldBadges || '/' || rq.SilverBadges || '/' || rq.BronzeBadges) AS BadgeTriplet,
    rq.PopularityRank,
    0 AS TagMatchCount
FROM RankedQuestions rq
WHERE rq.OwnerUserId IN (
    SELECT u.Id
    FROM Users u
    WHERE u.Reputation > 10000
)

EXCEPT

SELECT
    QuestionId,
    Title,
    DisplayName,
    CreationDate,
    AgeDays,
    AnswerCount,
    CommentCount,
    MaxCommentLength,
    (GoldBadges || '/' || SilverBadges || '/' || BronzeBadges) AS BadgeTriplet,
    PopularityRank,
    0 AS TagMatchCount
FROM RankedQuestions
WHERE AgeDays > 3

ORDER BY PopularityRank, AgeDays DESC
LIMIT 200;