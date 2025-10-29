-- {"query": "1040.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3783} 

WITH UserActivitySummary AS (
    -- Gathers comprehensive activity metrics for each user, including badge counts and engagement scores.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersCreated,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(p.Score, 0)) AS TotalPostsScoreReceived,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentsScoreReceived,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (CAST(u.UpVotes AS NUMERIC) / NULLIF(u.UpVotes + u.DownVotes, 0)) AS UpVoteRatioGiven,
        DATE_PART('day', NOW() - u.LastAccessDate) AS DaysSinceLastAccess,
        -- Calculate a composite engagement score, normalizing by user's active tenure
        (SUM(COALESCE(p.Score, 0) * 1.5) + SUM(COALESCE(p.ViewCount, 0) * 0.1) + SUM(COALESCE(p.FavoriteCount, 0) * 2) + SUM(COALESCE(c.Score, 0) * 0.5)) /
            NULLIF(DATE_PART('day', NOW() - u.CreationDate) + 1, 0) AS UserEngagementScorePerDay
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostHistoricalEvolution AS (
    -- Tracks detailed post history, including edit counts, close/reopen events, and editor activity.
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS TotalEditRevisions, -- Title, Body, Tags edits
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS TotalCloseEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS TotalReopenEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.Id END) AS TotalDeleteEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.Id END) AS TotalUndeleteEvents,
        MIN(ph.CreationDate) AS FirstHistoryEntryDate,
        MAX(ph.CreationDate) AS LastHistoryEntryDate,
        -- Aggregates distinct CloseReasonType Ids from comments in close history events.
        STRING_AGG(DISTINCT crt.Id::VARCHAR, ';') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND ph.Comment ~ '^[0-9]+$') AS AggregatedCloseReasonIds,
        -- Correlated subquery to find the most recent editor's ID
        (
            SELECT phed.UserId
            FROM PostHistory phed
            WHERE phed.PostId = ph.PostId AND phed.CreationDate = MAX(ph.CreationDate)
            ORDER BY phed.Id DESC LIMIT 1
        ) AS LastEditorUserId,
        -- Calculate average time between edits by the same user on the same post
        AVG(EXTRACT(EPOCH FROM (ph_next.CreationDate - ph.CreationDate)) / 3600.0) FILTER (WHERE ph_next.UserId = ph.UserId) AS AvgHoursBetweenSelfEdits
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND crt.Id = CAST(ph.Comment AS SMALLINT)
    LEFT JOIN LATERAL (
        SELECT ph_inner.CreationDate, ph_inner.UserId
        FROM PostHistory ph_inner
        WHERE ph_inner.PostId = ph.PostId AND ph_inner.CreationDate > ph.CreationDate
        ORDER BY ph_inner.CreationDate
        LIMIT 1
    ) AS ph_next ON TRUE
    GROUP BY ph.PostId
),
QuestionDetailedMetrics AS (
    -- Focuses on questions, their tags, answer engagement, and links to other posts.
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.ClosedDate,
        q.CommunityOwnedDate,
        q.Title AS QuestionTitle,
        q.Tags AS QuestionTagsString,
        LENGTH(q.Body) AS QuestionBodyLength,
        COALESCE(q.LastEditDate, q.CreationDate) AS EffectiveLastEditDate,
        -- Time difference to first answer, if available
        DATE_PART('day', (SELECT MIN(a.CreationDate) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) - q.CreationDate) AS DaysToFirstAnswer,
        -- Extract up to the first two tags
        SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2) AS CleanTags,
        TRIM(SPLIT_PART(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><', 1)) AS FirstTag,
        TRIM(SPLIT_PART(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><', 2)) AS SecondTag,
        -- Correlated subquery: Get the total score of all answers for this question
        (SELECT SUM(s.Score) FROM Posts s WHERE s.ParentId = q.Id AND s.PostTypeId = 2) AS TotalAnswerScore,
        -- Correlated subquery: Check if the question has a highly upvoted answer (>50 score)
        EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2 AND a.Score > 50) AS HasHighScoringAnswer,
        -- Calculate Question-to-Answer score ratio
        CAST(q.Score AS NUMERIC) / NULLIF(q.AnswerCount, 0) AS ScorePerAnswer,
        -- Count of linked/duplicate posts
        COUNT(DISTINCT pl.RelatedPostId) AS TotalRelatedPosts,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinks
    FROM Posts q
    LEFT JOIN PostLinks pl ON q.Id = pl.PostId
    WHERE q.PostTypeId = 1 -- Only questions
    GROUP BY q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount,
             q.ClosedDate, q.CommunityOwnedDate, q.Title, q.Tags, q.Body, q.LastEditDate
),
CommentEngagementSummary AS (
    -- Aggregates comment statistics for each post.
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalCommentsOnPost,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        SUM(c.Score) AS TotalCommentScoreOnPost,
        MAX(c.CreationDate) AS LastCommentDateOnPost,
        ARRAY_AGG(DISTINCT COALESCE(u.DisplayName, c.UserDisplayName)) FILTER (WHERE COALESCE(u.DisplayName, c.UserDisplayName) IS NOT NULL) AS DistinctCommenterNames
    FROM Comments c
    LEFT JOIN Users u ON c.UserId = u.Id
    GROUP BY c.PostId
),
UserPostTagsContribution AS (
    -- Analyzes user's contribution to tags by total score.
    SELECT
        p.OwnerUserId AS UserId,
        TRIM(SPLIT_PART(UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')), ' ', 1)) AS TagName,
        SUM(p.Score) AS TotalTagScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags != ''
    GROUP BY p.OwnerUserId, TagName
)
-- The main query to combine all insights, perform complex filtering, and apply window functions.
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.DaysSinceLastAccess,
    uas.TotalPostsCreated,
    uas.TotalQuestionsCreated,
    uas.TotalAnswersCreated,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.UserEngagementScorePerDay,
    q.QuestionId,
    q.QuestionTitle,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.QuestionBodyLength,
    q.QuestionTagsString,
    q.CleanTags,
    q.FirstTag,
    q.SecondTag,
    q.TotalAnswerScore,
    q.HasHighScoringAnswer,
    q.ScorePerAnswer,
    q.TotalRelatedPosts,
    q.DuplicateLinks,
    phe.TotalHistoryEntries,
    phe.TotalEditRevisions,
    phe.TotalCloseEvents,
    phe.TotalReopenEvents,
    phe.TotalDeleteEvents,
    phe.TotalUndeleteEvents,
    phe.AggregatedCloseReasonIds,
    phe.AvgHoursBetweenSelfEdits,
    ces.TotalCommentsOnPost,
    ces.UniqueCommenters,
    ces.TotalCommentScoreOnPost,
    ces.LastCommentDateOnPost,
    DATE_PART('day', q.EffectiveLastEditDate - q.QuestionCreationDate) AS DaysToLastEdit,
    q.DaysToFirstAnswer,
    -- Window Function: Rank users within different reputation quartiles based on their overall engagement.
    NTILE(4) OVER (ORDER BY uas.Reputation DESC) AS ReputationQuartile,
    RANK() OVER (PARTITION BY NTILE(4) OVER (ORDER BY uas.Reputation DESC) ORDER BY uas.UserEngagementScorePerDay DESC, uas.TotalPostsScoreReceived DESC) AS EngagementRankInReputationQuartile,
    -- Window Function: Calculate average score of questions created by users with similar creation year.
    AVG(q.QuestionScore) OVER (PARTITION BY EXTRACT(YEAR FROM uas.UserCreationDate)) AS AvgQuestionScoreByCreationYear,
    -- Lag/Lead: Get the previous and next question score for the same user, ordered by creation date.
    LAG(q.QuestionScore, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY q.QuestionCreationDate) AS PrevQuestionScore,
    LEAD(q.QuestionScore, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY q.QuestionCreationDate) AS NextQuestionScore,
    -- Complex CASE expression to flag potentially problematic or high-value posts.
    CASE
        WHEN q.ClosedDate IS NOT NULL AND phe.TotalReopenEvents > 0 AND q.QuestionScore < 0 THEN 'HighlyContentious_ClosedReopenedNegativeScore'
        WHEN q.AnswerCount = 0 AND q.QuestionCreationDate < NOW() - INTERVAL '1 year' AND q.ViewCount > 5000 THEN 'OldUnansweredHighView'
        WHEN q.DistinctAnswerers > 5 AND q.TotalAnswerScore < q.QuestionScore * 0.5 THEN 'ManyAnswerersLowTotalAnswerScore'
        WHEN phe.TotalEditRevisions > 10 AND phe.TotalCloseEvents > 1 THEN 'HyperEditedAndFrequentlyClosed'
        WHEN q.HasHighScoringAnswer AND q.QuestionScore < 0 THEN 'NegativeQuestion_PositiveAnswer'
        ELSE 'NormalEngagement'
    END AS QuestionAnalysisFlag,
    -- Identify users who consistently edit their posts frequently.
    (phe.AvgHoursBetweenSelfEdits < 24 AND phe.TotalEditRevisions > 5 AND phe.LastEditorUserId = uas.UserId) AS ConsistentlySelfEditingOwner,
    -- String manipulation to check for a specific tag and user location.
    (u.Location ILIKE '%London%' AND q.QuestionTagsString LIKE '%<sql>%') AS LondonSQLContributor,
    -- Join to get human-readable close reason names.
    STRING_AGG(DISTINCT crt.Name, ', ') AS AllCloseReasonNames
FROM UserActivitySummary uas
INNER JOIN Posts main_p ON uas.UserId = main_p.OwnerUserId AND main_p.PostTypeId = 1 -- Focus on questions owned by active users
INNER JOIN QuestionDetailedMetrics q ON main_p.Id = q.QuestionId
LEFT JOIN PostHistoricalEvolution phe ON q.QuestionId = phe.PostId
LEFT JOIN CommentEngagementSummary ces ON q.QuestionId = ces.PostId
LEFT JOIN Users u ON uas.UserId = u.Id -- Re-join to get location for specialized filtering
LEFT JOIN UNNEST(STRING_TO_ARRAY(phe.AggregatedCloseReasonIds, ';')) AS close_reason_id ON TRUE
LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(close_reason_id AS SMALLINT)
WHERE
    uas.Reputation > 10000
    AND uas.TotalQuestionsCreated >= 5
    AND uas.SilverBadges >= 3
    AND q.QuestionScore >= 50
    AND q.ViewCount > 1000
    AND (
        (q.ClosedDate IS NOT NULL AND phe.TotalReopenEvents > 0) OR -- Questions closed and then reopened
        (q.AnswerCount = 0 AND q.QuestionCreationDate < NOW() - INTERVAL '1 year') OR -- Old unanswered questions
        (phe.TotalEditRevisions > 7 AND q.QuestionScore < 10) -- Heavily edited but low-scoring questions
    )
    AND u.Location IS NOT NULL AND uas.DisplayName IS NOT NULL
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.UserCreationDate, uas.DaysSinceLastAccess,
    uas.TotalPostsCreated, uas.TotalQuestionsCreated, uas.TotalAnswersCreated,
    uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges, uas.UserEngagementScorePerDay,
    q.QuestionId, q.QuestionTitle, q.QuestionScore, q.ViewCount, q.AnswerCount, q.FavoriteCount,
    q.QuestionBodyLength, q.QuestionTagsString, q.CleanTags, q.FirstTag, q.SecondTag,
    q.TotalAnswerScore, q.HasHighScoringAnswer, q.ScorePerAnswer, q.TotalRelatedPosts, q.DuplicateLinks,
    phe.TotalHistoryEntries, phe.TotalEditRevisions, phe.TotalCloseEvents, phe.TotalReopenEvents,
    phe.TotalDeleteEvents, phe.TotalUndeleteEvents, phe.AggregatedCloseReasonIds, phe.LastEditorUserId, phe.AvgHoursBetweenSelfEdits,
    ces.TotalCommentsOnPost, ces.UniqueCommenters, ces.TotalCommentScoreOnPost, ces.LastCommentDateOnPost,
    q.EffectiveLastEditDate, q.QuestionCreationDate, q.DaysToFirstAnswer, u.Location, q.ClosedDate
ORDER BY
    uas.UserEngagementScorePerDay DESC, q.QuestionScore DESC, uas.Reputation DESC
LIMIT 250;
