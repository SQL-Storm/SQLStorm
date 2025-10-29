-- {"query": "1961.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2694} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        u.Reputation,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / (60 * 60 * 24) AS AccountAgeDays,
        COUNT(DISTINCT p.Id) AS TotalOwnedPosts,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        u.LastAccessDate,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score ELSE NULL END) AS AvgOwnedPostScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgOwnedQuestionViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostDetailedMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.Title,
        p.Body,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        p.LastEditDate,
        p.LastActivityDate,
        p.Tags,
        (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6,8,9)) AS NumDistinctEditors,
        (SELECT COUNT(ph2.Id) FROM PostHistory ph2 WHERE ph2.PostId = p.Id) AS TotalPostHistoryEvents,
        COALESCE(EXTRACT(EPOCH FROM (p.LastActivityDate - p.LastEditDate)) / (60 * 60 * 24), 0) AS DaysSinceLastEdit,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate)) / (60 * 60 * 24) AS PostAgeDays,
        (CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END) AS HasAcceptedAnswer,
        -- Extract the first tag (assuming format like '<tag1><tag2>...>')
        SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags) - 2) AS FirstTag
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
PostEventTimelines AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.CreationDate AS HistoryDate,
        LAG(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate,
        LEAD(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextEventDate,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / (60 * 60) AS HoursSincePrevEvent,
        COALESCE(ph.UserId, -1) AS HistoryUserId
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
),
AggregatedTagStats AS (
    SELECT
        SPLIT_PART(SUBSTRING(t.Tags, 2, LENGTH(t.Tags) - 2), '><', n.N) AS TagName,
        COUNT(DISTINCT t.Id) AS TotalQuestionsWithTag,
        AVG(t.ViewCount) AS AvgViewsForTagQuestions,
        SUM(t.AnswerCount) AS TotalAnswersForTagQuestions,
        SUM(CASE WHEN t.PostTypeId = 1 THEN t.FavoriteCount ELSE 0 END) AS TotalQuestionFavorites,
        COUNT(b.Id) AS TotalBadgesForTag
    FROM Posts t
    CROSS JOIN (SELECT GENERATE_SERIES(1, 5) AS N) n -- assuming max 5 tags per post for performance; adjust as needed
    LEFT JOIN Badges b ON b.TagBased = TRUE AND b.Name = SPLIT_PART(SUBSTRING(t.Tags, 2, LENGTH(t.Tags) - 2), '><', n.N)
    WHERE t.PostTypeId = 1 AND t.Tags IS NOT NULL AND LENGTH(TRIM(t.Tags)) > 2 AND SPLIT_PART(SUBSTRING(t.Tags, 2, LENGTH(t.Tags) - 2), '><', n.N) IS NOT NULL
    GROUP BY SPLIT_PART(SUBSTRING(t.Tags, 2, LENGTH(t.Tags) - 2), '><', n.N)
    HAVING COUNT(DISTINCT t.Id) > 100 -- Only consider tags with substantial usage
),
UserVoteInfluence AS (
    SELECT
        u.Id AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN p.Score ELSE -p.Score END) AS WeightedVoteImpact -- Hypothetical impact based on votes given
    FROM Users u
    JOIN Votes v ON u.Id = v.UserId
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.VoteTypeId IN (2, 3) -- UpMod, DownMod
    GROUP BY u.Id
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.AccountAgeDays,
    uas.TotalOwnedPosts,
    uas.TotalCommentsMade,
    pdm.PostId,
    pdm.PostTypeName,
    pdm.Title,
    pdm.Score AS PostScore,
    pdm.ViewCount AS PostViewCount,
    pdm.AnswerCount,
    pdm.CommentCount AS PostCommentCount,
    pdm.HasAcceptedAnswer,
    pdm.NumDistinctEditors,
    pdm.TotalPostHistoryEvents,
    pdm.DaysSinceLastEdit,
    pdm.PostAgeDays,
    pdm.FirstTag,
    ats.AvgViewsForTagQuestions AS FirstTagAvgViews,
    ats.TotalBadgesForTag AS FirstTagBadges,
    uvi.TotalUpVotesGiven,
    uvi.TotalDownVotesGiven,
    uvi.WeightedVoteImpact,
    RANK() OVER (PARTITION BY uas.UserId ORDER BY pdm.Score DESC, pdm.ViewCount DESC) AS RankWithinUserPosts,
    NTILE(5) OVER (ORDER BY pdm.Score DESC, pdm.ViewCount DESC) AS OverallPostScoreQuintile,
    (SELECT COUNT(DISTINCT ph_inner.PostId)
     FROM PostHistory ph_inner
     WHERE ph_inner.UserId = uas.UserId
       AND ph_inner.CreationDate > uas.LastAccessDate - INTERVAL '30 days'
       AND ph_inner.PostHistoryTypeId IN (4, 5, 6)) AS UserRecentEditsCount, -- Correlated subquery 1
    (SELECT SUM(CASE WHEN v_inner.VoteTypeId = 2 THEN 1 WHEN v_inner.VoteTypeId = 3 THEN -1 ELSE 0 END)
     FROM Votes v_inner
     WHERE v_inner.PostId = pdm.PostId
       AND v_inner.CreationDate BETWEEN pdm.CreationDate AND pdm.CreationDate + INTERVAL '7 days'
       AND v_inner.UserId IS NOT NULL -- Exclude community votes if any for this calculation
    ) AS NetVotesFirstWeek, -- Non-correlated subquery (to the main outer query, but correlated to pdm)
    COALESCE(pet.HoursSincePrevEvent, 0) AS HoursFromLastPostEvent,
    CASE
        WHEN pdm.Score > 100 AND pdm.ViewCount > 5000 AND pdm.AnswerCount > 2 THEN 'HighImpact'
        WHEN pdm.Score > 50 AND pdm.ViewCount > 1000 THEN 'MediumImpact'
        ELSE 'LowImpact'
    END AS PostImpactCategory,
    'https://stackoverflow.com/questions/' || pdm.PostId || '/' || REPLACE(LOWER(SUBSTRING(COALESCE(pdm.Title, 'no-title'), 1, 50)), ' ', '-') AS PostUrlSnippet -- Complex string expression
FROM UserActivitySummary uas
LEFT JOIN PostDetailedMetrics pdm ON uas.UserId = pdm.OwnerUserId
LEFT JOIN AggregatedTagStats ats ON pdm.FirstTag = ats.TagName
LEFT JOIN PostEventTimelines pet ON pdm.PostId = pet.PostId AND pet.PostHistoryTypeId = 5 -- Specific to body edit events
LEFT JOIN UserVoteInfluence uvi ON uas.UserId = uvi.UserId
WHERE
    uas.Reputation > 5000
    AND pdm.PostTypeId = 1 -- Focus on questions
    AND pdm.CreationDate >= CURRENT_DATE - INTERVAL '5 years' -- Recent posts
    AND pdm.Score > 10 -- Only consider reasonably scored posts
    AND pdm.Title IS NOT NULL
    AND pdm.Tags IS NOT NULL
    AND (
        pdm.FirstTag LIKE 'sql%'
        OR pdm.FirstTag LIKE 'database%'
        OR pdm.FirstTag LIKE 'performance%'
    )
    AND EXISTS ( -- Correlated subquery 2: check if the user has any gold badges related to the first tag
        SELECT 1 FROM Badges b_sub
        WHERE b_sub.UserId = uas.UserId
          AND b_sub.Class = 1
          AND b_sub.TagBased = TRUE
          AND b_sub.Name = pdm.FirstTag
    )
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.AccountAgeDays, uas.TotalOwnedPosts, uas.TotalCommentsMade,
    pdm.PostId, pdm.PostTypeName, pdm.Title, pdm.Score, pdm.ViewCount, pdm.AnswerCount, pdm.CommentCount,
    pdm.HasAcceptedAnswer, pdm.NumDistinctEditors, pdm.TotalPostHistoryEvents, pdm.DaysSinceLastEdit,
    pdm.PostAgeDays, pdm.FirstTag, ats.AvgViewsForTagQuestions, ats.TotalBadgesForTag,
    uvi.TotalUpVotesGiven, uvi.TotalDownVotesGiven, uvi.WeightedVoteImpact,
    pet.HoursSincePrevEvent, uas.LastAccessDate, pdm.CreationDate
HAVING
    COUNT(pdm.PostId) > 0 -- Ensure at least one qualifying post per user
ORDER BY
    uas.Reputation DESC,
    pdm.Score DESC,
    pdm.CreationDate DESC
LIMIT 1000;
