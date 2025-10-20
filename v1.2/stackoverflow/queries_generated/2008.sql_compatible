WITH RecursiveUserQuestions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS QuestionId,
        p.CreationDate AS QuestionCreation,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS Rnk
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    WHERE u.Reputation IS NOT NULL
      AND p.Id IS NOT NULL
), RecentPosts AS (
    SELECT
        Q.UserId,
        '[' || STRING_AGG(
            '{"QuestionId":' || CAST(QuestionId AS VARCHAR) ||
            ',"QuestionCreation":"' || CAST(QuestionCreation AS VARCHAR) || '"}'
            , ','
        ) AS QuestionsJson
    FROM RecursiveUserQuestions Q
    WHERE Q.Rnk <= 5
    GROUP BY Q.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(rp.QuestionsJson, '[]') AS QuestionsJson
FROM Users u
LEFT JOIN RecentPosts rp ON rp.UserId = u.Id
WHERE u.Reputation IS NOT NULL;