-- {"query": "1117.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2334} 

WITH UserPerformanceSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        NTILE(5) OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS ReputationQuintile,
        RANK() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, COUNT(DISTINCT b.Id) DESC) AS UserOverallRank,
        (u.Reputation * 0.7 + u.UpVotes * 0.2 + COUNT(DISTINCT b.Id) * 0.1) AS WeightedUserScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
    HAVING u.Reputation > 500 AND COUNT(DISTINCT b.Id) >= 5
),
QuestionDetailedMetrics AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Title,
        p.Body,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.Tags,
        p.ClosedDate,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        DATE_PART('day', p.LastActivityDate - p.CreationDate) AS DaysActive,
        COALESCE(p.FavoriteCount, 0) + p.Score * 2 + p.ViewCount / 100 + COALESCE(p.AnswerCount, 0) * 5 AS CalculatedImpactScore,
        -- Check for common problematic tags
        (LOWER(p.Tags) LIKE '%<javascript>%' OR LOWER(p.Tags) LIKE '%<typescript>%') AS IsFrontendTag,
        (LOWER(p.Tags) LIKE '%<java>%' OR LOWER(p.Tags) LIKE '%<.net>%') AS IsBackendTag,
        string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.CreationDate >= '2021-01-01' -- Recent questions for relevance
      AND p.ViewCount > 1000 -- Sufficiently popular questions
      AND p.OwnerUserId IS NOT NULL -- Not community wiki owned by default for this analysis
),
PostHistoryTimeline AS (
    SELECT
        ph.Id AS HistoryId,
        ph.PostId,
        ph.CreationDate AS HistoryEventDate,
        ph.PostHistoryTypeId,
        ph.Comment,
        -- Get the specific close reason name if available, else NULL
        (SELECT crt.Name FROM CloseReasonTypes crt WHERE crt.Id = CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS smallint) ELSE NULL END) AS CloseReasonName,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11) -- Initial, edits, close, reopen
),
PostHistoryAggregated AS (
    SELECT
        PostId,
        COUNT(HistoryId) AS TotalHistoryEntries,
        SUM(CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseCount,
        MAX(CASE WHEN PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS HadReopenEvent,
        MAX(HistoryEventDate) AS LatestHistoryEvent,
        MIN(HistoryEventDate) AS EarliestHistoryEvent,
        -- Average time between history events for a post
        AVG(EXTRACT(EPOCH FROM (HistoryEventDate - PreviousHistoryDate))) FILTER (WHERE PreviousHistoryDate IS NOT NULL AND HistoryEventDate != PreviousHistoryDate) AS AvgSecondsBetweenHistoryEvents,
        STRING_AGG(DISTINCT CloseReasonName, '; ') FILTER (WHERE CloseReasonName IS NOT NULL) AS AllCloseReasons
    FROM PostHistoryTimeline
    GROUP BY PostId
),
RelatedPostInfo AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        p_rel.Score AS RelatedPostScore,
        p_rel.ViewCount AS RelatedPostViewCount,
        DENSE_RANK() OVER (PARTITION BY pl.PostId ORDER BY p_rel.Score DESC, p_rel.ViewCount DESC, p_rel.CreationDate DESC) AS RankOfRelatedPost
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p_rel ON pl.RelatedPostId = p_rel.Id
    WHERE lt.Name IN ('Linked', 'Duplicate')
)
SELECT
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalBadges,
    ups.GoldBadges,
    ups.ReputationQuintile,
    ups.UserOverallRank,
    qdm.QuestionId,
    qdm.Title AS QuestionTitle,
    qdm.QuestionCreationDate,
    qdm.QuestionScore,
    qdm.ViewCount AS QuestionViewCount,
    qdm.AnswerCount,
    qdm.FavoriteCount,
    qdm.CalculatedImpactScore,
    qda.TotalEditCount,
    qda.TotalCloseCount,
    qda.HadReopenEvent,
    qda.LatestHistoryEvent,
    qda.AllCloseReasons,
    qdm.IsFrontendTag,
    qdm.IsBackendTag,
    array_length(qdm.TagArray, 1) AS NumberOfTags,
    -- Correlated Subquery: Get the score of the accepted answer, if any
    (SELECT COALESCE(pa.Score, 0) FROM Posts pa WHERE pa.Id = qdm.AcceptedAnswerId AND pa.PostTypeId = 2) AS AcceptedAnswerScore,
    -- Correlated Subquery: Check if any of the tags indicate a specific topic (e.g., 'database' or 'sql')
    (SELECT EXISTS (
        SELECT 1
        FROM UNNEST(qdm.TagArray) AS t(tag_name)
        WHERE LOWER(t.tag_name) IN ('sql', 'database', 'postgresql', 'mysql', 'tsql')
    )) AS ContainsDatabaseTag,
    rpi.RelatedPostId,
    rpi.LinkTypeName,
    rpi.RelatedPostScore,
    rpi.RelatedPostViewCount,
    -- Calculate a weighted average of user's reputation and question's impact for posts created within 1 year
    AVG(ups.WeightedUserScore + qdm.CalculatedImpactScore * 0.5) OVER (PARTITION BY ups.ReputationQuintile ORDER BY qdm.QuestionCreationDate RANGE BETWEEN INTERVAL '1 year' PRECEDING AND CURRENT ROW) AS RollingWeightedScore,
    -- Rank questions by impact within each user's profile
    ROW_NUMBER() OVER (PARTITION BY ups.UserId ORDER BY qdm.CalculatedImpactScore DESC, qdm.QuestionCreationDate DESC) AS UserQuestionImpactRank,
    -- String expression and NULL logic for body preview
    COALESCE(SUBSTRING(qdm.Body, 1, 100), 'No body preview available') AS BodyPreview,
    CASE
        WHEN qdm.ClosedDate IS NOT NULL AND qda.HadReopenEvent = 1 THEN 'ClosedThenReopened'
        WHEN qdm.ClosedDate IS NOT NULL THEN 'PermanentlyClosed'
        WHEN qda.TotalEditCount > 5 AND qdm.QuestionScore > 50 THEN 'HighlyMaintainedHighImpact'
        WHEN qdm.DaysActive > 365 AND COALESCE(qdm.AnswerCount, 0) = 0 THEN 'StaleUnanswered'
        ELSE 'Active'
    END AS QuestionStatusCategory,
    DATE_PART('year', NOW()) - DATE_PART('year', ups.UserCreationDate) AS UserAccountAgeYears,
    EXTRACT(EPOCH FROM (NOW() - qdm.QuestionCreationDate)) / 3600 AS HoursSinceQuestionCreated
FROM UserPerformanceSummary ups
JOIN QuestionDetailedMetrics qdm ON ups.UserId = qdm.OwnerUserId
LEFT JOIN PostHistoryAggregated qda ON qdm.QuestionId = qda.PostId
LEFT JOIN RelatedPostInfo rpi ON qdm.QuestionId = rpi.PostId AND rpi.RankOfRelatedPost = 1 -- Only consider the top related post
WHERE ups.ReputationQuintile IN (1, 2) -- Top 40% of users by reputation
  AND qdm.CalculatedImpactScore > 200 -- Significant impact
  AND (qda.TotalEditCount > 2 OR qda.TotalCloseCount > 0 OR qda.HadReopenEvent = 1) -- Questions with significant history
  AND qdm.Title NOT ILIKE '%[bug]%' -- Exclude bug reports (case-insensitive)
  AND qdm.QuestionCreationDate BETWEEN ups.UserCreationDate AND ups.LastAccessDate -- Question within user's active period
  AND (rpi.RelatedPostScore IS NULL OR rpi.RelatedPostScore > 10) -- Either no related post, or related post also has some score
ORDER BY ups.UserOverallRank ASC, qdm.CalculatedImpactScore DESC, qda.LatestHistoryEvent DESC
LIMIT 1000;
