-- {"query": "43076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 548} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastActivityDate,
        DENSE_RANK() OVER (ORDER BY SUM(p.Score) DESC) AS UserRank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id,
        u.DisplayName
),
TopQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        COUNT(DISTINCT ph.UserId) AS EditorCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id
    ORDER BY
        p.Score DESC,
        p.ViewCount DESC
    LIMIT 10
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalScore,
    ua.LastActivityDate,
    tq.PostId,
    tq.Title,
    tq.Score AS QuestionScore,
    tq.ViewCount,
    tq.AnswerCount,
    tq.EditorCount,
    tq.CommentCount,
    ua.UserRank
FROM
    UserActivity ua
JOIN
    TopQuestions tq ON ua.UserId = tq.EditorCount
WHERE
    ua.TotalScore > (SELECT AVG(TotalScore) FROM UserActivity)
ORDER BY
    ua.TotalScore DESC,
    tq.QuestionScore DESC;
