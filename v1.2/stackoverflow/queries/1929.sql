WITH RecursiveUsersActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionsCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswersCount,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS RankReputation
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation
),
RecursiveCommentStats(id, usercollapse_token_counts) AS (
    SELECT DISTINCT
        c.Id AS CommentID,
        COALESCE(CAST(NULL AS text), '') AS usercollapse_token_counts
    FROM
        Comments c
)
SELECT *
FROM RecursiveUsersActivity ua
LEFT JOIN RecursiveCommentStats cs ON cs.id = ua.UserId;