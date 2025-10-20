WITH TagQuestions AS (
    SELECT
        t.TagName,
        p.Id             AS QuestionId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.ViewCount
    FROM Posts p
    JOIN unnest(
           string_to_array(
             substring(p.Tags FROM 2 FOR (length(p.Tags) - 2))
           , '><')
         ) AS t(TagName) ON TRUE
    WHERE p.PostTypeId = 1
),
MonthlyStats AS (
    SELECT
        TagName,
        date_trunc('month', CreationDate) AS Month,
        COUNT(*)                AS QuestionsMonthly,
        SUM(AnswerCount)        AS TotalAnswers,
        SUM(ViewCount)          AS TotalViews,
        AVG(Score)              AS AvgScore,
        MAX(Score)              AS MaxScore
    FROM TagQuestions
    WHERE CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY TagName, date_trunc('month', CreationDate)
),
TopAnswers AS (
    SELECT
        q.Id              AS QuestionId,
        a.Id              AS AnswerId,
        a.Score,
        u.Reputation,
        RANK() OVER (
           PARTITION BY q.Id
           ORDER BY a.Score DESC
        )                  AS RankByScore,
        LEAD(a.CreationDate) OVER (
           PARTITION BY q.Id
           ORDER BY a.CreationDate
        ) - a.CreationDate AS AnswerGap
    FROM Posts q
    JOIN Posts a
      ON a.ParentId = q.Id
     AND a.PostTypeId = 2
    LEFT JOIN Users u
      ON u.Id = a.OwnerUserId
    WHERE q.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
CommentStats AS (
    SELECT
        p.Id               AS PostId,
        COUNT(c.Id)        AS CommentCount,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END)  AS PositiveComments,
        SUM(CASE WHEN c.Score <= 0 THEN 1 ELSE 0 END) AS NonPositiveComments
    FROM Posts p
    LEFT JOIN Comments c
      ON c.PostId = p.Id
    GROUP BY p.Id
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*)       AS BadgeCount,
        MAX(b.Date)    AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    ms.TagName,
    ms.Month,
    ms.QuestionsMonthly,
    ms.TotalAnswers,
    ms.TotalViews,
    ms.AvgScore,
    ms.MaxScore,
    ta.TopAnswerScore,
    ta.TopAnswererReputation,
    ca.CommentCount  AS QuestionComments,
    an.CommentCount  AS AnswerComments,
    ub.BadgeCount,
    ub.LastBadgeDate
FROM MonthlyStats ms
LEFT JOIN LATERAL (
    SELECT
        taq.QuestionId,
        MAX(CASE WHEN ta.RankByScore = 1 THEN ta.Score END)       AS TopAnswerScore,
        MAX(CASE WHEN ta.RankByScore = 1 THEN ta.Reputation END)  AS TopAnswererReputation,
        MAX(ta.AnswerId) AS AnswerId  -- include AnswerId so outer join to answer comments works
    FROM TopAnswers taq
    JOIN TopAnswers ta
      ON taq.QuestionId = ta.QuestionId
    WHERE taq.QuestionId IN (
        SELECT q.Id
        FROM Posts q
        WHERE q.PostTypeId = 1
          AND q.Tags LIKE '%' || ms.TagName || '%'
          AND date_trunc('month', q.CreationDate) = ms.Month
    )
    GROUP BY taq.QuestionId
) ta ON TRUE
LEFT JOIN CommentStats ca
  ON ca.PostId = ta.QuestionId
LEFT JOIN CommentStats an
  ON an.PostId = ta.AnswerId
LEFT JOIN UserBadges ub
  ON ub.UserId = (
       SELECT OwnerUserId
       FROM Posts
       WHERE Id = ta.QuestionId
)
ORDER BY ms.TagName, ms.Month DESC;