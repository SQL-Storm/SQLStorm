WITH active_question_stats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        p.LastActivityDate AS LastActivity,
        p.Score AS QuestionScore,
        p.ViewCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT v_up.Id) AS UpVotes,
        COUNT(DISTINCT v_down.Id) AS DownVotes,
        ARRAY_AGG(DISTINCT t.TagName) AS Tags
    FROM
        Posts p
        LEFT JOIN Comments c ON c.PostId = p.Id
        LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
        LEFT JOIN Votes v_up ON v_up.PostId = p.Id AND v_up.VoteTypeId = 2
        LEFT JOIN Votes v_down ON v_down.PostId = p.Id AND v_down.VoteTypeId = 3
        LEFT JOIN (
            SELECT p2.Id, UNNEST(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) AS TagName
            FROM Posts p2
        ) t ON t.Id = p.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
        AND p.ClosedDate IS NULL
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount
),
high_activity_days AS (
    SELECT
        CAST(date_trunc('day', p.LastActivityDate) AS date) AS Day,
        COUNT(DISTINCT p.Id) AS QuestionsActive
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY
        CAST(date_trunc('day', p.LastActivityDate) AS date)
),
top_users AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM
        Users u
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
        LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
        LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
)
SELECT
    aqst.QuestionId,
    aqst.Title,
    aqst.QuestionCreationDate,
    aqst.LastActivity,
    aqst.QuestionScore,
    aqst.ViewCount,
    aqst.CommentCount,
    aqst.AnswerCount,
    aqst.UpVotes,
    aqst.DownVotes,
    aqst.Tags,
    hd.Day,
    hd.QuestionsActive,
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.CommentCount,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.UpVotesGiven,
    tu.DownVotesGiven
FROM
    active_question_stats aqst
    LEFT JOIN high_activity_days hd ON CAST(date_trunc('day', aqst.LastActivity) AS date) = hd.Day
    LEFT JOIN top_users tu ON tu.Id = (
        SELECT p.OwnerUserId FROM Posts p WHERE p.Id = aqst.QuestionId LIMIT 1
    )
ORDER BY
    aqst.LastActivity DESC
LIMIT 100;