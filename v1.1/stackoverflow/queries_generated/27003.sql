-- {"query": "27003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1624} 

WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(a.Score), 0) AS TotalAnswerScore,
        COUNT(p.Id) AS TotalPosts,
        COUNT(a.Id) AS TotalAnswers,
        COUNT(c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.LastAccessDate > NOW() - INTERVAL '30 days'
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
), RecognizedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.Score,
        /* Generate excerpt simulating trimming*/
        CASE
            WHEN LENGTH(p.Body) > 200 THEN SUBSTRING(p.Body, 1, 200) || '...'
            ELSE p.Body
        END AS Excerpt,
        COALESCE(SUM(v.VoteTypeId = 2), 0) AS UpVotes,
        COALESCE(SUM(v.VoteTypeId = 3), 0) AS DownVotes,
        COUNT(c.Id) AS CommentCount,
        p.ViewCount,
        concat(pt.name, ' on ', TO_CHAR(p.CreationDate, 'YYYY-MM-DD HH24:MI:SS')) AS TypeDate
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    JOIN
        PostTypes pt on p.PostTypeId = pt.Id
    WHERE
        p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY
        p.Id, p.Title, p.Body, p.CreationDate, p.Score, p.ViewCount, pt.Name
), ActiveTags AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        REPLACE(t.TagName, ' ', '-') AS UrlSlug,
        LENGTH(t.TagName) AS TagLength,
        COUNT(pt.Id) AS RelatedPosts
    FROM
        Tags t
    LEFT JOIN
        Posts pt ON t.Id = ANY(STRING_TO_ARRAY(SUBSTRING(pt.Tags FROM 2 FOR LENGTH(pt.Tags)-2), ''><''))
    GROUP BY
        t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
    ORDER BY
        t.Count DESC
    LIMIT 50
)
SELECT
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.TotalPostScore + au.TotalAnswerScore AS CombinedScore,
    au.TotalPosts + au.TotalAnswers AS TotalContributions,
    rp.PostId,
    rp.Title,
    rp.Excerpt,
    rp.UpVotes,
    rp.DownVotes,
    rp.CommentCount,
    rp.ViewCount,
    COALESCE(rp.TypeDate, 'Unknown') AS PostInfo,
    at.TagName,
    at.TagLength
FROM
    ActiveUsers au
JOIN
    RecognizedPosts rp ON au.UserId = rp.OwnerUserId
LEFT JOIN
    ActiveTags at ON rp.Id = at.RelatedPosts
WHERE
    (rp.UpVotes > 10 AND rp.ViewCount > 500)
    OR (at.TagLength > 10 AND at.RelatedPosts > 5)
WINDOW
    AVG(rp.Score) OVER (PARTITION BY at.TagName ORDER BY rp.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS AvgScoreByTag
WINDOW
    COUNT(rp.Id) OVER (PARTITION BY au.UserId ORDER BY rp.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ContributionCount
WHERE
    (CombinedScore > 1000 AND ContributionCount > 10)
    OR (AvgScoreByTag IS NOT NULL AND AvgScoreByTag > 5)

UNION ALL

SELECT
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.TotalPostScore + au.TotalAnswerScore AS CombinedScore,
    au.TotalPosts + au.TotalAnswers AS TotalContributions,
    rp.PostId,
    rp.Title,
    at.TagName,
    at.TagLength
FROM
    ActiveUsers au
JOIN
    RecognizedPosts rp ON au.UserId = rp.OwnerUserId
LEFT JOIN
    ActiveTags at ON rp.Id = at.RelatedPosts
LEFT JOIN
    PostHistory ph ON rp.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
WHERE
    ph.Comment IS NOT NULL
    AND (rp.UpVotes > 5 AND rp.ViewCount > 100)
GROUP BY
    au.UserId, au.DisplayName, au.Reputation, au.TotalPostScore, au.TotalAnswerScore, au.TotalPosts, au.TotalAnswers, rp.PostId, rp.Title,at.TagName,at.TagLength
