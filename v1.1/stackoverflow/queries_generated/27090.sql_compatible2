WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY SUM(p.Score) DESC) AS ScoreRank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),
TagActivity AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        COUNT(p.Id) AS TaggedPosts,
        SUM(p.Score) AS TaggedScore,
        SUM(p.ViewCount) AS TaggedViews,
        COALESCE(p2.Body, 'No Excerpt') AS TagExcerpt,
        u.DisplayName AS ExcerptEditor
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN
        Posts p2 ON t.ExcerptPostId = p2.Id
    LEFT JOIN
        Users u ON p2.LastEditorUserId = u.Id
    GROUP BY
        t.Id, t.TagName, p2.Body, u.DisplayName
),
ComplexPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.Title,
        p.Body,
        p.Tags,
        p.AnswerCount,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate) AS LastVoteDate,
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            ELSE 'Not Accepted'
        END AS AcceptanceStatus,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS PostStatus,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        p.ParentId
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName, p.Title, p.Body, p.Tags, p.AnswerCount, p.AcceptedAnswerId, p.ClosedDate, p.ParentId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalScore,
    ua.LastPostDate,
    ua.PostRank,
    ua.ScoreRank,
    (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = ua.UserId) AS TotalBadges,
    STRING_AGG(ta.TagName, ', ') AS PopularTags,
    ta.TaggedPosts,
    ta.TaggedScore,
    ta.TaggedViews,
    ta.TagExcerpt,
    ta.ExcerptEditor,
    cp.PostId,
    cp.PostTypeId,
    cp.CreationDate,
    cp.Score,
    cp.ViewCount,
    cp.OwnerName,
    SUBSTRING(cp.Title FROM 1 FOR 50) AS ShortTitle,
    CASE
        WHEN LENGTH(cp.Body) > 100 THEN SUBSTRING(cp.Body FROM 1 FOR 100) || '...'
        ELSE cp.Body
    END AS ShortBody,
    cp.Tags,
    cp.AnswerCount,
    cp.CommentCount,
    cp.UpVotes,
    cp.DownVotes,
    cp.LastVoteDate,
    cp.AcceptanceStatus,
    cp.PostStatus,
    cp.PreviousPostScore,
    COALESCE(cp.PostStatus, 'Unknown') AS FinalPostStatus
FROM
    UserActivity ua
LEFT JOIN
    TagActivity ta ON ta.TagId = (
        SELECT t2.Id FROM Tags t2 ORDER BY RANDOM() LIMIT 1
    )
LEFT JOIN
    ComplexPosts cp ON cp.OwnerUserId = ua.UserId
WHERE
    ua.TotalPosts > 0
    AND (cp.PostTypeId = 1 OR cp.PostTypeId = 2)
    AND ta.TaggedPosts > 10
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalScore,
    ua.LastPostDate,
    ua.PostRank,
    ua.ScoreRank,
    ta.TagName,
    ta.TaggedPosts,
    ta.TaggedScore,
    ta.TaggedViews,
    ta.TagExcerpt,
    ta.ExcerptEditor,
    cp.PostId,
    cp.PostTypeId,
    cp.CreationDate,
    cp.Score,
    cp.ViewCount,
    cp.OwnerName,
    cp.Title,
    cp.Body,
    cp.Tags,
    cp.AnswerCount,
    cp.CommentCount,
    cp.UpVotes,
    cp.DownVotes,
    cp.LastVoteDate,
    cp.AcceptanceStatus,
    cp.PostStatus,
    cp.PreviousPostScore
ORDER BY
    ua.TotalScore DESC,
    cp.CreationDate DESC;