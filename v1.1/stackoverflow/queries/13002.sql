WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownvotes,
        ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) DESC) AS UpvoteRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE 
        u.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH)
    GROUP BY 
        u.Id
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS Tags,
        ROW_NUMBER() OVER (PARTITION BY pt.Name ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank,
        p.OwnerUserId
    FROM 
        Posts p
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN 
        PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN 
        Tags t ON (',' || p.Tags || ',') LIKE ('%,' || t.TagName || ',%')
    WHERE 
        pt.Name = 'Question' AND 
        (p.ClosedDate IS NULL OR p.ClosedDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR))
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, pt.Name, p.OwnerUserId
    HAVING 
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) < 2
)
SELECT
    ua.UserId,
    u.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalUpvotes,
    ua.TotalDownvotes,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.Tags,
    (ua.TotalUpvotes - COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 3 THEN 1 ELSE 0 END), 0)) AS AdjustedUpvotes,
    ua.UpvoteRank
FROM 
    UserActivity ua
JOIN 
    Users u ON ua.UserId = u.Id
LEFT JOIN 
    TopQuestions tq ON ua.UserId = tq.OwnerUserId AND tq.QuestionRank = 1
LEFT JOIN 
    PostHistory ph ON ua.UserId = ph.UserId AND ph.PostHistoryTypeId = 3 AND ph.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3' MONTH)
WHERE 
    ua.UpvoteRank <= 100 AND 
    (u.Location IS NOT NULL OR u.AboutMe LIKE '%SQL%')
GROUP BY 
    ua.UserId, u.DisplayName, ua.QuestionCount, ua.AnswerCount, ua.TotalUpvotes, ua.TotalDownvotes, tq.Title, tq.Score, tq.Tags, ua.UpvoteRank
ORDER BY 
    ua.UpvoteRank, tq.Score DESC;