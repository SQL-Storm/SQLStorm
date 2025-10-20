-- {"query": "27086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1221} 

WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.LastAccessDate,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.LastAccessDate > NOW() - INTERVAL '1 month'
    GROUP BY
        u.Id, u.Reputation, u.DisplayName, u.LastAccessDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        DisplayName,
        PostCount,
        QuestionCount,
        AnswerCount
    FROM
        ActiveUsers
    WHERE
        Reputation > 1000
),
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(a.AnswerCount, 0) AS AnswerCount,
        COALESCE(c.CommentCount, 0) AS CommentCount,
        COALESCE(v.UpVotes, 0) AS UpVotes,
        COALESCE(v.DownVotes, 0) AS DownVotes
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            ParentId,
            COUNT(*) AS AnswerCount
        FROM
            Posts
        WHERE
            PostTypeId = 2
        GROUP BY
            ParentId
    ) a ON p.Id = a.ParentId
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount
        FROM
            Comments
        GROUP BY
            PostId
    ) c ON p.Id = c.PostId
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM
            Votes
        GROUP BY
            PostId
    ) v ON p.Id = v.PostId
    WHERE
       p.CreationDate > NOW() - INTERVAL '1 month'
),
TagMetrics AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore
    FROM
        Tags t
    JOIN
        Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY
        t.TagName
)
SELECT
    r.PostId,
    r.PostTypeId,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.Title,
    r.Tags,
    r.OwnerDisplayName,
    r.AnswerCount,
    r.CommentCount,
    r.UpVotes,
    r.DownVotes,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS UserDisplayName,
    u.LastAccessDate AS UserLastAccessDate,
    t.TagName,
    tm.PostCount AS TagPostCount,
    tm.QuestionCount AS TagQuestionCount,
    tm.AnswerCount AS TagAnswerCount,
    tm.TotalViews AS TagTotalViews,
    tm.AvgScore AS TagAvgScore
FROM
    RecentPosts r
JOIN
    Users u ON r.OwnerUserId = u.Id
JOIN
    Tags t ON r.Tags LIKE CONCAT('%<', t.TagName, '>%')
JOIN
    TagMetrics tm ON t.TagName = tm.TagName
WHERE
    u.Reputation > 1000
    AND r.Score > (SELECT AVG(Score) FROM Posts)
    AND r.ViewCount > (SELECT AVG(ViewCount) FROM Posts)
ORDER BY
    r.CreationDate DESC,
    r.Score DESC,
    r.ViewCount DESC
LIMIT 100;
