-- {"query": "1333.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2981} 

WITH UserEngagementSummary AS (
    -- CTE 1: Aggregates user activity, calculates a complex engagement score,
    -- and identifies users with significant post counts and reputation in a recent period.
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        -- Calculate a weighted engagement score based on various user metrics.
        -- Includes NULL handling for potential missing view counts or votes.
        (
            COALESCE(u.Reputation, 0) * 0.15 +
            COALESCE(u.UpVotes, 0) * 0.5 -
            COALESCE(u.DownVotes, 0) * 0.2 +
            COALESCE(u.Views, 0) * 0.01 +
            (SELECT COUNT(DISTINCT b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Date >= u.CreationDate) * 1.0
        ) AS TotalEngagementScore,
        COUNT(DISTINCT p.Id) AS PostsCreated,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        -- Window function: Rank users by reputation within their creation year.
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS RepRankInCreationYear
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE
        u.CreationDate >= '2015-01-01' -- Focus on more recent users
        AND u.Reputation > 500
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '1 year' -- Recently active
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate, u.LastAccessDate
    HAVING
        COUNT(DISTINCT p.Id) >= 5 AND COUNT(DISTINCT c.Id) >= 10
),
PostVersionComplexity AS (
    -- CTE 2: Analyzes post history to determine complexity and 'volatility' of posts.
    -- Includes identifying owner edits, multiple revisions, and close/reopen events.
    SELECT
        ph.PostId,
        ph.UserId AS HistoryUserId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.Comment,
        -- Detects if the edit was made by the post's original owner.
        (ph.UserId = (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = ph.PostId)) AS IsOwnerEdit,
        -- Window function: Counts total unique edit types per post.
        COUNT(DISTINCT ph.PostHistoryTypeId) OVER (PARTITION BY ph.PostId) AS UniqueHistoryTypeCount,
        -- Window function: Cumulative count of edits (Type 4,5,6) for a post.
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS CumulativeEditCount,
        -- Window function: Time difference in days to the previous history event for the same post.
        EXTRACT(DAY FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) AS DaysSincePrevHistory
    FROM PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (
            4, -- Edit Title
            5, -- Edit Body
            6, -- Edit Tags
            10, -- Post Closed
            11, -- Post Reopened
            12, -- Post Deleted
            13  -- Post Undeleted
        )
        AND ph.CreationDate >= '2018-01-01' -- Recent history
),
DetailedPostAnalysis AS (
    -- CTE 3: Combines post attributes with its history, filters controversial/complex posts,
    -- and performs string parsing on tags and body content.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.Body,
        p.LastActivityDate,
        p.ClosedDate,
        pvc.UniqueHistoryTypeCount,
        pvc.CumulativeEditCount,
        pvc.DaysSincePrevHistory,
        -- Correlated subquery: Fetches the name of the CloseReasonType if the post was closed.
        (
            SELECT crt.Name
            FROM PostHistory ph_close
            JOIN CloseReasonTypes crt ON crt.Id = CAST(ph_close.Comment AS SMALLINT)
            WHERE ph_close.PostId = p.Id AND ph_close.PostHistoryTypeId = 10 -- Post Closed
            ORDER BY ph_close.CreationDate DESC
            LIMIT 1
        ) AS LastCloseReason,
        -- Parses primary tag from the Tags string, handling NULLs gracefully.
        COALESCE(
            SUBSTRING(p.Tags, 2, POSITION('><' IN p.Tags) - 2),
            'Untagged'
        ) AS PrimaryTag,
        -- Evaluates 'Controversy Score' based on edits, views, and comments.
        -- Uses complicated arithmetic and NULL logic.
        (
            pvc.CumulativeEditCount * 2.0 +
            COALESCE(p.CommentCount, 0) * 0.8 +
            CASE
                WHEN p.ViewCount IS NOT NULL AND p.ViewCount > 1000 THEN 5.0
                WHEN p.ViewCount IS NOT NULL AND p.ViewCount > 500 THEN 2.0
                ELSE 0.0
            END -
            COALESCE(p.Score, 0) * 0.1
        ) AS ControversyScore,
        -- String expression: Checks if the post body contains specific keywords.
        (p.Body ILIKE '%error%' OR p.Body ILIKE '%bug%' OR p.Body ILIKE '%issue%') AS ContainsProblemKeywords
    FROM Posts p
    LEFT JOIN PostVersionComplexity pvc ON p.Id = pvc.PostId
    WHERE
        p.PostTypeId IN (1, 2) -- Questions or Answers
        AND p.OwnerUserId IS NOT NULL
        AND p.CreationDate >= '2018-01-01'
        AND pvc.UniqueHistoryTypeCount >= 2 -- At least two distinct history types
        AND pvc.CumulativeEditCount >= 2 -- At least two edits
),
FinalUserPostAnalysis AS (
    -- CTE 4: Joins UserEngagementSummary with DetailedPostAnalysis,
    -- further filters for relevant user-post interactions.
    SELECT
        ues.UserId,
        ues.UserName,
        ues.TotalEngagementScore,
        ues.RepRankInCreationYear,
        dpa.PostId,
        dpa.PostTypeId,
        dpa.PostCreationDate,
        dpa.Title,
        dpa.PrimaryTag,
        dpa.ControversyScore,
        dpa.LastCloseReason,
        dpa.ContainsProblemKeywords,
        dpa.Score,
        dpa.ViewCount,
        dpa.CommentCount,
        -- Window function: Calculate average controversy score for posts by the same user.
        AVG(dpa.ControversyScore) OVER (PARTITION BY ues.UserId) AS AvgUserControversyScore,
        -- Window function: Rank posts by controversy score for each user.
        ROW_NUMBER() OVER (PARTITION BY ues.UserId ORDER BY dpa.ControversyScore DESC, dpa.PostCreationDate DESC) AS UserControversyRank,
        -- Combine title and primary tag for a complex display string, using NULL logic.
        COALESCE(
            UPPER(SUBSTRING(dpa.Title, 1, 1)) || LOWER(SUBSTRING(dpa.Title, 2)) || ' [' || dpa.PrimaryTag || ']',
            'UNKNOWN POST [' || dpa.PrimaryTag || ']'
        ) AS FormattedPostTitleTag
    FROM UserEngagementSummary ues
    JOIN DetailedPostAnalysis dpa ON ues.UserId = dpa.OwnerUserId
    WHERE
        dpa.Score >= 0
        AND dpa.ControversyScore > 10
        AND dpa.Title IS NOT NULL
        AND dpa.PrimaryTag != 'Untagged'
)
-- Main query: Selects and transforms final data, applies further filtering,
-- uses outer joins for related entities (links, accepted answers),
-- and incorporates complex predicates and set operations (simulated with IN/EXISTS).
SELECT
    fupa.UserId,
    fupa.UserName,
    fupa.TotalEngagementScore,
    fupa.FormattedPostTitleTag,
    fupa.ControversyScore,
    fupa.AvgUserControversyScore,
    fupa.UserControversyRank,
    fupa.LastCloseReason,
    fupa.ContainsProblemKeywords,
    COALESCE(lt.Name, 'No Related Link') AS RelatedLinkType,
    -- Outer join to fetch details about accepted answers if applicable.
    COALESCE(p_accepted.Title, 'No Accepted Answer') AS AcceptedAnswerTitle,
    -- Complicated calculation: Score-to-view ratio, handling division by zero.
    CASE
        WHEN fupa.ViewCount > 0 THEN CAST(fupa.Score AS NUMERIC) / fupa.ViewCount
        ELSE 0.0
    END AS ScoreToViewRatio,
    -- Correlated subquery in SELECT: Check if this user has any active bounty posts.
    EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = fupa.PostId
          AND v.VoteTypeId = 8 -- BountyStart
          AND v.UserId = fupa.UserId
          AND v.BountyAmount > 0
    ) AS HasActiveBounty,
    -- String expression: Generate a short unique post identifier.
    LEFT(MD5(CAST(fupa.PostId AS VARCHAR) || fupa.FormattedPostTitleTag), 8) AS PostHashId
FROM FinalUserPostAnalysis fupa
LEFT JOIN PostLinks pl ON fupa.PostId = pl.PostId AND pl.LinkTypeId = 1 -- Linked posts
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN Posts p_accepted ON fupa.PostTypeId = 1 AND fupa.PostId = p_accepted.AcceptedAnswerId -- Only for questions
WHERE
    fupa.RepRankInCreationYear <= 50 -- Top 50 users by rep in their creation year
    AND fupa.UserControversyRank <= 5 -- Top 5 most controversial posts per user
    AND fupa.TotalEngagementScore > 1000
    AND (
        fupa.LastCloseReason IS NOT NULL OR -- Post was closed
        fupa.ContainsProblemKeywords        -- Or body contains problem keywords
    )
    AND NOT EXISTS (
        -- Exclude posts that were deleted and then undeleted within a short period,
        -- indicating potential moderation noise rather than genuine controversy.
        SELECT 1
        FROM PostVersionComplexity pvc_inner
        WHERE pvc_inner.PostId = fupa.PostId
          AND pvc_inner.PostHistoryTypeId = 12 -- Post Deleted
          AND EXISTS (
              SELECT 1
              FROM PostVersionComplexity pvc_undelete
              WHERE pvc_undelete.PostId = pvc_inner.PostId
                AND pvc_undelete.PostHistoryTypeId = 13 -- Post Undeleted
                AND pvc_undelete.HistoryDate BETWEEN pvc_inner.HistoryDate AND pvc_inner.HistoryDate + INTERVAL '1 hour'
          )
    )
    -- Simulating a 'set operator' style filter: Only include posts that also appear
    -- in a separate criterion (e.g., questions with at least 3 answers and 2 comments).
    AND fupa.PostId IN (
        SELECT p_set.Id
        FROM Posts p_set
        WHERE p_set.PostTypeId = 1 -- Questions
          AND p_set.AnswerCount >= 3
          AND p_set.CommentCount >= 2
          AND p_set.CreationDate BETWEEN fupa.PostCreationDate - INTERVAL '90 days' AND fupa.PostCreationDate + INTERVAL '90 days'
    )
ORDER BY
    fupa.TotalEngagementScore DESC,
    fupa.ControversyScore DESC,
    ScoreToViewRatio DESC
LIMIT 200;
