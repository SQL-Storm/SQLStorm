-- {"query": "6071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 912} 
WITH
-- Sample heavy CTE to benchmark various features
RecentActivities AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.FavoriteCount,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        v.VoteTypeId,
        vt.Name AS VoteTypeName,
        -- Correlated subquery: count comments after post creation
        (SELECT COUNT(*) FROM Comments c
         WHERE c.PostId = p.Id
           AND c.CreationDate > p.CreationDate) AS PostCommentCountAfterCreation,
        -- Window function to rank posts per day by score
        ROW_NUMBER() OVER (
            PARTITION BY CAST(p.CreationDate AS date)
            ORDER BY p.Score DESC, p.ViewCount DESC
        ) AS DayRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    -- Optional: outer join to catch posts without votes
    WHERE p.CreationDate >= DATEADD(day, -30, GETDATE())
      AND p.PostTypeId IN (1, 2) -- Questions and Answers
),
-- Expand by linking to related posts via PostLinks (outer join example)
ExpandedLinks AS (
    SELECT
        ra.PostId,
        ra.PostTypeId,
        ra.Title,
        ra.Tags,
        ra.Score,
        ra.ViewCount,
        ra.CommentCount,
        ra.AnswerCount,
        ra.FavoriteCount,
        ra.Reputation,
        ra.UserCreationDate,
        ra.LastAccessDate,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name AS LinkTypeName
    FROM RecentActivities ra
    LEFT JOIN PostLinks pl ON pl.PostId = ra.PostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
-- Complex predicate calculations and NULL handling
Calculated AS (
    SELECT
        PostId,
        PostTypeId,
        Title,
        Tags,
        Score,
        ViewCount,
        CommentCount,
        AnswerCount,
        FavoriteCount,
        Reputation,
        UserCreationDate,
        LastAccessDate,
        RelatedPostId,
        LinkTypeName,
        -- Complex expression with NULLs and arithmetic
        (COALESCE(Score, 0) * 2
         + COALESCE(ViewCount, 0) / NULLIF(COALESCE(AnswerCount, 1), 0)
         + CASE WHEN Reputation IS NULL THEN -1 ELSE 0 END) AS CompositeScore,
        DayRank
    FROM ExpandedLinks
    LEFT JOIN (
        SELECT
            PostId,
            ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS rn,
            CreationDate
        FROM Votes
    ) AS v2 ON v2.PostId = ExpandedLinks.PostId
    WINDOW w AS (PARTITION BY ExpandedLinks.PostId)
)
SELECT
    c.PostId,
    c.PostTypeId,
    c.Title,
    -- Split multi-valued Tags for benchmarking string processing
    STRING_AGG(TRIM(t.tag), ',') WITHIN GROUP (ORDER BY t.tag) AS AllTags,
    c.CompositeScore,
    c.DayRank,
    c.LinkTypeName,
    c.RelatedPostId,
    c.Reputation,
    c.UserCreationDate,
    c.LastAccessDate,
    c.CreationDate
FROM Calculated c
LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(REPLACE(REPLACE(REPLACE(c.Tags, '<', ''), '>', ''), ' ', ''), ',')) AS tag
) AS t ON TRUE
GROUP BY
    c.PostId, c.PostTypeId, c.Title, c.CompositeScore, c.DayRank,
    c.LinkTypeName, c.RelatedPostId, c.Reputation, c.UserCreationDate, c.LastAccessDate, c.CreationDate
ORDER BY c.CompositeScore DESC, c.DayRank ASC
LIMIT 100;