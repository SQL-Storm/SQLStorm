-- {"query": "20017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1645} 

WITH PowerUsers AS (
    -- CTE 1: Identify "power users" based on reputation, tenure, and having a gold badge.
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate
    FROM Users u
    WHERE u.Id IN (SELECT DISTINCT UserId FROM Badges WHERE Class = 1) -- Must have at least one gold badge
      AND u.Reputation > 15000
      AND u.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '3 year')
      AND u.AboutMe IS NOT NULL
),
UserPosts AS (
    -- CTE 2: Consolidate questions and answers from power users into a single set, using a SET OPERATOR.
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CommentCount,
        p.ContentLicense,
        CASE
            WHEN p.PostTypeId = 1 THEN p.Id
            ELSE p.ParentId
        END AS QuestionId,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            ELSE 'Answer'
        END AS PostType
    FROM Posts p
    WHERE p.OwnerUserId IN (SELECT Id FROM PowerUsers)
      AND p.PostTypeId IN (1, 2) -- 1:Question, 2:Answer
      AND p.ClosedDate IS NULL

    UNION ALL

    -- Add a dummy record for each power user to demonstrate UNION and ensure all users are included
    -- even if they have no posts (though the previous filter makes this unlikely).
    SELECT
        -1 AS Id,
        pu.Id AS OwnerUserId,
        pu.CreationDate AS CreationDate,
        0 AS Score,
        0 AS ViewCount,
        0 AS FavoriteCount,
        0 AS CommentCount,
        'N/A' AS ContentLicense,
        -1 AS QuestionId,
        'UserCreationRecord' AS PostType
    FROM PowerUsers pu
),
PostDetails AS (
    -- CTE 3: Enrich post data with parent question info and calculate time between posts using a WINDOW FUNCTION.
    SELECT
        up.Id,
        up.OwnerUserId,
        up.PostType,
        up.CreationDate,
        up.Score,
        up.ViewCount,
        up.FavoriteCount,
        up.CommentCount,
        q.Title AS QuestionTitle,
        q.Tags,
        string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')[1] AS PrimaryTag,
        EXTRACT(EPOCH FROM (up.CreationDate - LAG(up.CreationDate, 1, up.CreationDate) OVER (PARTITION BY up.OwnerUserId ORDER BY up.CreationDate))) / 86400.0 AS DaysSinceLastPost,
        CASE WHEN up.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAcceptedAnswer
    FROM UserPosts up
    LEFT JOIN Posts q ON up.QuestionId = q.Id
    WHERE up.PostType IN ('Question', 'Answer') AND q.Tags IS NOT NULL
),
PostPerformance AS (
    -- CTE 4: Calculate a composite performance score and rank posts for each user.
    -- This involves complex calculations, a CORRELATED SUBQUERY, and a WINDOW FUNCTION.
    SELECT
        pd.*,
        (
            CASE
                WHEN pd.PostType = 'Question'
                THEN (pd.Score * 2.0) + (ln(1 + pd.ViewCount) * 1.5) + (COALESCE(pd.FavoriteCount, 0) * 3.0)
                WHEN pd.PostType = 'Answer'
                THEN (pd.Score * 4.0) + (pd.IsAcceptedAnswer * 50.0)
            END
            +
            -- Correlated subquery to add bonus points for recent upvotes.
            (SELECT COUNT(*) * 0.2 FROM Votes v WHERE v.PostId = pd.Id AND v.VoteTypeId = 2 AND v.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year'))
        ) AS PerformanceScore,
        ROW_NUMBER() OVER (PARTITION BY pd.OwnerUserId, pd.PostType ORDER BY
            (CASE
                WHEN pd.PostType = 'Question'
                THEN (pd.Score * 2.0) + (ln(1 + pd.ViewCount) * 1.5) + (COALESCE(pd.FavoriteCount, 0) * 3.0)
                WHEN pd.PostType = 'Answer'
                THEN (pd.Score * 4.0) + (pd.IsAcceptedAnswer * 50.0)
            END) DESC, pd.CreationDate DESC
        ) as PerformanceRank
    FROM PostDetails pd
)
-- Final Query: Select the top question and top answer for each power user, enriching with further details.
-- This involves joining multiple CTEs, OUTER JOINS, complex predicates, and string manipulations.
SELECT
    pu.DisplayName,
    pu.Reputation,
    pp.PostType,
    pp.QuestionTitle,
    pp.PrimaryTag,
    pp.Score AS PostScore,
    pp.CreationDate AS PostDate,
    ROUND(pp.DaysSinceLastPost, 2) AS DaysSinceLastPost,
    ROUND(pp.PerformanceScore, 2) AS PerformanceScore,
    (
        SELECT ROUND(AVG(ppi.PerformanceScore), 2)
        FROM PostPerformance ppi
        WHERE ppi.PrimaryTag = pp.PrimaryTag AND ppi.PostType = 'Question'
    ) AS AvgTagPerformance,
    COALESCE(
        (SELECT STRING_AGG(b.Name, ', ') FROM (SELECT Name FROM Badges WHERE UserId = pu.Id AND Class = 1 ORDER BY Date DESC LIMIT 3) b),
        'No Recent Gold Badges'
    ) AS RecentGoldBadges,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pp.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = pp.Id AND ph.PostHistoryTypeId IN (5, 8)) AS BodyEdits,
    LOWER(SUBSTRING(REPLACE(REPLACE(p_body.Body, '<p>', ''), '</p>', ' '), 1, 120)) || '...' AS BodySnippet
FROM PostPerformance pp
JOIN PowerUsers pu ON pp.OwnerUserId = pu.Id
LEFT JOIN Posts p_body ON pp.Id = p_body.Id
WHERE pp.PerformanceRank = 1
  AND pp.PrimaryTag IS NOT NULL
  AND (
      (pp.PostType = 'Question' AND pp.QuestionTitle ILIKE ANY(ARRAY['%optimization%', '%performance%', '%scaling%'])) OR
      (pp.PostType = 'Answer' AND pp.Score > 25 AND pp.IsAcceptedAnswer = 1)
  )
ORDER BY
    pu.Reputation DESC,
    pp.PerformanceScore DESC
LIMIT 150;
