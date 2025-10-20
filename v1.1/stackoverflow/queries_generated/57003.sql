-- {"query": "57003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 887} 

WITHHighRepUsers AS (
    SELECT
        Id AS UserId,
        Reputation
    FROM
        Users
    WHERE
        Reputation > 10000
), AirTightQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        u.DisplayName AS AuthorName,
        u.Reputation AS AuthorReputation,
        t.TagName,
        COUNT(v.PostId) AS VoteCount,
        COUNT(c.PostId) AS CommentCount,
        STRING_AGG(DISTINCT lt.Name, ', ') AS LinkTypes
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    JOIN
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN
        LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE
        p.PostTypeId = 1
        AND p.AnswerCount > 5
        AND p.ViewCount > 1000
        AND p.CreationDate > '2022-01-01'
    GROUP BY
        u.DisplayName, p.Title, u.Reputation, p.Id, t.TagName, p.ViewCount, p.AnswerCount, p.CreationDate, p.LastActivityDate, p.Score
), SubsequentActivity AS (
    SELECT
        q.PostId,
        q.Title,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.UserId AS EditorId,
        ph.Comment
        ph.ContentLicense,
        pt.Name AS HistoryTypeName,
        u.DisplayName AS EditorName
    FROM
        AirTightQuestions q
    JOIN
       PostHistory ph ON q.PostId = ph.PostId
    JOIN
       PostHistoryTypes pt ON ph.PostHistoryTypeId = pt.Id
    JOIN
       Users u ON ph.UserId = u.Id
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6, 10, 14, 15, 16, 17, 35, 36, 37, 38)
    )
SELECT sa.*,
       a.AuthorName,
       a.AuthorReputation,
       (SELECT COUNT(*)
        FROM HighRepUsers hru
        JOIN Votes v ON hru.UserId = v.UserId
        WHERE v.PostId = sa.PostId AND v.VoteTypeId = 2) AS HighRepUpvotes,
        CASE
            a.AuthorReputation
            WHEN < 50000 THEN 'bronze author'
            WHEN a.AuthorReputation < 100000 THEN  'silver author'
            ELSE 'golden author'
            END author's label

    FROM
        SubsequentActivity sa
    JOIN
        AirTightQuestions a ON sa.PostId = a.PostId
    WHERE
        sa.HistoryDate > '2022-01-01'
    ORDER BY
       HighRepUpvotes desc
    LIMIT 100;
