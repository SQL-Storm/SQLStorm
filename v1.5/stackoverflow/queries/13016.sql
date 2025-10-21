-- {"query": "13016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 559} 
WITH UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(p.Score) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS ScoreRank,
        AVG(ph.CreationDate - p.CreationDate) AS AvgEditTime
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE
        u.Reputation > 1000
    GROUP BY
        u.Id, u.DisplayName
),
TopTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName
    HAVING
        COUNT(p.Id) > 10
),
CommentedAnswers AS (
    SELECT
        p.Id AS AnswerId,
        COUNT(c.Id) AS CommentCount
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 2
    GROUP BY
        p.Id
    HAVING
        COUNT(c.Id) > 2
)
SELECT
    ua.DisplayName,
    ua.PostsCount,
    ua.TotalScore,
    tt.TagName,
    tt.QuestionCount,
    ca.AnswerId,
    ca.CommentCount,
    COALESCE(EXTRACT(DAY FROM ua.AvgEditTime), 0) AS AvgEditDays
FROM
    UserActivity ua
CROSS JOIN
    TopTags tt
LEFT JOIN
    CommentedAnswers ca ON ua.Id = ca.AnswerId
WHERE
    ua.ScoreRank <= 10
    AND tt.TagRank <= 5
ORDER BY
    ua.TotalScore DESC,
    tt.QuestionCount DESC,
    ca.CommentCount DESC;