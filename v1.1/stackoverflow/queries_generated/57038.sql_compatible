WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(a.Score) AS TotalAnswerScore,
        SUM(c.Score) AS TotalCommentScore
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN
        Votes v ON (v.PostId = p.Id OR v.PostId = a.Id)
    LEFT JOIN
        Comments c ON c.UserId = u.Id
    WHERE
        u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY
        u.Id, u.Reputation
),
PopularTags AS (
    SELECT
        t.TagName,
        t.Count,
        COUNT(p.Id) AS QuestionsWithTag,
        AVG(p.Score) AS AverageScore,
        AVG(p.ViewCount) AS AverageViewCount
    FROM
        Tags t
    JOIN
        Posts p ON p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName, t.Count
    ORDER BY
        QuestionsWithTag DESC
    LIMIT 10
), HighActivityPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COUNT(v.Id) AS VoteCount,
        MAX(v.CreationDate) AS LastVoteDate
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId = 1 AND p.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' DAY
    GROUP BY
        p.Id, p.Title, p.ViewCount, p.AnswerCount, p.CommentCount
    ORDER BY
        VoteCount DESC
    LIMIT 20
),
TopCommenters AS (
    SELECT
        c.UserId,
        u.DisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalScore
    FROM
        Comments c
    JOIN
        Users u ON c.UserId = u.Id
    GROUP BY
        c.UserId, u.DisplayName
    ORDER BY
        CommentCount DESC, TotalScore DESC
    LIMIT 10
)
SELECT
    au.UserId,
    au.Reputation AS Reputation,
    au.PostCount,
    au.AnswerCount,
    au.UpVotesReceived,
    au.DownVotesReceived,
    au.TotalAnswerScore,
    au.TotalCommentScore,
    pt.TagName,
    pt.QuestionsWithTag,
    pt.AverageScore,
    pt.AverageViewCount,
    hap.PostId,
    hap.Title,
    hap.ViewCount,
    hap.AnswerCount,
    hap.CommentCount,
    hap.VoteCount,
    hap.LastVoteDate,
    tc.UserId AS CommenterId,
    tc.DisplayName,
    tc.CommentCount,
    tc.TotalScore
FROM
    ActiveUsers au
LEFT JOIN
    PopularTags pt ON pt.TagName IS NOT NULL
CROSS JOIN
    HighActivityPosts hap
CROSS JOIN
    TopCommenters tc;