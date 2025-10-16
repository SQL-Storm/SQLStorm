WITH QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        u.DisplayName,
        u.Reputation,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes'
            ELSE 'No'
        END AS HasAcceptedAnswer,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagArray,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS UserQuestionCount,
        AVG(p.Score) OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.CreationDate 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS RunningAvgScore
    FROM Posts p
    LEFT OUTER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= CAST('2020-01-01' AS timestamp)
      AND p.ClosedDate IS NULL
),
TopAnswers AS (
    SELECT 
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.Score,
        u.DisplayName AS Answerer,
        u.Reputation,
        ROW_NUMBER() OVER (
            PARTITION BY a.ParentId 
            ORDER BY a.Score DESC, a.CreationDate ASC
        ) AS Rank
    FROM Posts a
    LEFT OUTER JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(*) AS BadgeCount,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges
    FROM Badges
    GROUP BY UserId
),
CommentActivity AS (
    SELECT 
        PostId,
        COUNT(*) AS CommentCount,
        AVG(CASE WHEN UserId IS NULL THEN 0 ELSE c.Score END) AS AvgCommentScore
    FROM Comments c
    WHERE c.CreationDate >= CAST('2020-01-01' AS timestamp)
    GROUP BY PostId
)
SELECT 
    qs.QuestionId,
    qs.Title,
    REPLACE(qs.Title, 'How to', 'Tutorial on') AS ModifiedTitle,
    qs.AnswerCount,
    qs.HasAcceptedAnswer,
    ta.Answerer,
    ta.Score AS TopAnswerScore,
    ta.Reputation AS AnswererRep,
    qs.Reputation AS AskerRep,
    qs.UserQuestionCount,
    qs.RunningAvgScore,
    bc.BadgeCount,
    bc.GoldBadges,
    ca.CommentCount,
    ca.AvgCommentScore,
    (qs.Reputation + COALESCE(ta.Reputation, 0)) / NULLIF(qs.UserQuestionCount, 0) AS CalculatedMetric,
    qs.TagArray[1] AS PrimaryTag,
    EXISTS (
        SELECT 1 FROM PostLinks pl 
        WHERE pl.PostId = qs.QuestionId 
          AND pl.LinkTypeId = 3
          AND pl.CreationDate > qs.CreationDate
    ) AS LinkedAsDuplicateLater
FROM QuestionStats qs
LEFT OUTER JOIN TopAnswers ta ON qs.QuestionId = ta.QuestionId AND ta.Rank = 1
LEFT OUTER JOIN (
    -- rewrite of join condition to avoid non-inner join on subquery;
    -- join BadgeCounts to the user who owns the question's post
    SELECT bc.UserId, bc.BadgeCount, bc.GoldBadges, p.Id AS PostId
    FROM BadgeCounts bc
    JOIN Posts p ON p.OwnerUserId = bc.UserId
) bc ON qs.QuestionId = bc.PostId
LEFT OUTER JOIN CommentActivity ca ON qs.QuestionId = ca.PostId
WHERE qs.AnswerCount > 5
GROUP BY
    qs.QuestionId,
    qs.Title,
    qs.Tags,
    qs.CreationDate,
    qs.AnswerCount,
    qs.DisplayName,
    qs.Reputation,
    qs.HasAcceptedAnswer,
    qs.TagArray,
    qs.UserQuestionCount,
    qs.RunningAvgScore,
    ta.Answerer,
    ta.Score,
    ta.Reputation,
    bc.BadgeCount,
    bc.GoldBadges,
    ca.CommentCount,
    ca.AvgCommentScore,
    qs.TagArray[1]
ORDER BY qs.AnswerCount DESC, qs.QuestionId
LIMIT 100;