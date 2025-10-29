-- {"query": "1811.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3501} 
WITH UserPostStats AS (
    -- Aggregates user activity, including post and comment counts, and badge information
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(p.Score, 0.0)) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavoritesReceived,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN c.CreationDate > u.LastAccessDate - INTERVAL '30 days' THEN 1 ELSE 0 END) AS RecentComments,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2015-01-01' AND u.Reputation > 500
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostDetailsExtended AS (
    -- Enriches post details with various aggregated metrics and flags, and includes correlated subqueries
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.Body,
        p.OwnerUserId,
        p.LastEditorUserId,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        -- Correlated subquery: effective comment count by actual users
        (SELECT COUNT(DISTINCT co.Id) FROM Comments AS co WHERE co.PostId = p.Id AND co.UserId IS NOT NULL) AS EffectiveCommentCount,
        -- Correlated subquery: latest upvote date
        (SELECT MAX(vo.CreationDate) FROM Votes AS vo WHERE vo.PostId = p.Id AND vo.VoteTypeId = 2) AS LatestUpvoteDate,
        -- Correlated subquery: latest downvote date
        (SELECT MAX(vo.CreationDate) FROM Votes AS vo WHERE vo.PostId = p.Id AND vo.VoteTypeId = 3) AS LatestDownvoteDate,
        COALESCE(p.FavoriteCount, 0) AS ActualFavoriteCount,
        -- NULL logic and conditional expression
        CASE
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL AND p.AcceptedAnswerId > 0 THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= '2018-01-01'
    AND (p.ViewCount > 1000 OR (p.PostTypeId = 2 AND p.Score > 50 AND p.ParentId IS NOT NULL))
),
PostHistoryAggregates AS (
    -- Aggregates post history events, focusing on edits, closes, and reopens
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosedEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenedEvents,
        MAX(ph.CreationDate) AS LastHistoryUpdate,
        MIN(ph.CreationDate) AS FirstHistoryEntry,
        STRING_AGG(DISTINCT ph.Comment, '; ' ORDER BY ph.Comment) AS HistoryCommentsString
    FROM PostHistory AS ph
    WHERE ph.CreationDate >= '2019-01-01'
    GROUP BY ph.PostId
),
PostLinkAnalysis AS (
    -- Analyzes linked and duplicate posts
    SELECT
        pl.PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedToCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateOfCount,
        STRING_AGG(DISTINCT CAST(pl.RelatedPostId AS TEXT), ', ' ORDER BY CAST(pl.RelatedPostId AS TEXT)) AS RelatedPostIdsList
    FROM PostLinks AS pl
    GROUP BY pl.PostId
),
RankedPostsByActivity AS (
    -- Applies window functions to rank posts based on various criteria
    SELECT
        pde.*,
        ROW_NUMBER() OVER (PARTITION BY pde.PostTypeId ORDER BY pde.PostScore DESC, pde.ViewCount DESC, pde.PostId) AS RankOverallScoreViews,
        DENSE_RANK() OVER (PARTITION BY pde.PostTypeId ORDER BY pde.PostCommentCount DESC, pde.PostId) AS RankComments,
        AVG(pde.PostScore) OVER (PARTITION BY EXTRACT(YEAR FROM pde.PostCreationDate)) AS AvgYearlyPostScore,
        NTILE(4) OVER (ORDER BY pde.ViewCount DESC) AS ViewCountQuartile,
        LAG(pde.PostCreationDate, 1, pde.PostCreationDate) OVER (PARTITION BY pde.OwnerUserId ORDER BY pde.PostCreationDate) AS PrevPostCreationDate,
        FIRST_VALUE(pde.Title) OVER (PARTITION BY pde.OwnerUserId ORDER BY pde.PostCreationDate) AS FirstPostTitleByOwner
    FROM PostDetailsExtended AS pde
    WHERE pde.ViewCount IS NOT NULL AND pde.PostScore IS NOT NULL
),
ClosedDuplicateQuestions AS (
    -- Identifies posts closed specifically as duplicates
    SELECT
        ph.PostId,
        STRING_AGG(DISTINCT crt.Name, ', ' ORDER BY crt.Name) AS CloseReasonNames,
        MAX(ph.CreationDate) AS LastClosedDate
    FROM PostHistory AS ph
    JOIN CloseReasonTypes AS crt ON CAST(ph.Comment AS SMALLINT) = crt.Id
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
      AND ph.Comment IN ('1', '101') -- Old: Exact Duplicate, New: Duplicate
    GROUP BY ph.PostId
),
ReopenedQuestions AS (
    -- Identifies posts that were reopened
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastReopenedDate
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId = 11 -- Post Reopened
    GROUP BY ph.PostId
),
QuestionsClosedThenReopened AS (
    -- Finds questions that were closed as duplicate and later reopened, using an implicit set operator (join + filter)
    SELECT
        cdq.PostId,
        cdq.CloseReasonNames,
        cdq.LastClosedDate,
        rq.LastReopenedDate
    FROM ClosedDuplicateQuestions AS cdq
    JOIN ReopenedQuestions AS rq ON cdq.PostId = rq.PostId
    WHERE rq.LastReopenedDate > cdq.LastClosedDate
)
SELECT
    rps.PostId,
    rps.Title,
    rps.PostTypeName,
    rps.PostCreationDate,
    rps.PostScore,
    rps.ViewCount,
    rps.ActualFavoriteCount,
    ups.DisplayName AS PostOwnerDisplayName,
    ups.Reputation AS PostOwnerReputation,
    ups.GoldBadges,
    ups.SilverBadges,
    ups.BronzeBadges,
    pha.TotalEdits,
    pha.TotalClosedEvents,
    pha.TotalReopenedEvents,
    pla.LinkedToCount,
    pla.DuplicateOfCount,
    rps.HasAcceptedAnswer,
    rps.RankOverallScoreViews,
    rps.RankComments,
    rps.AvgYearlyPostScore,
    rps.ViewCountQuartile,
    -- Complex calculation: days from creation to last activity
    (EXTRACT(EPOCH FROM (rps.LastActivityDate - rps.PostCreationDate)) / (60 * 60 * 24)) AS DaysSinceCreationToLastActivity,
    -- String expressions and NULL logic
    COALESCE(NULLIF(LENGTH(TRIM(rps.Tags)), 0), 0) AS TagsLength,
    LENGTH(COALESCE(rps.Title, '')) AS TitleLength,
    CASE
        WHEN rps.ClosedDate IS NOT NULL AND rps.LastEditDate IS NOT NULL AND rps.ClosedDate < rps.LastEditDate THEN 'ClosedAfterEdit'
        WHEN rps.ClosedDate IS NOT NULL THEN 'ClosedBeforeEdit'
        ELSE 'NotClosed'
    END AS ClosureStatus,
    -- NULL logic with conditional string result
    COALESCE(qctr.CloseReasonNames, 'N/A') AS DuplicateCloseReasonIfReopened,
    -- String manipulation functions
    UPPER(LEFT(COALESCE(rps.Title, 'NO_TITLE'), 15)) AS TitlePrefixUpper,
    REPLACE(REPLACE(LOWER(COALESCE(rps.Tags, '')), '><', ','), '<', '') AS CleanedTagsCsv,
    -- Correlated subquery for counting distinct external editors
    (SELECT COUNT(DISTINCT ph_inner.UserId)
     FROM PostHistory AS ph_inner
     WHERE ph_inner.PostId = rps.PostId
       AND ph_inner.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
       AND ph_inner.CreationDate > rps.PostCreationDate + INTERVAL '1 hour'
       AND ph_inner.UserId IS NOT NULL
       AND ph_inner.UserId <> COALESCE(rps.OwnerUserId, -2) -- Exclude owner and community user (-1) or non-existent (-2)
    ) AS CoEditorCount,
    -- Correlated subquery for average bounty amount
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rps.PostId AND v.VoteTypeId = 8 AND v.CreationDate BETWEEN rps.PostCreationDate AND rps.LastActivityDate) AS AvgBountyAmountOffered,
    -- Correlated subquery for bounty received by owner
    (SELECT COALESCE(SUM(v_inner.BountyAmount), 0)
     FROM Votes v_inner
     WHERE v_inner.PostId = rps.PostId
       AND v_inner.VoteTypeId = 9 -- BountyClose
       AND v_inner.UserId = rps.OwnerUserId
    ) AS OwnerReceivedBountyTotal,
    -- Complex predicate/calculation with subquery and NULL handling
    CASE
        WHEN rps.PostTypeId = 1 AND rps.AnswerCount IS NOT NULL AND rps.AnswerCount > 0
             AND rps.PostScore > (SELECT AVG(p_avg.Score) FROM Posts p_avg WHERE p_avg.PostTypeId = 1 AND p_avg.CreationDate BETWEEN rps.PostCreationDate - INTERVAL '30 days' AND rps.PostCreationDate)
             AND rps.HasAcceptedAnswer IS TRUE THEN TRUE
        ELSE FALSE
    END AS HighPerformingQuestionWithAcceptedAnswer,
    rps.LatestUpvoteDate,
    rps.LatestDownvoteDate,
    rps.PrevPostCreationDate,
    rps.FirstPostTitleByOwner,
    -- Correlated subquery for comment score after first day
    (SELECT COALESCE(SUM(co.Score), 0)
     FROM Comments co
     WHERE co.PostId = rps.PostId
       AND co.CreationDate > rps.PostCreationDate + INTERVAL '1 day'
    ) AS PostCommentScoreAfterDayOne
FROM RankedPostsByActivity AS rps
LEFT JOIN UserPostStats AS ups ON rps.OwnerUserId = ups.UserId
LEFT JOIN PostHistoryAggregates AS pha ON rps.PostId = pha.PostId
LEFT JOIN PostLinkAnalysis AS pla ON rps.PostId = pla.PostId
LEFT JOIN QuestionsClosedThenReopened AS qctr ON rps.PostId = qctr.PostId
WHERE
    rps.PostScore > 50
    AND rps.ViewCount > 5000
    AND rps.PostCreationDate BETWEEN '2020-01-01' AND '2023-01-01'
    -- Complicated predicate combining multiple conditions
    AND (
        (ups.TotalQuestions IS NOT NULL AND ups.TotalQuestions > 5) OR
        (ups.TotalAnswers IS NOT NULL AND ups.TotalAnswers > 10) OR
        (ups.GoldBadges IS NOT NULL AND ups.GoldBadges > 0)
    )
    -- String matching in title or tags (case-insensitive)
    AND (LOWER(rps.Title) LIKE '%performance%' OR LOWER(rps.Tags) LIKE '%<benchmark>%')
    -- Conditional filtering based on PostType and related metrics
    AND (
        (rps.PostTypeId = 1 AND rps.HasAcceptedAnswer IS TRUE AND rps.RankOverallScoreViews <= 100) -- Top 100 questions with accepted answers
        OR
        (rps.PostTypeId = 2 AND rps.PostScore >= 100 AND rps.RankComments <= 50) -- Top 50 answers by comments AND high score
    )
    -- Filtering on post history and links, handling NULLs
    AND (pha.TotalEdits IS NULL OR pha.TotalEdits <= 10)
    AND (pla.DuplicateOfCount IS NULL OR pla.DuplicateOfCount = 0)
    -- Exclude posts that were closed as duplicate and then reopened (implicit EXCEPT logic)
    AND qctr.PostId IS NULL
ORDER BY
    rps.AvgYearlyPostScore DESC,
    COALESCE(ups.GoldBadges, 0) DESC,
    rps.LastActivityDate DESC,
    rps.PostScore DESC
LIMIT 1000;