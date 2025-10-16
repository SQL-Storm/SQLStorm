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
    WHERE p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days')
),
QuestionWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate AS QuestionDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        ARRAY_AGG(a.Id) FILTER (WHERE a.Id IS NOT NULL) AS AnswerIds,
        COUNT(a.Id) AS AnswerCount
    FROM RecentPosts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Tags, q.CreationDate, q.Score, q.ViewCount
),
TagUsage AS (
    SELECT
        tag AS Tag,
        COUNT(*) AS UsageCount
    FROM (
        SELECT unnest(string_to_array(substring(rp.Tags FROM 2 FOR char_length(rp.Tags)-2), '><')) AS tag
        FROM RecentPosts rp
        WHERE rp.PostTypeId = 1 AND rp.Tags IS NOT NULL
    ) sub
    GROUP BY tag
),
ActivityPressure AS (
    SELECT
        q.QuestionId,
        q.AnswerCount,
        q.AnswerIds,
        u.Id AS UserId,
        u.Reputation,
        u.LastAccessDate,
        u.Location,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.QuestionId) AS CommentCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ANY(q.AnswerIds)) AS AnswerCommentsCount
    FROM QuestionWithAnswers q
    LEFT JOIN Posts p_owner ON p_owner.Id = q.QuestionId
    LEFT JOIN Users u ON u.Id = p_owner.OwnerUserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.CommentCount,
    ua.LastActivity,
    tu.Tag,
    tu.UsageCount,
    ap.AnswerCount AS NumberOfAnswers,
    ap.Reputation,
    ap.LastAccessDate,
    ap.Location,
    ap.CommentCount AS TotalCommentsOnPosts,
    ap.AnswerCommentsCount
FROM UserActivity ua
LEFT JOIN TagUsage tu ON TRUE
LEFT JOIN ActivityPressure ap ON ap.UserId = ua.UserId
WHERE
    ua.LastActivity > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days')
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.CommentCount,
    ua.LastActivity,
    tu.Tag,
    tu.UsageCount,
    ap.AnswerCount,
    ap.Reputation,
    ap.LastAccessDate,
    ap.Location,
    ap.CommentCount,
    ap.AnswerCommentsCount
ORDER BY ua.LastActivity DESC
LIMIT 100;