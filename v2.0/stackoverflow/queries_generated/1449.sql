-- {"query": "1449.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3159} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Views, 0) AS UserTotalViews,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        CAST(u.Reputation AS numeric) / (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / (3600 * 24) + 1) AS ReputationPerDay, -- Reputation gain per day
        COUNT(DISTINCT q.Id) AS TotalQuestionsAsked,
        COUNT(DISTINCT a.Id) AS TotalAnswersGiven,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN q.Id IS NOT NULL THEN COALESCE(q.Score, 0) ELSE 0 END) AS TotalQuestionScoreReceived,
        SUM(CASE WHEN a.Id IS NOT NULL THEN COALESCE(a.Score, 0) ELSE 0 END) AS TotalAnswerScoreReceived,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScoreReceived,
        COUNT(DISTINCT CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN q.Id END) AS QuestionsWithAcceptedAnswers,
        COUNT(DISTINCT CASE WHEN a.AcceptedAnswerId = a.Id THEN a.Id END) AS AnswersAcceptedByOthers
    FROM Users AS u
    LEFT JOIN Posts AS q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1 -- Questions owned by user
    LEFT JOIN Posts AS a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2 -- Answers owned by user
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    WHERE u.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '10 year') -- Focus on users created within the last 10 years
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Title,
        p.Body,
        p.Tags,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS ActualAnswerCount,
        COALESCE(p.CommentCount, 0) AS ActualCommentCount,
        COALESCE(p.FavoriteCount, 0) AS ActualFavoriteCount,
        COALESCE(p.ClosedDate, '9999-12-31 23:59:59') AS PostClosedDate, -- Use a far future date for open posts
        (p.Score * 0.6) + (p.ViewCount * 0.02) + (COALESCE(p.FavoriteCount, 0) * 1.5) + (COALESCE(p.AnswerCount, 0) * 1.0) + (COALESCE(p.CommentCount, 0) * 0.5) AS RawEngagementScore,
        COUNT(DISTINCT ph.Id) AS TotalPostHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        MAX(ph.CreationDate) AS LastPostEditDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 101) THEN 1 ELSE 0 END) AS CloseVotesReceived, -- Post Closed (old & new)
        SUM(CASE WHEN ph.PostHistoryTypeId IN (11) THEN 1 ELSE 0 END) AS ReopenVotesReceived, -- Post Reopened
        STRING_AGG(DISTINCT t.TagName, ' || ') FILTER (WHERE t.TagName IS NOT NULL) AS ParsedTagsAggregated
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName
        WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    ) AS t ON TRUE
    WHERE p.PostTypeId IN (1, 2) -- Questions or Answers
      AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '3 year') -- Recent posts
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Title, p.Body, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate
),
RankedAndFilteredPosts AS (
    SELECT
        pem.PostId,
        pem.PostTypeId,
        pem.OwnerUserId,
        pem.PostCreationDate,
        pem.LastActivityDate,
        pem.Title,
        pem.Body,
        pem.Tags,
        pem.Score,
        pem.ViewCount,
        pem.ActualAnswerCount,
        pem.ActualCommentCount,
        pem.ActualFavoriteCount,
        pem.PostClosedDate,
        pem.RawEngagementScore,
        pem.TotalPostHistoryEvents,
        pem.EditCount,
        pem.LastPostEditDate,
        pem.CloseVotesReceived,
        pem.ReopenVotesReceived,
        pem.ParsedTagsAggregated,
        RANK() OVER (PARTITION BY pem.PostTypeId ORDER BY pem.RawEngagementScore DESC, pem.LastActivityDate DESC) AS PostEngagementRank,
        NTILE(5) OVER (ORDER BY pem.RawEngagementScore DESC) AS PostEngagementTile,
        LAG(pem.LastPostEditDate, 1, pem.PostCreationDate) OVER (PARTITION BY pem.PostId ORDER BY pem.LastPostEditDate) AS PreviousEditDate
    FROM PostEngagementMetrics AS pem
    WHERE pem.RawEngagementScore > 100 -- Only significantly engaged posts
      AND pem.ViewCount > 50
),
UserBadgeAchievements AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadgesEarned,
        COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate,
        MIN(b.Date) AS FirstBadgeDate,
        CASE
            WHEN COUNT(CASE WHEN b.Class = 1 THEN 1 END) > 0 THEN 'Gold Tier'
            WHEN COUNT(CASE WHEN b.Class = 2 THEN 1 END) > 0 THEN 'Silver Tier'
            WHEN COUNT(CASE WHEN b.Class = 3 THEN 1 END) > 0 THEN 'Bronze Tier'
            ELSE 'No Tier'
        END AS UserBadgeTier
    FROM Badges AS b
    GROUP BY b.UserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.ReputationPerDay,
    uas.TotalQuestionsAsked,
    uas.TotalAnswersGiven,
    uas.TotalCommentsMade,
    uas.TotalQuestionScoreReceived,
    uas.TotalAnswerScoreReceived,
    uba.TotalBadgesEarned,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.UserBadgeTier,
    rp.PostId,
    rp.PostTypeId,
    rp.PostCreationDate,
    rp.LastActivityDate,
    COALESCE(rp.Title, 'Untitled Post') AS PostTitle,
    -- Complicated string expression for body snippet
    SUBSTRING(REPLACE(REPLACE(rp.Body, '<p>', ''), '</p>', ' '), 1, 100) || '...' AS BodySnippet,
    rp.Score AS PostScore,
    rp.ViewCount AS PostViewCount,
    rp.ActualAnswerCount AS PostAnswerCount,
    rp.ActualCommentCount AS PostCommentCount,
    rp.ActualFavoriteCount AS PostFavoriteCount,
    rp.ParsedTagsAggregated,
    rp.RawEngagementScore,
    rp.PostEngagementRank,
    rp.PostEngagementTile,
    (EXTRACT(EPOCH FROM (rp.LastPostEditDate - rp.PreviousEditDate)) / 3600)::numeric AS HoursBetweenLastEdits, -- Time in hours
    rp.CloseVotesReceived,
    rp.ReopenVotesReceived,
    -- Correlated subquery: Determine if any highly upvoted comment exists on this post from a user with similar reputation
    EXISTS (
        SELECT 1
        FROM Comments AS co
        JOIN Users AS co_u ON co.UserId = co_u.Id
        WHERE co.PostId = rp.PostId
          AND co.Score > 5
          AND ABS(co_u.Reputation - uas.Reputation) <= 5000 -- Reputation difference within 5000
          AND co.CreationDate > (rp.PostCreationDate - INTERVAL '30 days')
          AND co.CreationDate < (rp.PostCreationDate + INTERVAL '1 year')
    ) AS HasHighRepCommenter,
    -- Outer join for accepted answer details (if the post is a question)
    CASE
        WHEN rp.PostTypeId = 1 THEN COALESCE(aa.Score, -1)
        ELSE NULL
    END AS AcceptedAnswerScore,
    CASE
        WHEN rp.PostTypeId = 1 THEN COALESCE(aa.ViewCount, -1)
        ELSE NULL
    END AS AcceptedAnswerViews,
    CASE
        WHEN rp.PostTypeId = 1 THEN SUBSTRING(REPLACE(REPLACE(COALESCE(aa.Body, 'No Accepted Answer'), '<p>', ''), '</p>', ' '), 1, 50) || '...'
        ELSE NULL
    END AS AcceptedAnswerBodyExcerpt,
    -- Complicated predicate combining multiple factors for "PostHealthCategory"
    CASE
        WHEN rp.PostClosedDate <= CURRENT_TIMESTAMP THEN 'ClosedOrInactive'
        WHEN rp.ReopenVotesReceived > rp.CloseVotesReceived AND rp.PostClosedDate > CURRENT_TIMESTAMP THEN 'ReopenedAndActive'
        WHEN rp.EditCount > 5 AND rp.Score > 100 AND rp.ViewCount > 1000 AND rp.PostTypeId = 1 THEN 'WellMaintainedPopularQuestion'
        WHEN rp.PostTypeId = 2 AND rp.Score > 50 AND rp.OwnerUserId = uas.UserId AND uba.GoldBadges > 0 THEN 'ExpertAnswer'
        ELSE 'StandardActivePost'
    END AS PostHealthCategory,
    -- Complex aggregation with filter on tags for "MostDiscussedLinkedTag"
    (
        SELECT t_agg.TagName
        FROM (
            SELECT
                unnest(string_to_array(SUBSTRING(plp.Tags, 2, LENGTH(plp.Tags) - 2), '><')) AS TagName,
                COUNT(plp.Id) AS TagUseCount
            FROM PostLinks AS pl
            JOIN Posts AS plp ON pl.RelatedPostId = plp.Id
            WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 1
            GROUP BY 1
            ORDER BY TagUseCount DESC, TagName ASC
            LIMIT 1
        ) AS t_agg
    ) AS MostDiscussedLinkedTag,
    NULLIF(LENGTH(TRIM(REPLACE(rp.Body, ' ', ''))), 0) AS BodyTextLengthWithoutSpaces -- Calculation with NULL logic and string functions
FROM UserActivitySummary AS uas
LEFT JOIN UserBadgeAchievements AS uba ON uas.UserId = uba.UserId
INNER JOIN RankedAndFilteredPosts AS rp ON uas.UserId = rp.OwnerUserId -- Using INNER JOIN to focus on users with active ranked posts
LEFT JOIN Posts AS raw_post_for_accepted_ans ON rp.PostId = raw_post_for_accepted_ans.Id AND rp.PostTypeId = 1 -- Get original question post for AcceptedAnswerId
LEFT JOIN Posts AS aa ON raw_post_for_accepted_ans.AcceptedAnswerId = aa.Id AND aa.PostTypeId = 2 -- Accepted Answer details
WHERE uas.Reputation > 7500 -- Minimum reputation for featured users
  AND uas.TotalQuestionsAsked + uas.TotalAnswersGiven > 5 -- At least some content contribution
  AND rp.PostEngagementRank <= 100 -- Top 100 engaged posts per type
  AND rp.PostCreationDate BETWEEN (CURRENT_TIMESTAMP - INTERVAL '2 year') AND CURRENT_TIMESTAMP -- Posts within the last 2 years
  AND (rp.Title ILIKE '%performance%' OR rp.Title ILIKE '%optimization%') -- Specific keywords in title
  AND (rp.ParsedTagsAggregated ILIKE '%<sql>%' OR rp.ParsedTagsAggregated ILIKE '%<database>%') -- Specific technologies
  AND rp.PostClosedDate > (CURRENT_TIMESTAMP - INTERVAL '6 month') -- Only posts not closed or closed very recently
  AND (rp.ActualFavoriteCount IS NULL OR rp.ActualFavoriteCount > 2) -- Null logic for favorite count
ORDER BY uas.Reputation DESC, rp.RawEngagementScore DESC, rp.LastActivityDate DESC
LIMIT 500;
