-- {"query": "27085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1151} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.LastAccessDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        STRING_AGG(DISTINCT t.TagName, ', ') AS FavoriteTags
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Posts p2 ON p2.Id = p.ParentId
    LEFT JOIN
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE
        u.CreationDate > '2023-01-01'
    GROUP BY
        u.Id, u.Reputation, u.DisplayName, u.LastAccessDate
), RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        MAX(ph.CreationDate) AS LastEditDate,
        STRING_AGG(DISTINCT ph.UserId::TEXT, ', ') AS Editors,
        p.LastActivityDate
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.CreationDate > '2023-01-01'
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.Title, p.Tags, u.DisplayName, p.AcceptedAnswerId, p.LastActivityDate
), ActiveUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        LastAccessDate,
        TotalPosts,
        TotalComments,
        TotalVotes,
        TotalQuestions,
        TotalAnswers,
        TotalUpVotes,
        TotalDownVotes,
        FavoriteTags,
        ROW_NUMBER() OVER (PARTITION BY Reputation ORDER BY TotalPosts DESC) AS Rank
    FROM
        UserActivity
    WHERE
        TotalPosts > 10 AND TotalComments > 5
)
SELECT
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.TotalPosts,
    a.TotalComments,
    a.TotalVotes,
    a.TotalQuestions,
    a.TotalAnswers,
    a.TotalUpVotes,
    a.TotalDownVotes,
    a.FavoriteTags,
    a.Rank,
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.Tags,
    r.Score,
    r.ViewCount,
    r.AnswerCount,
    r.CommentCount,
    r.VoteCount,
    r.LastEditDate,
    r.Editors,
    r.LastActivityDate
FROM
    ActiveUsers a
LEFT JOIN
     RecentPosts r ON a.UserId = r.OwnerUserId
WHERE
    a.Rank <= 100
ORDER BY
    a.Reputation DESC, a.TotalPosts DESC, r.CreationDate DESC;
