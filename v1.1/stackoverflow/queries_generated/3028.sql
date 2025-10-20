-- {"query": "3028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 843} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(COALESCE(v_up.VoteCount, 0)) AS UpVotesGiven,
        SUM(COALESCE(v_down.VoteCount, 0)) AS DownVotesGiven,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(p.LastActivityDate) AS LastActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            v.UserId,
            COUNT(*) AS VoteCount
        FROM Votes v
        WHERE v.VoteTypeId = 2
        GROUP BY v.UserId
    ) v_up ON v_up.UserId = u.Id
    LEFT JOIN (
        SELECT
            v.UserId,
            COUNT(*) AS VoteCount
        FROM Votes v
        WHERE v.VoteTypeId = 3
        GROUP BY v.UserId
    ) v_down ON v_down.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
RecentPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate
    FROM Posts p
    WHERE p.CreationDate > NOW() - INTERVAL '365 days'
),
QuestionWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate AS QuestionDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        ARRAY_AGG(a.Id) AS AnswerIds,
        COUNT(a.Id) AS AnswerCount
    FROM RecentPosts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Tags, q.CreationDate, q.Score, q.ViewCount
),
TagUsage AS (
    SELECT
        unnest(string_to_array(substring(t.Tags, 2, length(t.Tags)-2), '><')) AS Tag,
        COUNT(*) AS UsageCount
    FROM RecentPosts t
    WHERE t.PostTypeId = 1
    GROUP BY Tag
),
ActivityPressure AS (
    SELECT
        q.QuestionId,
        q.AnswerCount,
        q.AnswerIds,
        u.Reputation,
        u.LastAccessDate,
        u.Location,
        (
            SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.QuestionId
        ) AS CommentCount,
        (
            SELECT COUNT(*) FROM Comments c WHERE c.PostId = ANY(q.AnswerIds)
        ) AS AnswerCommentsCount
    FROM QuestionWithAnswers q
    LEFT JOIN Users u ON u.Id = (
        SELECT OwnerUserId FROM Posts p WHERE p.Id = q.QuestionId
    )
)
SELECT
    u.UserId,
    u.DisplayName,
    u.QuestionCount,
    u.AnswerCount,
    u.UpVotesGiven,
    u.DownVotesGiven,
    u.CommentCount,
    u.LastActivity,
    t.Tag,
    tu.UsageCount,
    ac.AnswerCount AS NumberOfAnswers,
    ac.Reputation,
    ac.LastAccessDate,
    ac.Location,
    ac.CommentCount AS TotalCommentsOnPosts,
    ac.AnswerCommentsCount
FROM UserActivity u
LEFT JOIN TagUsage t ON TRUE
LEFT JOIN ActivityPressure ac ON ac.UserId = u.UserId
WHERE
    u.LastActivity > NOW() - INTERVAL '180 days'
ORDER BY u.LastActivity DESC
LIMIT 100;