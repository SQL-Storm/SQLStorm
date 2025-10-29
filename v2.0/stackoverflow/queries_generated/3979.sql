-- {"query": "3979.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2207} 

WITH
    recent_questions AS (
        SELECT Id,
               OwnerUserId,
               CreationDate,
               Score,
               Tags
        FROM Posts
        WHERE PostTypeId = 1
          AND CreationDate >= DATE '2023-01-01'
    ),
    answer_stats AS (
        SELECT
            a.OwnerUserId                     AS UserId,
            COUNT(*)                          AS AnswerCount,
            AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgScore,
            SUM(CASE WHEN a.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedCount,
            MAX(a.CreationDate)               AS LastAnswerDate
        FROM Posts a
        WHERE a.PostTypeId = 2
          AND a.CreationDate >= DATE '2023-01-01'
        GROUP BY a.OwnerUserId
    ),
    question_tags AS (
        SELECT
            q.Id                                   AS QuestionId,
            TRIM(BOTH '<>' FROM UNNEST(string_to_array(q.Tags, '><'))) AS Tag
        FROM recent_questions q
    ),
    user_tag_counts AS (
        SELECT
            a.OwnerUserId                     AS UserId,
            t.Tag,
            COUNT(*)                          AS TagAnswerCount,
            ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
        FROM Posts a
        JOIN question_tags t ON a.ParentId = t.QuestionId
        WHERE a.PostTypeId = 2
          AND a.OwnerUserId IS NOT NULL
        GROUP BY a.OwnerUserId, t.Tag
    ),
    latest_badge AS (
        SELECT DISTINCT ON (b.UserId)
            b.UserId,
            b.Name        AS BadgeName,
            b.Date        AS BadgeDate,
            b.Class       AS BadgeClass
        FROM Badges b
        ORDER BY b.UserId, b.Date DESC
    ),
    user_summary AS (
        SELECT
            u.Id                                   AS UserId,
            u.DisplayName,
            COALESCE(a.AnswerCount, 0)              AS TotalAnswers,
            COALESCE(a.AvgScore, 0)                 AS AvgAnswerScore,
            COALESCE(a.AcceptedCount, 0)            AS AcceptedAnswers,
            lb.BadgeName,
            lb.BadgeDate,
            lb.BadgeClass
        FROM Users u
        LEFT JOIN answer_stats a   ON u.Id = a.UserId
        LEFT JOIN latest_badge lb ON u.Id = lb.UserId
        WHERE u.Reputation > 1000
    )
SELECT
    us.UserId,
    us.DisplayName,
    us.TotalAnswers,
    us.AvgAnswerScore,
    us.AcceptedAnswers,
    us.BadgeName,
    us.BadgeDate,
    us.BadgeClass,
    COALESCE(ut.Tag, 'NoTag')               AS TopTag,
    COALESCE(ut.TagAnswerCount, 0)          AS TagAnswerCount,
    CASE
        WHEN us.TotalAnswers = 0                THEN NULL
        WHEN us.TotalAnswers < 10               THEN 'Newbie'
        WHEN us.TotalAnswers < 100              THEN 'Regular'
        ELSE                                    'PowerUser'
    END                                     AS UserTier,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = us.UserId AND c.Score >= 5)    AS HighScoreCommentCount
FROM user_summary us
LEFT JOIN (
    SELECT *
    FROM user_tag_counts
    WHERE TagRank = 1
) ut ON us.UserId = ut.UserId

UNION ALL

SELECT
    b.UserId,
    NULL               AS DisplayName,
    0                  AS TotalAnswers,
    0                  AS AvgAnswerScore,
    0                  AS AcceptedAnswers,
    b.Name             AS BadgeName,
    b.Date             AS BadgeDate,
    b.Class            AS BadgeClass,
    NULL               AS TopTag,
    0                  AS TagAnswerCount,
    NULL               AS UserTier,
    0                  AS QuestionCount,
    0                  AS HighScoreCommentCount
FROM Badges b
WHERE b.Class = 1
  AND NOT EXISTS (SELECT 1 FROM Users u WHERE u.Id = b.UserId)

ORDER BY UserId, UserTier NULLS LAST;
